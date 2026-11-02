namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Runtime;
using Amber.Script.Common;
using Amber.Player.Content;
using Amber.Player.Screens;
using Amber.Player.Tiled;

/// The native side of the script language: everything the interpreter does not handle itself (dialogs, items, the world,
/// time) is executed here on the game session.
struct PrototypeHost : IGameHost
{
	/// The session in a one element array (see ScreenHost).
	GameSession[] _session;

	static PrototypeHost Of(GameSession session)
	{
		var holder = new GameSession[1];

		holder[0] = session;

		return PrototypeHost { _session = holder };
	}

	ActionOutcome Execute(ActionOp op, uint16[] operands, const ref ThreadContext context)
	{
		var session = _session[0];
		var content = session.Content;
		int threadId = context.ThreadId;

		if (op == ActionOp.LearnWord)
		{
			if (session.Party.Learn((int)operands[0]))
				session.Hud.ShowNotice("New word: " + content.Keywords.GetOrDefault((int)operands[0], "?"), 150);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.GiveItem)
		{
			session.Party.AddItem((int)operands[0], (int)operands[1]);
			session.Hud.ShowNotice("Received: " + content.Items.GetOrDefault((int)operands[0], new ItemInfo()).Name + (operands[1] > 1 ? " x" + operands[1] : ""), 150);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.TakeItem)
		{
			session.Party.RemoveItem((int)operands[0], (int)operands[1]);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.GiveGold)
		{
			int amount = (int)Wire.Combine(operands[0], operands[1]);

			session.Party.SetGold(session.Party.Gold() + amount);
			session.Hud.ShowNotice("Received: " + amount + " gold", 150);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.TakeGold)
		{
			session.Party.SetGold(Max(0, session.Party.Gold() - (int)Wire.Combine(operands[0], operands[1])));

			return ActionOutcome.Done;
		}

		if (op == ActionOp.Say || op == ActionOp.SayPicture)
		{
			// say is push_screen(S.textbox, ...) which waits for the end of the text
			return OpenAndWait("textbox", new int[] { (int)operands[op == ActionOp.Say ? 0 : 1] }, threadId, context.OwnerMap);
		}

		if (op == ActionOp.Confirm)
			return OpenAndWait("confirmation", new int[] { (int)operands[0] }, threadId, context.OwnerMap);

		if (op == ActionOp.Bark)
		{
			if (session.ActorFor(operands[0], context.OwnerMap) is Actor actor)
				session.ShowBark(actor, content.Texts.GetOrDefault((int)operands[1], new TextInfo()).Text);

			return ActionOutcome.Done;
		}

		// the fight runs in real time on the map (Combat); its end (0 won, 1 fled, 2 lost) is the result of the action
		if (op == ActionOp.Battle)
		{
			if (content.Groups.TryGet((int)operands[0]) is MonsterGroupInfo group)
			{
				session.Combat.Start(session, group, threadId);

				return ActionOutcome.Blocked;
			}

			Console.WriteErrorLine("battle: the monster group " + operands[0] + " does not exist");

			return ActionOutcome.Done;
		}

		if (op == ActionOp.AddMember)
		{
			if (session.Squad.Join(session, (int)operands[0], 0) is error failure)
				Console.WriteErrorLine(failure.Message);
			else if (session.Content.Companions.TryGet((int)operands[0]) is CompanionInfo joined)
				session.Hud.ShowNotice(joined.Name + " joins you.", 150);

			return ActionOutcome.Done;
		}

		// teach_spell(target, SP.x): the party slots 2..6 (target 5..9) are the companions in the order they joined
		if (op == ActionOp.TeachSpell)
		{
			int slot = (int)operands[0] - 4;

			if (slot >= 1 && slot - 1 < session.Squad.Members.Count())
				session.Squad.Teach(session, session.Squad.Members.Get(slot - 1).Info.Id, (int)operands[1]);
			else if ((int)operands[0] == 2)
			{
				foreach (var member in ArrayOf(session.Squad.Members))
				{
					if (CanLearn(member.Info.Role, content.Spells.GetOrDefault((int)operands[1], new SpellInfo()).Kind))
						session.Squad.Teach(session, member.Info.Id, (int)operands[1]);
				}
			}

			return ActionOutcome.Done;
		}

		if (op == ActionOp.RemoveMember)
		{
			session.Squad.Leave(session, (int)operands[0]);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.Heal)
		{
			session.Party.SetHp(operands[1] == 0x7FFF ? session.Party.MaxHp : session.Party.Hp() + (int)(int16)operands[1]);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.Damage)
		{
			session.Party.SetHp(Max(1, session.Party.Hp() - (int)(int16)operands[1]));

			return ActionOutcome.Done;
		}

		if (op == ActionOp.PushScreen)
			return PushScreen(operands, threadId, context.OwnerMap);

		if (op == ActionOp.PopScreen)
		{
			session.Modals.PopScreen((int)(int16)operands[0]);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.SetNode || op == ActionOp.SetText || op == ActionOp.ShowNode || op == ActionOp.HideNode || op == ActionOp.EnableNode
			|| op == ActionOp.DisableNode)
		{
			SetNode(op, operands, context.ScreenKey);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.Native)
		{
			string native = content.NativeName((int)operands[0]);

			if (native == null)
				return ActionOutcome.Done;

			return ScreenHost.Of(session).CallNative(native, context);
		}

		if (op == ActionOp.SetTile)
		{
			int x = operands[1] == Wire.Here ? (int)context.TriggerX : (int)operands[1];
			int y = operands[2] == Wire.Here ? (int)context.TriggerY : (int)operands[2];
			var owner = session.RuntimeFor(context.OwnerMap);
			string layer = LayerNames[(int)operands[0]];
			uint32 tile = Wire.IsRelativeTile(operands[3])
				? (uint32)((int)GidOf(owner.World.Map.GetTile(layer, x, y)) + Wire.RelativeTileDelta(operands[3]))
				: (uint32)operands[3];

			owner.World.Map.SetTile(layer, x, y, tile);

			if (owner.Same(session.Current()))
				session.View.InvalidateTiles();

			return ActionOutcome.Done;
		}

		if (op == ActionOp.ApplyDelta)
		{
			if (content.Deltas.TryGet((int)operands[0]) is DeltaInfo delta)
				ApplyDelta(delta, session.RuntimeFor(context.OwnerMap));

			return ActionOutcome.Done;
		}

		if (op == ActionOp.Teleport)
		{
			// read the operands first: switching the map loads other script chunks
			int mapId = (int)operands[0];
			int x = (int)operands[1];
			int y = (int)operands[2];
			bool hasFacing = operands[3] < 4;

			if (!(session.MapById(mapId) is MapRuntime))
			{
				Console.WriteErrorLine("teleport: map " + mapId + " does not exist");

				return ActionOutcome.Done;
			}

			session.SwitchMap(mapId, x, y, hasFacing, hasFacing ? (Direction)(int)operands[3] : Direction.Down, threadId, true);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.Spawn)
		{
			if (session.ActorFor(operands[0], context.OwnerMap) is Actor actor)
			{
				actor.PlaceAt(operands[1] == Wire.Here ? (int)context.TriggerX : (int)operands[1], operands[2] == Wire.Here ? (int)context.TriggerY : (int)operands[2]);
				actor.SetVisible(true);
			}

			return ActionOutcome.Done;
		}

		if (op == ActionOp.Despawn)
		{
			if (session.ActorFor(operands[0], context.OwnerMap) is Actor actor)
				actor.SetVisible(false);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.SetDir)
		{
			if (session.ActorFor(operands[0], context.OwnerMap) is Actor actor)
			{
				if (operands[1] < 4)
					actor.SetFacing((Direction)(int)operands[1]);
			}

			return ActionOutcome.Done;
		}

		if (op == ActionOp.SetRoutine)
		{
			int entityId = (int)operands[0];
			int routineId = (int)operands[1];
			var owner = session.RuntimeFor(context.OwnerMap);

			foreach (var brain in owner.Brains)
			{
				if (brain.Actor.Id() == entityId)
				{
					brain.SetRoutine(owner.RoutineById(routineId));

					break;
				}
			}

			return ActionOutcome.Done;
		}

		if (op == ActionOp.AdvanceTime)
		{
			session.AddMinutes((int)operands[0]);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.SetPalette || op == ActionOp.FadePalette)
		{
			// the palette of the map the rule belongs to (spec 5.7); 0xFFFF releases it (back to day and night)
			var look = session.MapOrCurrent(context.OwnerMap).Look;
			bool release = operands[0] == Wire.None;
			var palette = look.Day;

			if (!release)
			{
				if (content.Palettes.TryGet((int)operands[0]) is Palette found)
					palette = found;
				else
				{
					Console.WriteErrorLine(ActionOpName(op) + ": the palette " + operands[0] + " does not exist");

					return ActionOutcome.Done;
				}
			}

			if (op == ActionOp.SetPalette)
			{
				look.SetPalette(release, palette);

				return ActionOutcome.Done;
			}

			bool nowait = ((int)operands[2] & 1) != 0 || operands[1] == 0;
			int previous = look.FadePalette(release, palette, (int)operands[1], nowait ? -1 : threadId);

			if (previous >= 0)
				session.Resume(previous, 0);

			return nowait ? ActionOutcome.Done : ActionOutcome.Blocked;
		}

		if (op == ActionOp.Flash)
		{
			// the color is a 12 bit color 0xRGB like on the Amiga
			int rgb = (int)operands[0];
			uint32 color = (uint32)(((rgb >> 8) & 15) * 17) << 16 | (uint32)(((rgb >> 4) & 15) * 17) << 8 | (uint32)((rgb & 15) * 17);

			session.Current().Look.Flash(color, (int)operands[1]);

			return ActionOutcome.Done;
		}

		if (op == ActionOp.Music || op == ActionOp.Sfx || op == ActionOp.Fade || op == ActionOp.Shake || op == ActionOp.Autosave)
			return ActionOutcome.Done;

		Console.WriteErrorLine("action " + ActionOpName(op) + " is not supported by the prototype");

		return ActionOutcome.Done;
	}

