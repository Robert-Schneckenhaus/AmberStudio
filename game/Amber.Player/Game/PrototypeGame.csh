namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Pack;
using Amber.Runtime;
using Amber.Screens;
using Amber.Script.Common;
using Amber.Script.Compilation;
using Amber.Player.Content;
using Amber.Player.Game.Ui;
using Amber.Player.Graphics;
using Amber.Player.Platform;
using Amber.Player.Screens;
using Amber.Player.Tiled;


struct GameValues
{
	int HelpTicks;
	bool QuitRequested;
	int RedrawMark;
}

/// The prototype game: the maps with the player and the NPCs, the events written in AmberScript and the screens.
struct PrototypeGame
{
	GameValues[] _s;
	LaunchOptions Options;
	GameSession Session;

	bool QuitRequested()
	{
		return _s[0].QuitRequested;
	}

	static Error<PrototypeGame> Load(LaunchOptions options)
	{
		InstantText = options.Script != null;

		string contentDirectory = options.Content != null ? options.Content : DefaultContent();
		var content = try LoadContent(options, contentDirectory);
		var player = Actor.Create("player", -1, try CreateArt(content, "player", Color.Of(60, 110, 200), Color.Of(110, 70, 40)));
		var arts = Dictionary<string, ActorArt>.Create();
		var runtimes = List<MapRuntime>.Create();

		foreach (var script in content.Maps)
		{
			var tiled = try TiledLoader.Load(Path.Combine(Path.Combine(contentDirectory, "maps"), script.Name + ".tmx"));
			var world = GameWorld.Create(WorldMap.Create(tiled), player);

			world.Actors.Clear();

			foreach (var entity in script.Entities)
			{
				if (!arts.ContainsKey(entity.Name))
					arts.Set(entity.Name, try CreateArt(content, entity.Name, DummyBody(entity.Name), DummyHair(entity.Name)));

				var actor = Actor.Create(entity.Name, entity.Id, arts.GetOrDefault(entity.Name, new ActorArt()));

				actor.PlaceAt(entity.X, entity.Y);
				world.Actors.Add(actor);
			}

			runtimes.Add(MapRuntime.Create(script.Name, content.MapIds.GetOrDefault(script.Name, -1), content.Places.GetOrDefault(script.Name, script.Name), world, script));
		}

		var iconList = List<int>.Create();

		foreach (var item in content.Items.Values())
		{
			if (item.Icon >= 0 && !iconList.Contains(item.Icon))
				iconList.Add(item.Icon);
		}

		var missingSprites = List<string>.Create();
		var sprites = LoadUiSprites(content.Theme, Path.Combine(RepositoryRoot, "assets"), missingSprites);

		if (missingSprites.Count() > 0)
		{
			var shown = List<string>.Create();

			for (var i = 0; i < missingSprites.Count() && i < 5; i += 1)
				shown.Add(missingSprites.Get(i));

			Console.WriteErrorLine("ui theme: " + missingSprites.Count() + " sprite(s) not found (" + JoinList(", ", shown) + (missingSprites.Count() > 5 ? ", ..." : "")
				+ "); looks which need them fall back.");
		}

		var view = WorldView.Create();
		var icons = try LoadIcons(content.IconSheetPath, iconList);
		var session = GameSession.Create(content, Party.Create(content.Hero), GameClock.Create(9, 0), player, view, UiKit { Theme = content.Theme, Sprites = sprites, Icons = icons });

		foreach (var created in runtimes)
		{
			// the look is part of the map runtime, so it is set before the runtime is copied into the session
			var runtime = created;

			view.AddWorld(runtime);
			runtime.Look = try CreateLook(content, runtime, view.ImagesOf(runtime), player);
			session.Maps.Add(runtime);

			foreach (var entity in runtime.Script.Entities)
			{
				if (runtime.World.FindActor(entity.Name) is Actor actor)
				{
					var brain = NpcBrain.Create(actor, runtime.World);

					brain.SetRoutine(runtime.RoutineOfEntity(entity.Id));
					runtime.Brains.Add(brain);
				}
			}
		}

		// the start of a new game: tables.yaml start: (the map and the cell), else the first map at its middle
		string startName = content.Hero.StartMap.Length > 0 ? content.Hero.StartMap : content.Maps.Count() > 0 ? content.Maps.Get(0).Name : "";

		if (!(session.MapByName(startName) is MapRuntime))
			return error("The content has no map '" + startName + "'.", (int)ErrorKind.InvalidData);

		var start = session.MapOrCurrent(content.MapIds.GetOrDefault(startName, -1));
		var interpreter = Interpreter.Create(content.GlobalScript, content.GlobalSizes, content.Limits);

		session.SetCurrent(start);
		start.World.Actors.Add(player);
		int startX = content.Hero.StartX >= 0 ? content.Hero.StartX : start.World.Map.Tiled.Width / 2;
		int startY = content.Hero.StartY >= 0 ? content.Hero.StartY : start.World.Map.Tiled.Height / 2;

		player.PlaceAt(startX, startY);
		player.SetFacing(Direction.Up);
		view.SetWorld(start);

		// only the map the party is on is loaded; the others are loaded when the party arrives
		interpreter.LoadMap(start.MapId, start.Script.Script, start.Sizes());
		session.SetInterpreter(interpreter);
		session.TriggerSimple(TriggerType.MapEnter);

		var state = new GameValues[1];

		state[0].HelpTicks = 1500;

		return PrototypeGame { _s = state, Options = options, Session = session };
	}

