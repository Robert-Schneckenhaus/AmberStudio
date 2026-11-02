namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Runtime;
using Amber.Screens;
using Amber.Script.Common;
using Amber.Script.Compilation;
using Amber.Player.Content;
using Amber.Player.Screens;

ScreenDefinition DefinitionOr(Optional<ScreenDefinition> found, string name)
{
	if (found is ScreenDefinition definition)
		return definition;

	return ScreenDefinition.Empty(name);
}

/// The script side of an open screen: its loaded chunk (if it has a screen block) and the map the opening thread belonged
/// to.
struct ScreenInstance
{
	bool HasChunk;
	LoadedChunk Chunk;
	bool HasScope;
	ScreenScript Scope;
	int OwnerMap;
}

/// Opens screens (YAML definitions plus their handler scripts), gives them their data (texts, items, words) and runs the
/// native functions the scripts of the screens call. push_screen, pop_screen, say, confirm and the conversation are all
/// implemented on top of it. It works on the session; its tables (instances, chests) are part of the session.
struct ScreenHost
{
	/// The session in a one element array (a struct which holds the session by value cannot be laid out while the session is).
	GameSession[] _session;

	static ScreenHost Of(GameSession session)
	{
		var holder = new GameSession[1];

		holder[0] = session;

		return ScreenHost { _session = holder };
	}

	/// Opens a screen on top of the others. The script thread waits for the result of pop_screen if a thread is given.
	/// Returns false if the screen does not exist.
	bool Open(string name, int[] args, int waitingThread, int ownerMap)
	{
		var content = _session[0].Content;
		var found = content.Screens.Find(name);

		if (found == null)
		{
			Console.WriteErrorLine("screen '" + name + "' does not exist");

			return false;
		}

		var definition = DefinitionOr(found, name);
		int screenId = content.ScreenId(name);
		var instance = ScreenInstance { OwnerMap = ownerMap };

		if (content.ScreenScripts.TryGet(name) is ScreenScript scope)
		{
			var chunk = _session[0].Interpreter().LoadScreen(screenId, scope.Chunk, scope.Sizes);

			for (var i = 0; i < args.Length && chunk.State.IsValidVar(i); i += 1)
				chunk.State.SetVar(i, (int16)args[i]);

			instance.HasChunk = true;
			instance.Chunk = chunk;
			instance.HasScope = true;
			instance.Scope = scope;
		}

		var modal = ScreenModal.Create(definition, args, 10 + _session[0].Modals.Count() * 24, waitingThread, ownerMap);

		_session[0].ScreenInstances.Set(modal.Handle, instance);

		if (instance.HasChunk)
			_session[0].ScreensByChunk.Set(instance.Chunk.Key, modal);

		_session[0].Modals.Push(ref _session[0], modal);

		var context = TriggerContext.Of(TriggerType.ScreenOpen);

		context.MapId = _session[0].MapId();
		context.ScreenId = screenId;
		_session[0].TriggerWith(context);
		RunGroup(modal, definition.OnOpen, 0);

		return true;
	}

	/// The screen was closed (removed from the stack): screen_close, the on_close handler, the chunk is unloaded and the
	/// waiting thread gets the result.
	void Closed(ScreenModal modal)
	{
		var instance = _session[0].ScreenInstances.GetOrDefault(modal.Handle, new ScreenInstance());
		int screenId = _session[0].Content.ScreenId(modal.Definition.Name);
		var context = TriggerContext.Of(TriggerType.ScreenClose);

		context.MapId = _session[0].MapId();
		context.ScreenId = screenId;
		_session[0].TriggerWith(context);
		RunGroup(modal, modal.Definition.OnClose, 0);

		if (instance.HasChunk)
		{
			_session[0].Interpreter().UnloadScreen(instance.Chunk);
			_session[0].ScreensByChunk.Remove(instance.Chunk.Key);
		}

		_session[0].ScreenInstances.Remove(modal.Handle);

		if (modal.WaitingThread() >= 0)
			_session[0].Resume(modal.WaitingThread(), modal.Result());
	}

