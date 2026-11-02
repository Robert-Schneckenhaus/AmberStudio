namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Runtime;
using Amber.Script.Common;
using Amber.Player.Content;
using Amber.Player.Game.Ui;
using Amber.Player.Screens;

/// A map change which waits for the map_exit scripts of the old map.
struct PendingSwitch
{
	int MapId;
	int X;
	int Y;
	bool HasFacing;
	Direction Facing;
	int Thread;
	List<int> ExitThreads;
}

struct SessionValues
{
	MapRuntime Current;
	Interpreter Interpreter;
	/// True after a map change until the map_enter trigger of the new map has been fired.
	bool MapEnterPending;
	bool HasPending;
	PendingSwitch Pending;
}

/// All state of a running game: content, party, clock, the maps with their actors and the user interface. The script host
/// and the game loop both work on it. A handle: the host, the screen host and the screens keep copies of it.
struct GameSession
{
	SessionValues[] _s;
	GameContent Content;
	Party Party;
	GameClock Clock;
	Actor Player;
	WorldView View;
	UiKit Ui;
	Hud Hud;
	ModalStack Modals;
	ScreenFade Fade;
	/// All maps (the IDs are the ones of the script pack).
	List<MapRuntime> Maps;
	List<Bubble> Bubbles;
	/// The chests which were opened, in the order they were first used (the others still have their initial content).
	Dictionary<int, Chest> Chests;
	/// The script side of the open screens by modal key.
	Dictionary<int, ScreenInstance> ScreenInstances;
	/// The open screens by the key of their loaded chunk (ThreadContext.ScreenKey).
	Dictionary<int, ScreenModal> ScreensByChunk;
	/// The fight on the map (real time, see Combat).
	Combat Combat;
	/// The companions of the hero.
	Squad Squad;

	static GameSession Create(GameContent content, Party party, GameClock clock, Actor player, WorldView view, UiKit ui)
	{
		return GameSession
		{
			_s = new SessionValues[1], Content = content, Party = party, Clock = clock, Player = player, View = view, Ui = ui, Hud = Amber.Player.Game.Ui.Hud.Create(),
			Modals = ModalStack.Create(), Fade = ScreenFade.Create(), Maps = List<MapRuntime>.Create(), Bubbles = List<Bubble>.Create(),
			Chests = Dictionary<int, Chest>.Create(), ScreenInstances = Dictionary<int, ScreenInstance>.Create(), ScreensByChunk = Dictionary<int, ScreenModal>.Create(),
			Combat = Combat.Create(), Squad = Squad.Create()
		};
	}

	Interpreter Interpreter()
	{
		return _s[0].Interpreter;
	}

	void SetInterpreter(Interpreter interpreter)
	{
		_s[0].Interpreter = interpreter;
	}

	/// The map the party is on. Only its script chunk is loaded in the interpreter.
	MapRuntime Current()
	{
		return _s[0].Current;
	}

	void SetCurrent(MapRuntime map)
	{
		_s[0].Current = map;
	}

	bool MapEnterPending()
	{
		return _s[0].MapEnterPending;
	}

	void SetMapEnterPending(bool value)
	{
		_s[0].MapEnterPending = value;
	}

	GameWorld World()
	{
		return _s[0].Current.World;
	}

	int MapId()
	{
		return _s[0].Current.MapId;
	}

	string PlaceName()
	{
		return _s[0].Current.PlaceName;
	}

	List<NpcBrain> Brains()
	{
		return _s[0].Current.Brains;
	}

	Optional<MapRuntime> MapById(int mapId)
	{
		foreach (var map in Maps)
		{
			if (map.MapId == mapId)
				return map;
		}

		return null;
	}

	Optional<MapRuntime> MapByName(string name)
	{
		foreach (var map in Maps)
		{
			if (map.Name == name)
				return map;
		}

		return null;
	}

	/// The map a script thread belongs to (the thread's owner map), or the current one.
	MapRuntime RuntimeFor(int ownerMap)
	{
		if (MapById(ownerMap) is MapRuntime map)
			return map;

		return _s[0].Current;
	}