	/// Debug commands of input scripts ("warp x y", "time hh:mm", "expect ..."). A failed expectation is the error.
	Error<void> Debug(string command)
	{
		var parts = SplitWhitespace(command);
		var session = Session;

		if (parts.Length == 0)
			return;

		if (parts[0] == "hp")
			session.Party.SetHp(try DebugNumber(parts, 1));
		else if (parts[0] == "warp")
			session.World().Player.PlaceAt(try DebugNumber(parts, 1), try DebugNumber(parts, 2));
		else if (parts[0] == "map")
		{
			if (parts.Length < 4)
				return error("map needs a name and a position: " + command, (int)ErrorKind.InvalidData);

			if (session.MapByName(parts[1]) is MapRuntime target)
				try session.SwitchMap(target.MapId, try DebugNumber(parts, 2), try DebugNumber(parts, 3), true, Direction.Up, -1, true);
			else
				return error("There is no map '" + parts[1] + "'.", (int)ErrorKind.InvalidOperation);
		}
		else if (parts[0] == "time")
		{
			var time = SplitToList(parts.Length > 1 ? parts[1] : "", ":");
			int hours = -1;
			int minutes = -1;

			if (time.Count() == 2)
			{
				if (TryParseInt(time.Get(0)) is int h)
					hours = h;

				if (TryParseInt(time.Get(1)) is int m)
					minutes = m;
			}

			if (hours < 0 || minutes < 0)
				return error("time needs hh:mm: " + command, (int)ErrorKind.InvalidData);

			int target = hours * 60 + minutes;
			int now = session.Clock.MinuteOfDay();

			session.AddMinutes((target - now + 24 * 60) % (24 * 60));
		}
		else if (parts[0] == "member")
		{
			// "member add bram" / "member remove bram": a companion joins or leaves without a script (tests)
			string key = try DebugText(parts, 2);

			if (session.Content.Symbols.TryResolve(SymbolKind.Character, key) is not uint16 id)
				return error("Unknown companion in '" + command + "'.", (int)ErrorKind.InvalidData);

			if (try DebugText(parts, 1) == "add")
				try session.Squad.Join(session, (int)id, 0);
			else
				session.Squad.Leave(session, (int)id);
		}
		else if (parts[0] == "expect")
			try Expect(parts, command);

		return;
	}