	/// The open screen of a script thread (ThreadContext.ScreenKey).
	Optional<ScreenModal> Find(int screenKey)
	{
		return _session[0].ScreensByChunk.TryGet(screenKey);
	}

	void RunGroup(ScreenModal screen, string group, int argument)
	{
		if (group == null || !_session[0].ScreenInstances.ContainsKey(screen.Handle))
			return;

		var instance = _session[0].ScreenInstances.GetOrDefault(screen.Handle, new ScreenInstance());
		var host = PrototypeHost.Of(_session[0]);

		if (instance.HasScope && instance.HasChunk && instance.Scope.GroupRefs.ContainsKey(group))
			_session[0].Interpreter().RunGroup(ref host, instance.Chunk, instance.Scope.GroupRefs.GetOrDefault(group, 0), (uint32)argument, instance.OwnerMap);
		else if (_session[0].Content.GlobalGroups.ContainsKey(group))
			_session[0].Interpreter().RunGroup(ref host, _session[0].Interpreter().GlobalChunk(), _session[0].Content.GlobalGroups.GetOrDefault(group, 0), (uint32)argument, instance.OwnerMap);
		else
			Console.WriteErrorLine("screen '" + screen.Definition.Name + "': group '" + group + "' does not exist");
	}

	string ResolveText(string raw, ScreenModal screen)
	{
		if (raw == null || raw.Length == 0)
			return "";

		if (raw.StartsWith("T."))
		{
			if (_session[0].Content.TextByName(raw.Substring(2)) is TextInfo text)
				return text.Text;

			return raw;
		}

		if (raw.StartsWith("$"))
			return ResolveTextId(screen.Arg(raw.Substring(1)));

		return raw;
	}

	string ResolveTextId(int id)
	{
		if (_session[0].Content.Texts.TryGet(id) is TextInfo text)
			return text.Text;

		return "";
	}

	string TextByName(string name)
	{
		if (_session[0].Content.TextByName(name) is TextInfo text)
			return text.Text;

		return "";
	}

	string ResolveSource(string source, ScreenModal screen)
	{
		var content = _session[0].Content;
		var party = _session[0].Party;

		if (source.StartsWith("screen."))
		{
			var parts = source.Substring(7).Split(".");
			int id = screen.Arg(parts[0].ToString());

			if (parts.Length > 1 && parts[1] == "speaker")
			{
				if (content.Texts.TryGet(id) is TextInfo text)
					return text.Speaker;

				return "";
			}

			return ResolveTextId(id);
		}

		if (source == "party.gold")
			return "Gold: " + party.Gold();

		if (source == "chest.gold")
		{
			if (ChestOf(screen) is Chest chest)
				return "Gold: " + chest.Gold();

			return "Gold: 0";
		}

		if (source == "input.message" || source == "shop.message" || source == "party.message")
			return screen.Message();

		if (source.StartsWith("member."))
			return MemberText(source, screen);

		if (source == "party.stats")
			return "Attack " + party.AttackWith(content) + "  Defense " + party.DefenseWith(content);

		if (source == "party.hp")
			return "HP " + party.Hp() + "/" + party.MaxHp;

		if (source == "conversation.title")
		{
			int ownerMap = _session[0].ScreenInstances.ContainsKey(screen.Handle) ? _session[0].ScreenInstances.GetOrDefault(screen.Handle, new ScreenInstance()).OwnerMap : -1;

			if (_session[0].ActorFor((uint16)screen.Arg("npc"), ownerMap) is Actor npc)
				return "Talking to " + Capitalized(npc.Name);

			return "";
		}

		if (source == "party.words.hint")
			return party.KnownWords().Count() == 0 ? "You do not know any words yet." : "";

		Console.WriteErrorLine("unknown data source '" + source + "'");

		return "";
	}