	/// The actor for an entity operand of a script running on the given map; "party" is the player.
	Optional<Actor> ActorFor(uint16 entity, int ownerMap)
	{
		if (entity == Wire.None)
			return Player;

		return RuntimeFor(ownerMap).World.FindActorById((int)entity);
	}

	/// The chest with the ID (symbol CH.name); it is created with its initial content when it is used for the first time.
	Optional<Chest> ChestOf(int id)
	{
		if (Chests.TryGet(id) is Chest chest)
			return chest;

		if (Content.Chests.TryGet(id) is ChestInfo info)
		{
			var content = List<IntPair2>.Create();

			foreach (var pair in info.Items.Entries())
				content.Add(IntPair2 { Key = pair.Key, Value = pair.Value });

			var created = Chest.Create(info.Gold, content);

			Chests.Set(id, created);

			return created;
		}

		return null;
	}

	/// Replaces the chests with the saved ones (loading a savegame); all others are initial again.
	void RestoreChests(Dictionary<int, Chest> saved)
	{
		Chests.Clear();

		foreach (var pair in saved.Entries())
			Chests.Set(pair.Key, pair.Value);
	}

	int TriggerWith(TriggerContext context)
	{
		var host = PrototypeHost.Of(this);

		return Interpreter().Trigger(ref host, context);
	}

	/// A trigger on the current map; -1 leaves a value out.
	int Trigger(TriggerType type, int x, int y, int otherX, int otherY, int entity, int param, int arg)
	{
		var context = TriggerContext.Of(type);

		context.MapId = MapId();
		context.X = x < 0 ? Wire.None : (uint16)x;
		context.Y = y < 0 ? Wire.None : (uint16)y;
		context.OtherX = otherX < 0 ? Wire.None : (uint16)otherX;
		context.OtherY = otherY < 0 ? Wire.None : (uint16)otherY;
		context.EntityId = entity;
		context.Param = param < 0 ? Wire.None : (uint16)param;
		context.Arg = (uint32)arg;

		return TriggerWith(context);
	}

	int TriggerSimple(TriggerType type)
	{
		return Trigger(type, -1, -1, -1, -1, -1, -1, 0);
	}

	void Resume(int threadId, int result)
	{
		var host = PrototypeHost.Of(this);

		Interpreter().Resume(ref host, threadId, (int16)result);
	}

	/// The palette of the current map for this tick (clock, fades, flashes); a thread that waited for a fade goes on.
	void TickLook()
	{
		var look = Current().Look;
		int thread = look.Tick();

		look.Update(Clock.MinuteOfDay());

		if (thread >= 0)
			Resume(thread, 0);
	}

	void TickInterpreter()
	{
		var host = PrototypeHost.Of(this);

		Interpreter().Tick(ref host);
	}

	/// One tick of the clock; a new hour fires hour(h).
	void TickClock()
	{
		if (Clock.Tick())
			AddMinutes(1);
	}

	/// Advances the clock; every hour that starts fires hour(h) (C#: GameClock.HourStarted).
	void AddMinutes(int minutes)
	{
		for (var i = 0; i < minutes; i += 1)
		{
			int hour = Clock.AddMinute();

			if (hour >= 0)
				Trigger(TriggerType.Hour, -1, -1, -1, -1, -1, hour, hour);
		}
	}

	/// True while the party is leaving a map and the map_exit scripts are still running (the world waits).
	bool Leaving()
	{
		return _s[0].HasPending;
	}