	bool Evaluate(ConditionOp op, uint16[] operands, const ref ThreadContext context)
	{
		var session = _session[0];

		if (op == ConditionOp.HasMember)
			return session.Squad.Has((int)operands[0]);

		if (op == ConditionOp.WordKnown)
			return session.Party.Knows((int)operands[0]);

		if (op == ConditionOp.HasItem)
			return session.Party.Count((int)operands[0]) >= (int)operands[1];

		if (op == ConditionOp.Gold)
			return CompareValues((int64)session.Party.Gold(), operands[0], (int64)Wire.Combine(operands[1], operands[2]));

		if (op == ConditionOp.HourIn)
		{
			int hour = session.Clock.Hour();
			int from = (int)operands[0];
			int to = (int)operands[1];

			return from <= to ? hour >= from && hour < to : hour >= from || hour < to;
		}

		if (op == ConditionOp.InMap)
			return (int)operands[0] == session.MapId();

		if (op == ConditionOp.PartySize)
			return CompareValues(1, operands[0], (int64)(int16)operands[1]);

		if (op == ConditionOp.TileIs)
		{
			int x = operands[1] == Wire.Here ? (int)context.TriggerX : (int)operands[1];
			int y = operands[2] == Wire.Here ? (int)context.TriggerY : (int)operands[2];

			return GidOf(session.RuntimeFor(context.OwnerMap).World.Map.GetTile(LayerNames[(int)operands[0]], x, y)) == (uint32)operands[3];
		}

		if (op == ConditionOp.Near)
		{
			if (session.ActorFor(operands[0], context.OwnerMap) is Actor actor)
			{
				var player = session.Player;

				return actor.Visible() && Abs(actor.TileX() - player.TileX()) + Abs(actor.TileY() - player.TileY()) <= (int)operands[1];
			}

			return false;
		}

		if (op == ConditionOp.Facing)
			return (int)session.Player.Facing() == (int)operands[0];

		return false;
	}

