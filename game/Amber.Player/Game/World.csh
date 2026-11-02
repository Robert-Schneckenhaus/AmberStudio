// The world of the game: actors (the player and the NPCs), the maps with their collision and tile changes, the routines
// of the NPCs and path finding. Actors, maps, worlds, brains and map runtimes are handles (C#: classes).

namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Cook;
using Amber.Pack;
using Amber.Runtime;
using Amber.Script.Compilation;
using Amber.Player.Graphics;
using Amber.Player.Tiled;

const int TileSize = 16;

/// Extra sorting offset of the actors in front of the objects of the same row (see WorldView).
const int ActorBaseLine = 8;

/// Game ticks the walk pose is kept between two steps.
const int ActorGraceTicks = 2;

/// Gives every handle a number so that two handles can be compared (C#: reference equality).
int NextHandleKey = 1;

int NewHandleKey()
{
	int key = NextHandleKey;

	NextHandleKey += 1;

	return key;
}

/// The pictures of an actor: a standing image and a walk cycle for each direction (dummy figures or character sheets).
struct ActorArt
{
	int Width;
	int Height;
	/// Distance from the left edge of the tile to the left edge of the image.
	int OffsetX;
	/// Distance from the bottom of the image to the feet.
	int FootMargin;
	int WalkFrameCount;
	/// Game ticks per walk frame at walking speed (1 pixel per tick).
	int TicksPerFrame;
	/// Standing pictures by direction.
	Image[] Stand;
	/// Walk pictures: direction * WalkFrameCount + frame.
	Image[] Walk;
	/// Run pictures, like Walk.
	Image[] Run;
}

struct ActorState
{
	int Id;
	int TileX;
	int TileY;
	Direction Facing;
	bool Blocking;
	bool Visible;
	int Speed;
	int TicksLeft;
	int TicksTotal;
	int StepX;
	int StepY;
	int AnimationTicks;
	int Grace;
	bool Arrived;
	int FromX;
	int FromY;
	ActorArt Art;
}

/// The player or an NPC. Moves from tile to tile with a smooth pixel offset. The tile position changes when a step starts
/// (the target tile is reserved immediately).
struct Actor
{
	ActorState[] _s;
	string Name;
	int Handle;

	static Actor Create(string name, int id, ActorArt art)
	{
		var state = new ActorState[1];

		state[0].Id = id;
		state[0].Facing = Direction.Down;
		state[0].Blocking = true;
		state[0].Visible = true;
		state[0].Speed = 1;
		state[0].Art = art;

		return Actor { _s = state, Name = name, Handle = NewHandleKey() };
	}

	bool Same(Actor other)
	{
		return Handle == other.Handle;
	}

	/// Entity ID of the script pack or -1.
	int Id()
	{
		return _s[0].Id;
	}

	ActorArt Art()
	{
		return _s[0].Art;
	}

	void SetArt(ActorArt art)
	{
		_s[0].Art = art;
	}

	int TileX()
	{
		return _s[0].TileX;
	}

	int TileY()
	{
		return _s[0].TileY;
	}

	Direction Facing()
	{
		return _s[0].Facing;
	}

	void SetFacing(Direction direction)
	{
		_s[0].Facing = direction;
	}

	/// Other actors cannot enter the tile of a blocking actor.
	bool Blocking()
	{
		return _s[0].Blocking;
	}

	void SetBlocking(bool blocking)
	{
		_s[0].Blocking = blocking;
	}

	bool Visible()
	{
		return _s[0].Visible;
	}

	void SetVisible(bool visible)
	{
		_s[0].Visible = visible;
	}

	bool IsMoving()
	{
		return _s[0].TicksLeft > 0;
	}

	bool Running()
	{
		return _s[0].Speed > 1;
	}

	/// True in the tick in which a step ended.
	bool Arrived()
	{
		return _s[0].Arrived;
	}

	/// The tile the last step started from.
	int FromX()
	{
		return _s[0].FromX;
	}

	int FromY()
	{
		return _s[0].FromY;
	}

	/// Pixels still to go in the current step (per axis), 0 when standing.
	int Offset()
	{
		return _s[0].TicksTotal == 0 ? 0 : TileSize * _s[0].TicksLeft / _s[0].TicksTotal;
	}