	Error<void> Expect(string[] parts, string command)
	{
		if (parts.Length < 2)
			return error("Unknown expectation '" + command + "'.", (int)ErrorKind.InvalidOperation);

		var session = Session;
		var content = session.Content;
		var player = session.World().Player;
		string what = parts[1];
		string actual = "";
		string expected = "";

		if (what == "gold")
		{
			actual = "" + session.Party.Gold();
			expected = try DebugText(parts, 2);
		}
		else if (what == "hp")
		{
			// "expect hp 30", or "expect hp >0" for more than a number
			expected = try DebugText(parts, 2);
			actual = "" + session.Party.Hp();

			if (expected.StartsWith(">"))
			{
				if (TryParseInt(expected.Substring(1)) is int limit)
				{
					if (session.Party.Hp() > limit)
						actual = expected;
				}
			}
		}
		else if (what == "item")
		{
			string key = try DebugText(parts, 2);
			int id = -1;

			foreach (var item in content.Items.Values())
			{
				if (id < 0 && item.Key == key)
					id = item.Id;
			}

			if (id < 0)
				return error("Unknown item in '" + command + "'.", (int)ErrorKind.InvalidOperation);

			actual = "" + session.Party.Count(id);
			expected = try DebugText(parts, 3);
		}
		else if (what == "word")
		{
			actual = session.Party.Knows(content.KeywordId(try DebugText(parts, 2))) ? "1" : "0";
			expected = try DebugText(parts, 3);
		}
		else if (what == "flag")
		{
			// a flag of the current map, or a global one
			string name = try DebugText(parts, 2);
			var map = session.Current();
			int local = content.FlagIndex(map.Name, name);
			int global = content.FlagIndex(null, name);

			bool value = false;

			if (local >= 0)
			{
				if (session.StateOfMap(map.MapId) is StateStore store)
					value = store.GetFlag(local);
			}
			else if (global >= 0)
				value = session.Interpreter().Global().GetFlag(global);
			else
				return error("Unknown flag in '" + command + "'.", (int)ErrorKind.InvalidOperation);

			actual = value ? "1" : "0";
			expected = try DebugText(parts, 3);
		}
		else if (what == "at")
		{
			actual = player.TileX() + "," + player.TileY();
			expected = (try DebugText(parts, 2)) + "," + (try DebugText(parts, 3));
		}
		else if (what == "blocked")
		{
			actual = session.World().Map.IsBlocked(try DebugNumber(parts, 2), try DebugNumber(parts, 3)) ? "1" : "0";
			expected = try DebugText(parts, 4);
		}
		else if (what == "map")
		{
			actual = session.Current().Name;
			expected = try DebugText(parts, 2);
		}
		else if (what == "modals")
		{
			actual = session.Modals.Any() ? "1" : "0";
			expected = try DebugText(parts, 2);
		}
		else if (what == "member")
		{
			// "expect member bram 1" (in the party) or "expect member bram hp 12"
			string key = try DebugText(parts, 2);
			int id = (int)(session.Content.Symbols.TryResolve(SymbolKind.Character, key) ?? (uint16)0);

			actual = session.Squad.Has(id) ? "1" : "0";
			expected = try DebugText(parts, 3);

			if (expected == "weapon" || expected == "armor" || expected == "spell")
			{
				// "expect member wren weapon hunting_bow", "expect member sela spell fire_blast 1"
				string what2 = expected;
				int index = session.Squad.IndexOf(id);

				expected = try DebugText(parts, 4);
				actual = "-";

				if (index >= 0)
				{
					var member = session.Squad.Members.Get(index);

					if (what2 == "spell")
					{
						int spell = (int)(session.Content.Symbols.TryResolve(SymbolKind.Spell, expected) ?? (uint16)0);

						actual = member.Spells.Contains(spell) ? "1" : "0";
						expected = try DebugText(parts, 5);
					}
					else
					{
						int item = what2 == "weapon" ? member.Weapon : member.Armor;

						actual = item > 0 ? session.Content.Items.GetOrDefault(item, new ItemInfo()).Key : "-";
					}
				}
			}
			else if (expected == "hp")
			{
				expected = try DebugText(parts, 4);
				actual = "-";

				foreach (var member in session.Squad.Members)
				{
					if (member.Info.Id == id)
						actual = "" + member.Hp;
				}

				if (expected.StartsWith(">") && TryParseInt(expected.Substring(1)) is int limit && TryParseInt(actual) is int value && value > limit)
					actual = expected;
			}
		}
		else if (what == "time")
		{
			actual = session.Clock.Text();
			expected = try DebugText(parts, 2);
		}
		else if (what == "actor")
		{
			// "expect actor mira 14,19": the tile of an NPC of the current map
			if (session.World().FindActor(try DebugText(parts, 2)) is Actor actor)
				actual = actor.TileX() + "," + actor.TileY();
			else
				actual = "none";

			expected = try DebugText(parts, 3);
		}
		else if (what == "redraws")
		{
			// widget redraws since the last "expect redraws": "reset" only sets the mark, ">n" means more than n
			int delta = WidgetRedraws - _s[0].RedrawMark;

			_s[0].RedrawMark = WidgetRedraws;
			expected = try DebugText(parts, 2);

			if (expected == "reset")
			{
				Console.WriteLine("ok: " + command);

				return;
			}

			actual = "" + delta;

			if (expected.StartsWith(">"))
			{
				if (TryParseInt(expected.Substring(1)) is int count)
				{
					if (delta > count)
						actual = expected;
				}
			}
		}
		else
			return error("Unknown expectation '" + command + "'.", (int)ErrorKind.InvalidOperation);

		if (actual != expected)
			return error("Expectation failed: " + command + " (actual: " + actual + ")", (int)ErrorKind.InvalidOperation);

		Console.WriteLine("ok: " + command);

		return;
	}