	/// Moves the party to another map. First map_exit is fired on the old map; if its scripts wait (say, wait), the change
	/// happens when they are done (UpdateLeaving), else at once. Then the old map is unloaded from the interpreter (its state
	/// is kept), the new one loaded and shown; map_enter is fired at the beginning of the next tick. The thread which
	/// teleported keeps running. With announce false (loading a savegame) map_exit is not fired.
	Error<void> SwitchMap(int mapId, int x, int y, bool hasFacing, Direction facing, int threadId, bool announce)
	{
		if (!(MapById(mapId) is MapRuntime))
			return error("Map " + mapId + " does not exist.", (int)ErrorKind.InvalidOperation);

		if (_s[0].HasPending)
			return;

		var target = MapOrCurrent(mapId);

		if (announce && !target.Same(Current()))
		{
			var before = Interpreter().ActiveThreadsOf(Current().MapId);

			TriggerSimple(TriggerType.MapExit);

			// the threads the trigger started (not the teleporting one, not what ran before)
			var exitThreads = List<int>.Create();

			foreach (var id in Interpreter().ActiveThreadsOf(Current().MapId))
			{
				if (!before.Contains(id) && id != threadId)
					exitThreads.Add(id);
			}

			if (exitThreads.Count() > 0)
			{
				_s[0].HasPending = true;
				_s[0].Pending = PendingSwitch { MapId = mapId, X = x, Y = y, HasFacing = hasFacing, Facing = facing, Thread = threadId, ExitThreads = exitThreads };

				return;
			}
		}

		Complete(target, x, y, hasFacing, facing, threadId);

		return;
	}

	MapRuntime MapOrCurrent(int mapId)
	{
		if (MapById(mapId) is MapRuntime map)
			return map;

		return Current();
	}

	/// Finishes a map change which waited for the map_exit scripts. Called every tick.
	void UpdateLeaving()
	{
		if (!_s[0].HasPending)
			return;

		var waiting = _s[0].Pending;

		foreach (var id in waiting.ExitThreads)
		{
			if (Interpreter().IsThreadActive(id))
				return;
		}

		_s[0].HasPending = false;
		Complete(MapOrCurrent(waiting.MapId), waiting.X, waiting.Y, waiting.HasFacing, waiting.Facing, waiting.Thread);
	}

	void Complete(MapRuntime target, int x, int y, bool hasFacing, Direction facing, int threadId)
	{
		bool changed = !target.Same(Current());
		var from = Current();

		if (changed)
		{
			var old = Current();

			old.SetSavedState(StateOfMap(old.MapId));

			// leaving the map ends a fight on it (fled)
			Combat.Abort(this);

			// a palette of a script belongs to the map: leaving releases it, a thread that waited for its fade goes on
			int fadeThread = old.Look.Release();

			Interpreter().UnloadMap(old.MapId, threadId);

			if (fadeThread >= 0)
				Resume(fadeThread, 0);

			old.World.Remove(Player);

			SetCurrent(target);

			if (!target.World.Contains(Player))
				target.World.Actors.Add(Player);

			if (target.SavedState() is StateStore saved)
				Interpreter().LoadMap(target.MapId, target.Script.Script, saved);
			else
				Interpreter().LoadMap(target.MapId, target.Script.Script, StateStore.Create(target.Sizes()));

			View.SetWorld(target);

			foreach (var bubble in Bubbles)
				bubble.Stop();

			Fade.Start(12);
			SetMapEnterPending(true);
		}

		Player.PlaceAt(x, y);

		if (hasFacing)
			Player.SetFacing(facing);

		// the companions come along (or join the hero where he was put)
		Squad.MoveTo(from.World, target.World, Player);
	}

	/// The state of a loaded map, or no value.
	Optional<StateStore> StateOfMap(int mapId)
	{
		if (Interpreter().GetMap(mapId) is LoadedChunk map)
			return map.State;

		return null;
	}

	void ShowBark(Actor actor, string text)
	{
		int found = -1;

		for (var i = 0; i < Bubbles.Count() && found < 0; i += 1)
		{
			if (Bubbles.Get(i).OwnedBy(actor))
				found = i;
		}

		for (var i = 0; i < Bubbles.Count() && found < 0; i += 1)
		{
			if (!Bubbles.Get(i).Active())
				found = i;
		}

		if (found < 0)
		{
			Bubbles.Add(Bubble.Create());
			found = Bubbles.Count() - 1;
		}

		Bubbles.Get(found).Start(actor, text, 180);
	}
}