	int PixelX()
	{
		return _s[0].TileX * TileSize - _s[0].StepX * Offset() + _s[0].Art.OffsetX;
	}

	int PixelY()
	{
		return (_s[0].TileY + 1) * TileSize - _s[0].StepY * Offset() - _s[0].Art.Height + _s[0].Art.FootMargin;
	}

	/// The middle of the actor's tile in pixels, including the current movement.
	int CenterX()
	{
		return _s[0].TileX * TileSize + TileSize / 2 - _s[0].StepX * Offset();
	}

	int CenterY()
	{
		return _s[0].TileY * TileSize + TileSize / 2 - _s[0].StepY * Offset();
	}

	void PlaceAt(int x, int y)
	{
		_s[0].TileX = x;
		_s[0].TileY = y;
		_s[0].TicksLeft = 0;
		_s[0].TicksTotal = 0;
		_s[0].AnimationTicks = 0;
		_s[0].Grace = 0;
	}

	void StartStep(Direction direction)
	{
		StartStepBy(DeltaX(direction), DeltaY(direction), direction);
	}

	/// Starts a step of one tile, diagonal if both deltas are set. A diagonal step takes longer (by the square root of 2) so
	/// that the speed on screen stays the same.
	void StartStepBy(int deltaX, int deltaY, Direction facing)
	{
		double ticks = 16.0 / (double)_s[0].Speed * (deltaX != 0 && deltaY != 0 ? 1.4142135623730951 : 1.0);

		_s[0].Facing = facing;
		_s[0].FromX = _s[0].TileX;
		_s[0].FromY = _s[0].TileY;
		_s[0].TileX += deltaX;
		_s[0].TileY += deltaY;
		_s[0].StepX = deltaX;
		_s[0].StepY = deltaY;
		_s[0].TicksTotal = (int)(ticks + 0.5);
		_s[0].TicksLeft = _s[0].TicksTotal;
	}

	/// Advances the walk animation by one tick.
	void Tick()
	{
		_s[0].Arrived = false;

		if (_s[0].TicksLeft > 0)
		{
			_s[0].TicksLeft -= 1;
			_s[0].AnimationTicks += _s[0].Speed;
			_s[0].Grace = ActorGraceTicks;
			_s[0].Arrived = _s[0].TicksLeft == 0;
		}
		else if (_s[0].Grace > 0)
			_s[0].Grace -= 1;
		else
			_s[0].AnimationTicks = 0;
	}

	/// The pose of CurrentImage as a number: 0..3 standing by direction, 1000 + n the walk picture n, 2000 + n the run
	/// picture n (MapLook caches the palette pictures by it).
	int CurrentFrameKey()
	{
		var art = _s[0].Art;
		int direction = (int)_s[0].Facing;
		int frame = _s[0].AnimationTicks / art.TicksPerFrame % art.WalkFrameCount;

		if (!IsMoving() && _s[0].Grace == 0)
			return direction;

		return (Running() ? 2000 : 1000) + direction * art.WalkFrameCount + frame;
	}

	/// The picture of the current pose: the walk pose is kept for a moment between two steps so that it does not flicker to
	/// standing.
	Image CurrentImage()
	{
		var art = _s[0].Art;
		int direction = (int)_s[0].Facing;
		int frame = _s[0].AnimationTicks / art.TicksPerFrame % art.WalkFrameCount;

		if (!IsMoving() && _s[0].Grace == 0)
			return art.Stand[direction];

		return Running() ? art.Run[direction * art.WalkFrameCount + frame] : art.Walk[direction * art.WalkFrameCount + frame];
	}
}

struct TileEdit
{
	int Layer;
	int X;
	int Y;
	uint32 Old;
	uint32 New;
}

struct BlockEdit
{
	int X;
	int Y;
	bool Old;
	bool New;
}

struct TilePoint
{
	int X;
	int Y;
}

/// A change of a tile or of the collision (layer 255, tile 1 = blocked).
struct NetChange
{
	int Layer;
	int X;
	int Y;
	uint32 Tile;
}

/// A loaded map with its collision data and named waypoints. Scripts change tiles and blocking at runtime; the changes are
/// logged so that they can be saved and undone.
struct WorldMap
{
	TiledMap Tiled;
	bool[] _blocked;
	List<TileEdit> _tileEdits;
	List<BlockEdit> _blockEdits;
	Dictionary<string, TilePoint> Waypoints;