	/// One fixed game tick (1/50 s, like the Amiga).
	Error<void> Update(InputState input)
	{
		var session = Session;

		session.TickInterpreter();
		session.TickLook();
		session.UpdateLeaving();

		if (session.MapEnterPending())
		{
			session.SetMapEnterPending(false);
			session.TriggerSimple(TriggerType.MapEnter);
		}

		// during a map change the screen is black for a moment and nothing else happens
		session.Hud.SetSuppressed(session.Fade.Active());

		if (session.Fade.Active())
			session.Fade.Update();
		else if (session.Modals.Any())
			session.Modals.Update(ref session, input);
		else if (session.Leaving())
		{
			// the map_exit scripts of the old map are still running: the world waits
		}
		else
		{
			if (input.Pressed(Key.Escape))
			{
				_s[0].QuitRequested = true;

				return;
			}

			_s[0].HelpTicks = Max(0, _s[0].HelpTicks - 1);
			try HandleWorldInput(input);
			TickWorld();
		}

		session.View.Update();

		foreach (var bubble in session.Bubbles)
			bubble.Update(session.View.CameraX(), session.View.CameraY());

		session.Hud.Update(session.PlaceName(), session.Clock.Text(), session.Party.Gold(), session.Party.Hp(), session.Party.MaxHp, !session.Modals.Any() && _s[0].HelpTicks > 0);

		return;
	}

	string SavePath()
	{
		return Options.SavePath != null ? Options.SavePath : DefaultSavePath();
	}

	Error<void> QuickSave()
	{
		var session = Session;

		if (!CanSaveGame(session))
		{
			session.Hud.ShowNotice("Cannot save now.", 70);

			return;
		}

		string path = SavePath();
		string directory = Path.GetDirectory(path);

		if (directory.Length > 0 && !Directory.Exists(directory))
			Directory.Create(directory);

		try File.WriteAllBytes(path, CaptureGame(session));
		session.Hud.ShowNotice("Game saved.", 70);

		return;
	}

	Error<void> QuickLoad()
	{
		var session = Session;
		string path = SavePath();

		if (!File.Exists(path))
		{
			session.Hud.ShowNotice("No savegame.", 70);

			return;
		}

		if (!CanSaveGame(session))
		{
			session.Hud.ShowNotice("Cannot load now.", 70);

			return;
		}

		var result = RestoreGame(session, try File.ReadAllBytes(path));

		if (result is not error)
			session.Hud.ShowNotice("Game loaded.", 70);
		else if (result.Code == (int)ErrorKind.InvalidSave)
		{
			Console.WriteErrorLine("savegame " + path + ": " + result.Message);
			session.Hud.ShowNotice("Savegame not usable.", 100);
		}
		else
			return error(result.Message, result.Code);

		return;
	}