	/// The sources are versioned by their owner: a change of the party or of a chest marks the widgets which show them.
	int64 SourceVersion(string source, ScreenModal screen)
	{
		if (source == "party.gold" || source == "party.words" || source == "party.items" || source == "party.words.hint" || source == "party.hp"
			|| source == "party.stats" || source == "shop.pack")
			return _session[0].Party.Version();

		if (source == "party.members")
			return _session[0].Squad.Version() + _session[0].Party.Version();

		if (source.StartsWith("member."))
			return _session[0].Squad.Version() * 4096 + screen.SelectionVersionOf("members");

		if (source == "chest.gold" || source == "chest.items" || source == "shop.items")
		{
			if (ChestOf(screen) is Chest chest)
				return chest.Version();

			return 0;
		}

		if (source == "input.message" || source == "shop.message" || source == "party.message")
			return screen.MessageVersion();

		return 0;
	}

	/// The bars of the party: the prototype has one hero (slot 1) with hit points and no spell points.
	IntPair Bar(string kind, int slot)
	{
		if (kind == "hp" && slot == 1)
			return IntPair { First = _session[0].Party.Hp(), Second = _session[0].Party.MaxHp };

		return IntPair { First = 0, Second = 0 };
	}

	Optional<Chest> ChestOf(ScreenModal screen)
	{
		return _session[0].ChestOf(screen.Arg("chest"));
	}


	/// The values, gear and spells of the companion selected in the list "members" of the party screen.
	string MemberText(string source, ScreenModal screen)
	{
		var content = _session[0].Content;

		if (screen.SelectedOf("members") is not ListRow row)
			return "";

		int index = _session[0].Squad.IndexOf(row.Value);

		if (index < 0)
			return "";

		var member = _session[0].Squad.Members.Get(index);

		if (source == "member.stats")
			return Capitalized(member.Info.Role) + "  Att " + member.Attack(content) + "  Def " + member.Defense(content);

		if (source == "member.gear")
		{
			string weapon = member.Weapon > 0 ? content.Items.GetOrDefault(member.Weapon, new ItemInfo()).Name : "-";
			string armor = member.Armor > 0 ? content.Items.GetOrDefault(member.Armor, new ItemInfo()).Name : "-";

			return weapon + ", " + armor;
		}

		if (source == "member.spells")
		{
			var names = List<string>.Create();

			foreach (var spell in member.Spells)
				names.Add(content.Spells.GetOrDefault(spell, new SpellInfo()).Name);

			return names.Count() == 0 ? "No spells" : JoinList(", ", names);
		}

		return "";
	}

	ListRow[] Rows(string source, ScreenModal screen)
	{
		var content = _session[0].Content;

		if (source == "party.words")
		{
			var rows = List<ListRow>.Create();

			foreach (var id in _session[0].Party.KnownWords())
				rows.Add(ListRow.Of(id, content.Keywords.GetOrDefault(id, "?")));

			return ArrayOf(rows);
		}

		if (source == "party.items")
			return ItemRows(_session[0].Party.Items());

		if (source == "chest.items")
		{
			if (ChestOf(screen) is Chest chest)
				return ItemRows(chest.Items());

			return new ListRow[0];
		}

		if (source == "shop.items")
		{
			if (ChestOf(screen) is Chest stock)
				return PricedRows(stock.Items(), false);

			return new ListRow[0];
		}

		if (source == "shop.pack")
			return PricedRows(_session[0].Party.Items(), true);

		if (source == "party.members")
		{
			var rows = List<ListRow>.Create();

			foreach (var member in _session[0].Squad.Members)
				rows.Add(ListRow.Of(member.Info.Id, member.Info.Name + " " + member.Hp + "/" + member.Info.Hp));

			return ArrayOf(rows);
		}

		Console.WriteErrorLine("unknown list source '" + source + "'");

		return new ListRow[0];
	}