	static WorldMap Create(TiledMap tiled)
	{
		var map = WorldMap
		{
			Tiled = tiled, _blocked = new bool[tiled.Width * tiled.Height], _tileEdits = List<TileEdit>.Create(), _blockEdits = List<BlockEdit>.Create(),
			Waypoints = Dictionary<string, TilePoint>.Create()
		};

		if (tiled.FindLayer("collision") is TiledLayer collision)
		{
			for (var y = 0; y < tiled.Height; y += 1)
			{
				for (var x = 0; x < tiled.Width; x += 1)
					map._blocked[y * tiled.Width + x] = GidOf(collision.Get(x, y)) != 0;
			}
		}

		foreach (var layer in tiled.ObjectLayers)
		{
			foreach (var point in layer.Objects)
				map.Waypoints.Set(point.Name, TilePoint { X = (int)point.X / tiled.TileWidth, Y = (int)point.Y / tiled.TileHeight });
		}

		return map;
	}

	int Width()
	{
		return Tiled.Width;
	}

	int Height()
	{
		return Tiled.Height;
	}

	int TileSize()
	{
		return Tiled.TileWidth;
	}

	bool IsBlocked(int x, int y)
	{
		return x < 0 || y < 0 || x >= Tiled.Width || y >= Tiled.Height || _blocked[y * Tiled.Width + x];
	}

	void SetBlocked(int x, int y, bool value)
	{
		if (x < 0 || y < 0 || x >= Tiled.Width || y >= Tiled.Height || _blocked[y * Tiled.Width + x] == value)
			return;

		_blockEdits.Add(BlockEdit { X = x, Y = y, Old = _blocked[y * Tiled.Width + x], New = value });
		_blocked[y * Tiled.Width + x] = value;
	}

	bool SetTile(string layerName, int x, int y, uint32 raw)
	{
		if (Tiled.FindLayer(layerName) is TiledLayer layer)
		{
			int index = IndexOfText(LayerNames, layerName);

			if (index >= 0)
				_tileEdits.Add(TileEdit { Layer = index, X = x, Y = y, Old = layer.Get(x, y), New = raw });

			layer.Set(x, y, raw);

			return true;
		}

		return false;
	}

	uint32 GetTile(string layerName, int x, int y)
	{
		if (Tiled.FindLayer(layerName) is TiledLayer layer)
			return layer.Get(x, y);

		return 0;
	}

	/// The net changes since the map was loaded: the last value of every changed tile (layer, x, y, raw tile) and of every
	/// changed collision cell (layer 255, tile 1 = blocked, 0 = free). Cells which are back at their original value are left
	/// out. The order is the one of the first change of each cell (C#: GroupBy).
	List<NetChange> NetChanges()
	{
		var result = List<NetChange>.Create();
		var seen = Dictionary<string, bool>.Create();

		for (var i = 0; i < _tileEdits.Count(); i += 1)
		{
			var first = _tileEdits.Get(i);
			string key = first.Layer + ":" + first.X + ":" + first.Y;

			if (seen.ContainsKey(key))
				continue;

			seen.Set(key, true);

			var last = first;

			for (var j = i + 1; j < _tileEdits.Count(); j += 1)
			{
				var edit = _tileEdits.Get(j);

				if (edit.Layer == first.Layer && edit.X == first.X && edit.Y == first.Y)
					last = edit;
			}

			if (first.Old != last.New)
				result.Add(NetChange { Layer = first.Layer, X = first.X, Y = first.Y, Tile = last.New });
		}

		for (var i = 0; i < _blockEdits.Count(); i += 1)
		{
			var first = _blockEdits.Get(i);
			string key = "b:" + first.X + ":" + first.Y;

			if (seen.ContainsKey(key))
				continue;

			seen.Set(key, true);

			var last = first;

			for (var j = i + 1; j < _blockEdits.Count(); j += 1)
			{
				var edit = _blockEdits.Get(j);

				if (edit.X == first.X && edit.Y == first.Y)
					last = edit;
			}

			if (first.Old != last.New)
				result.Add(NetChange { Layer = 255, X = first.X, Y = first.Y, Tile = last.New ? (uint32)1 : (uint32)0 });
		}

		return result;
	}