	ActionOutcome OpenAndWait(string screen, int[] args, int threadId, int ownerMap)
	{
		return ScreenHost.Of(_session[0]).Open(screen, args, threadId, ownerMap) ? ActionOutcome.Blocked : ActionOutcome.Done;
	}

	/// push_screen(screen, flags, argc, args...): the thread waits for pop_screen unless the nowait flag (bit 0) is set.
	ActionOutcome PushScreen(uint16[] operands, int threadId, int ownerMap)
	{
		string name = _session[0].Content.ScreenName((int)operands[0]);

		if (name == null)
		{
			Console.WriteErrorLine("screen " + operands[0] + " does not exist");

			return ActionOutcome.Done;
		}

		int argc = (int)operands[2];
		var args = new int[argc];

		for (var i = 0; i < argc; i += 1)
			args[i] = (int)operands[3 + i];

		bool wait = (operands[1] & 1) == 0;

		return ScreenHost.Of(_session[0]).Open(name, args, wait ? threadId : -1, ownerMap) && wait ? ActionOutcome.Blocked : ActionOutcome.Done;
	}

	/// set_node, set_text, show_node ...: change a node of the screen the running rule belongs to.
	void SetNode(ActionOp op, uint16[] operands, int screenKey)
	{
		if (ScreenHost.Of(_session[0]).Find(screenKey) is ScreenModal screen)
		{
			if (screen.FindNode((int)operands[0]) is Widget widget)
			{
				if (op == ActionOp.ShowNode)
					widget.SetVisible(true);
				else if (op == ActionOp.HideNode)
					widget.SetVisible(false);
				else if (op == ActionOp.EnableNode)
					widget.SetEnabled(true);
				else if (op == ActionOp.DisableNode)
					widget.SetEnabled(false);
				else if (op == ActionOp.SetText)
					widget.SetTextId((int)operands[1]);
				else if (op == ActionOp.SetNode)
				{
					// properties: 0 visible, 1 enabled, 2 text ID (3 icon and 4 value are not used by the prototype)
					if (operands[1] == 0)
						widget.SetVisible(operands[2] != 0);
					else if (operands[1] == 1)
						widget.SetEnabled(operands[2] != 0);
					else if (operands[1] == 2)
						widget.SetTextId((int)operands[2]);
				}
			}
		}
	}

	void ApplyDelta(DeltaInfo delta, MapRuntime owner)
	{
		var map = owner.World.Map;

		foreach (var tile in delta.Tiles)
			map.SetTile(LayerNames[tile.Layer], tile.X, tile.Y, tile.Tile);

		for (var y = delta.UnblockY; y < delta.UnblockY + delta.UnblockHeight; y += 1)
		{
			for (var x = delta.UnblockX; x < delta.UnblockX + delta.UnblockWidth; x += 1)
				map.SetBlocked(x, y, false);
		}

		if (owner.Same(_session[0].Current()))
			_session[0].View.InvalidateTiles();
	}
}

bool CompareValues(int64 a, uint16 comparison, int64 b)
{
	var kind = (Comparison)(int)comparison;

	if (kind == Comparison.Equal)
		return a == b;

	if (kind == Comparison.NotEqual)
		return a != b;

	if (kind == Comparison.Less)
		return a < b;

	if (kind == Comparison.LessOrEqual)
		return a <= b;

	if (kind == Comparison.Greater)
		return a > b;

	if (kind == Comparison.GreaterOrEqual)
		return a >= b;

	return false;
}