	ListRow[] ItemRows(SortedCounts items)
	{
		var rows = List<ListRow>.Create();

		foreach (var id in items.Keys())
		{
			var item = _session[0].Content.Items.GetOrDefault(id, new ItemInfo());

			rows.Add(ListRow { Value = id, Label = item.Name + " x" + items.Get(id), Detail = item.Description, Icon = item.Icon, Count = items.Get(id) });
		}

		return ArrayOf(rows);
	}

	/// What the merchant asks for an item, or pays for it (half, at least 1); 0 if the item is not traded.
	int PriceOf(int item, bool selling)
	{
		int price = _session[0].Content.Items.GetOrDefault(item, new ItemInfo()).Price;

		return selling && price > 0 ? Max(1, price / 2) : price;
	}

	ListRow[] PricedRows(SortedCounts items, bool selling)
	{
		var rows = List<ListRow>.Create();

		foreach (var id in items.Keys())
		{
			var item = _session[0].Content.Items.GetOrDefault(id, new ItemInfo());
			int price = PriceOf(id, selling);

			rows.Add(ListRow
			{
				Value = id, Label = item.Name + " x" + items.Get(id) + " " + (price > 0 ? price + "g" : "-"), Detail = item.Description, Icon = item.Icon,
				Count = items.Get(id)
			});
		}

		return ArrayOf(rows);
	}

	void Trade(Optional<ScreenModal> screen, int item, bool buying)
	{
		if (screen is ScreenModal modal)
		{
			if (ChestOf(modal) is Chest stock)
				TradeWith(modal, stock, item, buying);
		}
	}

	void TradeWith(ScreenModal modal, Chest stock, int item, bool buying)
	{
		int price = PriceOf(item, !buying);
		var party = _session[0].Party;

		if (price == 0)
			modal.SetMessage(TextByName("shop_not_bought"));
		else if (buying && party.Gold() < price)
			modal.SetMessage(TextByName("shop_no_gold"));
		else if (buying ? stock.Count(item) == 0 : party.Count(item) == 0)
			return;
		else if (buying)
		{
			stock.Remove(item, 1);
			party.AddItem(item, 1);
			party.SetGold(party.Gold() - price);
			modal.SetMessage("");
		}
		else
		{
			party.RemoveItem(item, 1);
			stock.Add(item, 1);
			party.SetGold(party.Gold() + price);
			modal.SetMessage("");
		}
	}

	/// Runs a native function of the scripts (native action). The screen of the calling thread and the trigger argument
	/// give the context.
	ActionOutcome CallNative(string name, const ref ThreadContext context)
	{
		var screen = Find(context.ScreenKey);

		if (name == "pop_arg")
		{
			// closes the topmost screen with the value the handler was started with (the selected row)
			_session[0].Modals.PopScreen((int)(int16)(int)context.TriggerArg);

			return ActionOutcome.Done;
		}

		if (name == "conversation_ask")
		{
			TriggerAtNpc(screen, TriggerType.Keyword, (int)context.TriggerArg, false);

			return ActionOutcome.Done;
		}

		if (name == "conversation_ask_result")
		{
			TriggerAtNpc(screen, TriggerType.Keyword, (int)context.Result, false);

			return ActionOutcome.Done;
		}

		if (name == "lookup_word")
		{
			LookupWord(screen);

			return ActionOutcome.Done;
		}

		if (name == "chest_take" || name == "chest_put")
		{
			MoveItem(screen, (int)context.TriggerArg, name == "chest_take");

			return ActionOutcome.Done;
		}

		if (name == "chest_take_all")
		{
			TakeAll(screen);

			return ActionOutcome.Done;
		}

		if (name == "chest_take_gold")
		{
			TakeGold(screen);

			return ActionOutcome.Done;
		}

		if (name == "chest_close")
		{
			// the result tells the script whether the chest was emptied
			bool empty = false;

			if (screen is ScreenModal modal)
			{
				if (ChestOf(modal) is Chest chest)
					empty = chest.IsEmpty();
			}

			_session[0].Modals.PopScreen(empty ? 1 : 0);

			return ActionOutcome.Done;
		}

		if (name == "party_give" || name == "party_take_off")
		{
			if (screen is ScreenModal partyScreen)
			{
				if (partyScreen.SelectedOf("members") is ListRow member)
				{
					var squad = _session[0].Squad;

					partyScreen.SetMessage(name == "party_give" ? squad.Use(_session[0], member.Value, (int)context.TriggerArg) : squad.TakeOff(_session[0], member.Value));
				}
				else
					partyScreen.SetMessage("You have no companions yet.");
			}

			return ActionOutcome.Done;
		}

		if (name == "shop_buy" || name == "shop_sell")
		{
			Trade(screen, (int)context.TriggerArg, name == "shop_buy");

			return ActionOutcome.Done;
		}

		if (name == "conversation_give")
		{
			TriggerAtNpc(screen, TriggerType.GiveItem, (int)context.Result, true);

			return ActionOutcome.Done;
		}

		if (name == "conversation_show")
		{
			TriggerAtNpc(screen, TriggerType.ShowItem, (int)context.Result, true);

			return ActionOutcome.Done;
		}

		Console.WriteErrorLine("native '" + name + "' is not implemented");

		return ActionOutcome.Done;
	}