	/// Puts the map back to the state it was loaded in.
	void ResetChanges()
	{
		for (var i = _tileEdits.Count() - 1; i >= 0; i -= 1)
		{
			var edit = _tileEdits.Get(i);

			if (Tiled.FindLayer(LayerNames[edit.Layer]) is TiledLayer layer)
				layer.Set(edit.X, edit.Y, edit.Old);
		}

		for (var i = _blockEdits.Count() - 1; i >= 0; i -= 1)
		{
			var edit = _blockEdits.Get(i);

			_blocked[edit.Y * Tiled.Width + edit.X] = edit.Old;
		}

		_tileEdits.Clear();
		_blockEdits.Clear();
	}

	/// Applies saved changes (see NetChanges) to a map in its loaded state.
	void Apply(int layer, int x, int y, uint32 tile)
	{
		if (layer == 255)
			SetBlocked(x, y, tile != 0);
		else if (layer < LayerNames.Length)
			SetTile(LayerNames[layer], x, y, tile);
	}
}

/// The tile layers a script can change, in the order of the layer operand of set_tile.
const ReadOnlySlice<string> LayerNames = ["ground", "decor", "objects", "over"];

/// The logical state of a map: collision, actors and who stands where.
struct GameWorld
{
	WorldMap Map;
	Actor Player;
	List<Actor> Actors;

	static GameWorld Create(WorldMap map, Actor player)
	{
		var actors = List<Actor>.Create();

		actors.Add(player);

		return GameWorld { Map = map, Player = player, Actors = actors };
	}

	Optional<Actor> FindActor(string name)
	{
		foreach (var actor in Actors)
		{
			if (actor.Name == name)
				return actor;
		}

		return null;
	}

	/// The NPC with the entity ID (the player is never found).
	Optional<Actor> FindActorById(int id)
	{
		foreach (var actor in Actors)
		{
			if (actor.Id() == id && !actor.Same(Player))
				return actor;
		}

		return null;
	}

	bool Contains(Actor actor)
	{
		foreach (var candidate in Actors)
		{
			if (candidate.Same(actor))
				return true;
		}

		return false;
	}

	void Remove(Actor actor)
	{
		for (var i = 0; i < Actors.Count(); i += 1)
		{
			if (Actors.Get(i).Same(actor))
			{
				Actors.RemoveAt(i);

				return;
			}
		}
	}

	/// A visible blocking actor at the tile (the mover itself is ignored).
	bool ActorAt(int x, int y, Actor ignore)
	{
		foreach (var actor in Actors)
		{
			if (!actor.Same(ignore) && actor.Visible() && actor.Blocking() && actor.TileX() == x && actor.TileY() == y)
				return true;
		}

		return false;
	}

	bool CanEnter(Actor mover, int x, int y)
	{
		return !Map.IsBlocked(x, y) && !ActorAt(x, y, mover);
	}

	/// Tries to start a step. The actor turns even if the step is not possible.
	bool TryStep(Actor actor, Direction direction)
	{
		actor.SetFacing(direction);

		if (actor.IsMoving() || !CanEnter(actor, actor.TileX() + DeltaX(direction), actor.TileY() + DeltaY(direction)))
			return false;

		actor.StartStep(direction);

		return true;
	}

	/// Tries to start a diagonal step. Like in most tile games the corner must not be cut: both tiles next to the diagonal
	/// must be free as well.
	bool TryDiagonalStep(Actor actor, int deltaX, int deltaY, Direction facing)
	{
		int x = actor.TileX();
		int y = actor.TileY();

		if (actor.IsMoving() || !CanEnter(actor, x + deltaX, y + deltaY) || !CanEnter(actor, x + deltaX, y) || !CanEnter(actor, x, y + deltaY))
			return false;

		actor.StartStepBy(deltaX, deltaY, facing);

		return true;
	}
}