	Error<void> HandleWorldInput(InputState input)
	{
		var session = Session;
		var world = session.World();
		var player = world.Player;

		if (input.Pressed(Key.F5))
			session.AddMinutes(60);

		if (input.Pressed(Key.F6))
			session.AddMinutes(10);

		// the fight: a click on a monster or T makes it the target
		if (session.Combat.Active())
		{
			if (input.MousePressed(MouseButton.Left))
				session.Combat.TargetAt(input.MouseX() + session.View.CameraX(), input.MouseY() + session.View.CameraY());

			if (input.Pressed(Key.T))
				session.Combat.TargetNearest(player);
		}

		// H heals with an item, in a fight or not
		if (input.Pressed(Key.H))
		{
			if (session.Party.Hp() >= session.Party.MaxHp)
				session.Hud.ShowNotice("You are not hurt.", 70);
			else if (!session.Combat.UseHealingItem(session))
				session.Hud.ShowNotice("Nothing to heal with.", 70);
		}

		if (player.IsMoving())
			return;

		if (input.Pressed(Key.F2))
			return QuickSave();

		if (input.Pressed(Key.F3))
			return QuickLoad();

		if (input.Pressed(Key.I))
		{
			ScreenHost.Of(session).Open("inventory", new int[0], -1, session.MapId());

			return;
		}

		if (input.Pressed(Key.P))
		{
			if (session.Squad.Members.Count() == 0)
				session.Hud.ShowNotice("You have no companions yet.", 70);
			else
				ScreenHost.Of(session).Open("party", new int[0], -1, session.MapId());

			return;
		}

		if (input.Pressed(Key.Space) || input.Pressed(Key.Enter))
		{
			Interact();

			return;
		}

		// With one direction key the character walks that way. With a horizontal and a vertical key it walks diagonally; the
		// key pressed last decides where it looks and, if the corner is blocked, which axis it slides along first.
		var horizontalKey = input.LatestDown(new Key[] { Key.Left, Key.A, Key.Right, Key.D });
		var verticalKey = input.LatestDown(new Key[] { Key.Up, Key.W, Key.Down, Key.S });

		if (horizontalKey == Key.Unknown && verticalKey == Key.Unknown)
			return;

		var latest = MoveDirection(input.LatestDown(new Key[] { Key.Up, Key.W, Key.Down, Key.S, Key.Left, Key.A, Key.Right, Key.D }));

		if (horizontalKey != Key.Unknown && verticalKey != Key.Unknown)
		{
			var h = MoveDirection(horizontalKey);
			var v = MoveDirection(verticalKey);

			if (world.TryDiagonalStep(player, DeltaX(h), DeltaY(v), latest))
				return;

			var other = latest == h ? v : h;

			if (!world.TryStep(player, latest) && !world.TryStep(player, other))
				player.SetFacing(latest);

			return;
		}

		world.TryStep(player, latest);

		return;
	}

	void Interact()
	{
		var session = Session;
		var world = session.World();
		var player = world.Player;
		int x = player.TileX() + DeltaX(player.Facing());
		int y = player.TileY() + DeltaY(player.Facing());
		int started = 0;
		bool found = false;

		foreach (var npc in world.Actors)
		{
			if (found || npc.Same(player) || !npc.Visible() || npc.TileX() != x || npc.TileY() != y)
				continue;

			found = true;

			if (!npc.IsMoving())
				npc.SetFacing(Opposite(player.Facing()));

			started = session.Trigger(TriggerType.Speak, x, y, -1, -1, npc.Id(), -1, 0);
		}

		if (!found)
			started = session.Trigger(TriggerType.Examine, x, y, -1, -1, -1, -1, 0);

		if (started == 0)
			session.Hud.ShowNotice("Nothing special here.", 70);
	}

	void TickWorld()
	{
		var session = Session;
		var world = session.World();
		var player = world.Player;

		session.TickClock();

		foreach (var brain in session.Brains())
			brain.Tick(session.Clock.MinuteOfDay());

		foreach (var actor in world.Actors)
			actor.Tick();

		session.Combat.Tick(session);

		if (!session.Combat.Active())
			session.Squad.Follow(world, player);

		if (player.Arrived())
		{
			// a trigger can teleport the party: the following triggers belong to the old map and must not fire in the new one
			var map = session.Current();

			session.Trigger(TriggerType.EnterTile, player.TileX(), player.TileY(), player.FromX(), player.FromY(), -1, -1, 0);

			if (session.Current().Same(map))
				session.Trigger(TriggerType.LeaveTile, player.FromX(), player.FromY(), player.TileX(), player.TileY(), -1, -1, 0);

			if (session.Current().Same(map))
				session.Trigger(TriggerType.Step, player.TileX(), player.TileY(), -1, -1, -1, -1, 0);
		}
	}

	/// Everything that is visible now.
	void Draw(DrawList list)
	{
		var session = Session;

		session.View.Draw(list);
		session.Squad.Draw(list, session.View.CameraX(), session.View.CameraY());
		session.Combat.Draw(list, session.View.CameraX(), session.View.CameraY());
		list.AddAll(session.Hud.Items());

		foreach (var bubble in session.Bubbles)
			list.AddAll(bubble.Items());

		session.Modals.Draw(list);
		session.Fade.Draw(list);
	}
}