	/// The typed word of the input screen: a known word closes the screen with its ID, anything else gives a message.
	void LookupWord(Optional<ScreenModal> screen)
	{
		if (screen is ScreenModal modal)
		{
			string typed = modal.InputText().Trim().ToString();

			if (typed.Length == 0)
				return;

			int match = -1;

			foreach (var pair in _session[0].Content.Keywords.Entries())
			{
				if (match < 0 && pair.Value.ToLower() == typed.ToLower())
					match = pair.Key;
			}

			if (match < 0)
				modal.SetMessage(TextByName("word_unknown"));
			else if (!_session[0].Party.Knows(match))
				modal.SetMessage(TextByName("word_not_learned"));
			else
				_session[0].Modals.PopScreen(match);
		}
	}

	void MoveItem(Optional<ScreenModal> screen, int item, bool fromChest)
	{
		if (screen is ScreenModal modal)
		{
			if (ChestOf(modal) is Chest chest)
			{
				int count = fromChest ? chest.Count(item) : _session[0].Party.Count(item);

				if (count == 0)
					return;

				if (fromChest)
				{
					chest.Remove(item, count);
					_session[0].Party.AddItem(item, count);
				}
				else
				{
					_session[0].Party.RemoveItem(item, count);
					chest.Add(item, count);
				}
			}
		}
	}

	void TakeAll(Optional<ScreenModal> screen)
	{
		if (screen is ScreenModal modal)
		{
			if (ChestOf(modal) is Chest chest)
			{
				foreach (var id in chest.Items().Keys())
					MoveItem(screen, id, true);

				TakeGold(screen);
			}
		}
	}

	void TakeGold(Optional<ScreenModal> screen)
	{
		if (screen is ScreenModal modal)
		{
			if (ChestOf(modal) is Chest chest)
			{
				if (chest.Gold() == 0)
					return;

				_session[0].Party.SetGold(_session[0].Party.Gold() + chest.Gold());
				chest.SetGold(0);
			}
		}
	}

	void TriggerAtNpc(Optional<ScreenModal> screen, TriggerType type, int argument, bool reportIgnored)
	{
		if (screen is ScreenModal modal)
		{
			if (!_session[0].ScreenInstances.ContainsKey(modal.Handle))
				return;

			var instance = _session[0].ScreenInstances.GetOrDefault(modal.Handle, new ScreenInstance());

			if (_session[0].ActorFor((uint16)modal.Arg("npc"), instance.OwnerMap) is Actor npc)
			{
				int started = _session[0].Trigger(type, npc.TileX(), npc.TileY(), -1, -1, npc.Id(), -1, argument);

				if (started == 0 && reportIgnored)
					_session[0].Hud.ShowNotice(Capitalized(npc.Name) + " is not interested.", 100);
			}
		}
	}
}