/// Breadth first search on the tile grid (static collision only; moving actors are handled while walking). If the goal
/// cannot be entered the path leads to the reachable tile closest to it.
List<Direction> FindPath(WorldMap map, int startX, int startY, int goalX, int goalY)
{
	int width = map.Width();
	var from = new int[width * map.Height()];
	var seen = new bool[from.Length];
	var queue = new int[from.Length + 1];
	int head = 0;
	int tail = 0;
	int start = startY * width + startX;
	int best = start;
	int bestDistance = Abs(startX - goalX) + Abs(startY - goalY);

	seen[start] = true;
	queue[tail] = start;
	tail += 1;

	while (head < tail)
	{
		int current = queue[head];

		head += 1;

		int x = current % width;
		int y = current / width;

		if (x == goalX && y == goalY)
		{
			best = current;

			break;
		}

		int distance = Abs(x - goalX) + Abs(y - goalY);

		if (distance < bestDistance)
		{
			bestDistance = distance;
			best = current;
		}

		for (var d = 0; d < 4; d += 1)
		{
			var direction = (Direction)d;
			int nx = x + DeltaX(direction);
			int ny = y + DeltaY(direction);

			if (map.IsBlocked(nx, ny) || seen[ny * width + nx])
				continue;

			seen[ny * width + nx] = true;
			from[ny * width + nx] = current;
			queue[tail] = ny * width + nx;
			tail += 1;
		}
	}

	var path = List<Direction>.Create();

	for (var cell = best; cell != start; cell = from[cell])
	{
		int previous = from[cell];
		int dx = cell % width - previous % width;
		int dy = cell / width - previous / width;

		path.Add(dx > 0 ? Direction.Right : dx < 0 ? Direction.Left : dy > 0 ? Direction.Down : Direction.Up);
	}

	path.Reverse();

	return path;
}

const int BrainStuckTicks = 150;

struct BrainState
{
	PackedRoutineEntry[] Entries;
	int EntryIndex;
	int StepIndex;
	List<Direction> Path;
	int PathPosition;
	int WaitTicks;
	int BlockedTicks;
	bool HasGoal;
	int GoalX;
	int GoalY;
	string RoutineName;
	int RoutineId;
}

/// Runs the routine of an NPC: at the time of each entry the NPC walks to the waypoints and waits there.
struct NpcBrain
{
	BrainState[] _s;
	Actor Actor;
	GameWorld World;

	static NpcBrain Create(Actor actor, GameWorld world)
	{
		var state = new BrainState[1];

		state[0].Entries = new PackedRoutineEntry[0];
		state[0].EntryIndex = -1;
		state[0].Path = List<Direction>.Create();
		state[0].RoutineId = -1;

		return NpcBrain { _s = state, Actor = actor, World = world };
	}

	string RoutineName()
	{
		return _s[0].RoutineName;
	}

	/// ID of the routine (set_routine) or -1 if the NPC has none.
	int RoutineId()
	{
		return _s[0].RoutineId;
	}

	void SetRoutine(Optional<PackedRoutine> routine)
	{
		if (routine is PackedRoutine value)
		{
			_s[0].RoutineName = value.Name;
			_s[0].RoutineId = value.Id;
			_s[0].Entries = SortArray(value.Entries, CompareEntryMinute);
		}
		else
		{
			_s[0].RoutineName = null;
			_s[0].RoutineId = -1;
			_s[0].Entries = new PackedRoutineEntry[0];
		}

		_s[0].EntryIndex = -1;
		_s[0].Path = List<Direction>.Create();
		_s[0].WaitTicks = 0;
	}

	/// One tick of the NPC (only called while the world is running).
	void Tick(int minuteOfDay)
	{
		if (_s[0].Entries.Length == 0)
			return;

		int current = CurrentEntry(minuteOfDay);

		if (current != _s[0].EntryIndex)
		{
			_s[0].EntryIndex = current;
			_s[0].StepIndex = 0;
			_s[0].Path = List<Direction>.Create();
			_s[0].HasGoal = false;
			_s[0].WaitTicks = 0;
			BeginStep();
		}

		if (_s[0].WaitTicks > 0)
		{
			_s[0].WaitTicks -= 1;

			if (_s[0].WaitTicks == 0)
			{
				_s[0].StepIndex += 1;
				BeginStep();
			}

			return;
		}

		if (!_s[0].HasGoal || Actor.IsMoving())
			return;

		if (_s[0].PathPosition >= _s[0].Path.Count())
		{
			_s[0].HasGoal = false;
			_s[0].StepIndex += 1;
			BeginStep();

			return;
		}

		if (World.TryStep(Actor, _s[0].Path.Get(_s[0].PathPosition)))
		{
			_s[0].PathPosition += 1;
			_s[0].BlockedTicks = 0;
		}
		else
		{
			_s[0].BlockedTicks += 1;

			if (_s[0].BlockedTicks > BrainStuckTicks)
			{
				// something is in the way: plan again
				_s[0].BlockedTicks = 0;
				Plan(_s[0].GoalX, _s[0].GoalY);
			}
		}
	}