Direction MoveDirection(Key key)
{
	if (key == Key.Up || key == Key.W)
		return Direction.Up;

	if (key == Key.Down || key == Key.S)
		return Direction.Down;

	if (key == Key.Left || key == Key.A)
		return Direction.Left;

	return Direction.Right;
}

Color DummyBody(string name)
{
	if (name == "mira")
		return Color.Of(150, 60, 150);

	if (name == "tobi")
		return Color.Of(80, 170, 90);

	if (name == "bram")
		return Color.Of(110, 90, 60);

	return Color.Of(180, 90, 60);
}

Color DummyHair(string name)
{
	if (name == "mira")
		return Color.Of(200, 200, 205);

	if (name == "tobi")
		return Color.Of(235, 200, 90);

	if (name == "bram")
		return Color.Of(170, 170, 170);

	return Color.Of(60, 40, 30);
}

/// A character of the Mana Seed character base if the content defines a look and the pack is installed, else a dummy.
/// The palette of a map (Ziele Z4): the one of tables.yaml, or one made from the tiles and figures of the map; the
/// night palette of tables.yaml, or one made from the day palette.
Error<MapLook> CreateLook(GameContent content, MapRuntime runtime, TileImages images, Actor player)
{
	var info = content.MapLooks.GetOrDefault(runtime.Name, MapLookInfo { Palette = 0, Night = 0, Daylight = true });
	Palette day;

	if (content.Palettes.TryGet(info.Palette) is Palette given)
		day = given;
	else
	{
		var histogram = ColorHistogram.Create();

		AddTileColors(ref histogram, runtime.World.Map.Tiled, images, false, 8);
		AddFigureColors(ref histogram, player.Art());

		foreach (var actor in runtime.World.Actors)
			AddFigureColors(ref histogram, actor.Art());

		// the companions and the monsters of the fights can appear on every map
		foreach (var companion in content.Companions.Values())
			AddFigureColors(ref histogram, try CreateArt(content, companion.Look, DummyBody(companion.Key), DummyHair(companion.Key)));

		foreach (var group in content.Groups.Values())
		{
			foreach (var monster in group.Monsters)
				AddFigureColors(ref histogram, DummyActorArt(MonsterColor(monster.Key), Color.Of(30, 30, 30)));
		}

		day = (try BuildPalette(histogram, PaletteOptions.Create(256, runtime.Name))).Palette;
	}

	var night = content.Palettes.TryGet(info.Night) is Palette nightGiven ? nightGiven : NightOf(day);

	return MapLook.Create(day, night, info.Daylight);
}

/// The content the game runs from: the pack of --pack, or the content folder cooked into a pack in memory (the game
/// always runs from a pack; the folder is only the source of the cook).
Error<GameContent> LoadContent(LaunchOptions options, string contentDirectory)
{
	if (options.Pack != null)
		return GameContent.Load(options.Pack, RepositoryRoot);

	var source = try ContentSource.Load(contentDirectory, RepositoryRoot);

	return GameContent.FromPack(try PackCook.Cook(source), RepositoryRoot);
}

Error<ActorArt> CreateArt(GameContent content, string name, Color body, Color hair)
{
	string pack = CharacterPackDirectory();

	if (pack != null)
	{
		if (content.Characters.TryGet(name) is string[] layers)
		{
			// a layer the installed pack does not have: the figure is drawn as a placeholder, the game goes on
			var sheet = SheetActorArt(pack, layers);

			if (sheet is ActorArt art)
				return art;

			Console.WriteErrorLine("characters.yaml: '" + name + "' uses a picture that is missing (" + sheet.Message + "); it is drawn as a placeholder.");
		}
	}

	return DummyActorArt(body, hair);
}

Error<int> DebugNumber(string[] parts, int index)
{
	if (index < parts.Length && TryParseInt(parts[index]) is int value)
		return value;

	return error("The debug command '" + JoinList(" ", ListOf(parts)) + "' needs a number as argument " + index + ".", (int)ErrorKind.InvalidData);
}

Error<string> DebugText(string[] parts, int index)
{
	if (index < parts.Length)
		return parts[index];

	return error("The debug command '" + JoinList(" ", ListOf(parts)) + "' needs argument " + index + ".", (int)ErrorKind.InvalidData);
}