	int CurrentEntry(int minuteOfDay)
	{
		var entries = _s[0].Entries;
		int found = entries.Length - 1;

		for (var i = 0; i < entries.Length; i += 1)
		{
			if (entries[i].Minute <= minuteOfDay)
				found = i;
		}

		return found;
	}

	void BeginStep()
	{
		var steps = _s[0].Entries[_s[0].EntryIndex].Steps;

		while (_s[0].StepIndex < steps.Length)
		{
			var step = steps[_s[0].StepIndex];

			if (step.Kind == PackedRoutineStepKind.WalkTo && step.Target != null && World.Map.Waypoints.TryGet(step.Target) is TilePoint point)
			{
				_s[0].HasGoal = true;
				_s[0].GoalX = point.X;
				_s[0].GoalY = point.Y;
				Plan(point.X, point.Y);

				return;
			}

			if (step.Kind == PackedRoutineStepKind.Stay)
			{
				_s[0].WaitTicks = step.Ticks < 1 ? 1 : step.Ticks > 0x7FFFFFFF ? 0x7FFFFFFF : (int)step.Ticks;

				return;
			}

			if (step.Kind == PackedRoutineStepKind.Sleep)
			{
				_s[0].WaitTicks = 0x7FFFFFFF;

				return;
			}

			_s[0].StepIndex += 1;
		}
	}

	void Plan(int x, int y)
	{
		_s[0].Path = FindPath(World.Map, Actor.TileX(), Actor.TileY(), x, y);
		_s[0].PathPosition = 0;
	}
}

int CompareEntryMinute(PackedRoutineEntry a, PackedRoutineEntry b)
{
	return CompareInt(a.Minute, b.Minute);
}

struct MapRuntimeState
{
	bool HasSavedState;
	StateStore SavedState;
}

/// One map of the game: its world with the actors, the NPC brains and the script state while the map is not loaded.
struct MapRuntime
{
	MapRuntimeState[] _s;
	string Name;
	/// ID of the map in the script pack (symbol M.name).
	int MapId;
	string PlaceName;
	GameWorld World;
	/// The MAP chunk of the pack: entities, scripts and the baked routines of the NPCs.
	PackedMap Script;
	List<NpcBrain> Brains;
	PackedRoutine[] Routines;
	/// The palette of the map and its palette pictures (set when the game is loaded).
	MapLook Look;
	int Handle;

	static MapRuntime Create(string name, int mapId, string placeName, GameWorld world, PackedMap script)
	{
		var state = new MapRuntimeState[1];

		return MapRuntime
		{
			_s = state, Name = name, MapId = mapId, PlaceName = placeName, World = world, Script = script, Brains = List<NpcBrain>.Create(),
			Routines = script.Routines, Handle = NewHandleKey()
		};
	}

	bool Same(MapRuntime other)
	{
		return Handle == other.Handle;
	}

	/// The flags and variables of the map while it is unloaded (map-bound scripts only run while the map is loaded).
	Optional<StateStore> SavedState()
	{
		if (_s[0].HasSavedState)
			return _s[0].SavedState;

		return null;
	}

	void SetSavedState(Optional<StateStore> state)
	{
		if (state is StateStore value)
		{
			_s[0].HasSavedState = true;
			_s[0].SavedState = value;
		}
		else
			_s[0].HasSavedState = false;
	}

	StateSizes Sizes()
	{
		return Script.Sizes;
	}

	Optional<NpcBrain> BrainOf(Actor actor)
	{
		foreach (var brain in Brains)
		{
			if (brain.Actor.Same(actor))
				return brain;
		}

		return null;
	}

	Optional<PackedRoutine> RoutineById(int id)
	{
		foreach (var routine in Routines)
		{
			if (routine.Id == id)
				return routine;
		}

		return null;
	}

	Optional<PackedRoutine> RoutineOfEntity(int entityId)
	{
		foreach (var routine in Routines)
		{
			if (routine.EntityId == entityId)
				return routine;
		}

		return null;
	}
}
