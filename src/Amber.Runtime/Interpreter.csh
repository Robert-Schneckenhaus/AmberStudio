namespace Amber.Runtime;

using System;
using Amber.Base;
using Amber.Script.Common;

/// A loaded chunk (global scripts, one map or one screen instance) together with its state. Key identifies the loaded
/// instance (a screen can be open twice, its ID alone does not tell them apart); Id is the map ID, the screen ID or 0 for
/// the global chunk. A handle: copies share the state and the tick counters.
struct LoadedChunk
{
	int Key;
	ScriptChunk Chunk;
	ScopeKind Kind;
	int Id;
	StateStore State;
	int[] TickCounters;

	static LoadedChunk Create(int key, ScriptChunk chunk, ScopeKind kind, int id, StateStore state)
	{
		return LoadedChunk { Key = key, Chunk = chunk, Kind = kind, Id = id, State = state, TickCounters = new int[chunk.BindingCount] };
	}

	bool Same(LoadedChunk other)
	{
		return Key == other.Key;
	}
}

enum ThreadPhase : int32
{
	Enter,
	NextRule,
	RunActions
}

enum FlagChange : int32
{
	Set,
	Clear,
	Toggle
}

/// One slot of the fixed thread pool (C#: the class ThreadState). The pool is an array of these; the interpreter changes the
/// elements in place.
struct ThreadState
{
	bool Active;
	bool Waiting;
	int WaitTicks;
	ThreadPhase Phase;
	LoadedChunk Home;
	LoadedChunk Current;
	int OwnerMap;
	bool HasScreen;
	LoadedChunk Screen;
	uint16 Group;
	GroupMode Mode;
	int RuleIndex;
	int RuleCount;
	int RuleOffset;
	int ActionOffset;
	int ActionEnd;
	uint16 Next;
	int16 Result;
	uint32 Arg;
	uint16 X;
	uint16 Y;
	int Steps;
	int BindingKey;
	bool AutosaveRequested;
	int16[] Locals;
}

struct ReactiveEvent
{
	TriggerType Type;
	uint16 Slot;
	int Value;
	int MapId;
	int ScreenKey;
}

/// The mutable numbers of the interpreter (in an array, so that copies of the handle share them).
struct InterpreterCounters
{
	int NextChunkKey;
	int64 Ticks;
	uint32 Random;
}

/// Executes rules (spec section 2). The interpreter is written in a C-friendly way: fixed thread pool, word-wise access to
/// the chunks, no errors for control flow. It is a handle: copies share the state (the host may keep one).
///
/// The functions that run scripts (Trigger, Resume, Tick, RunGroup) take the host: interpreter.Tick(ref host). A chunk that
/// cannot be read ends the program (C#: an exception nobody catches); packs are checked when they are loaded.
struct Interpreter
{
	RuntimeLimits _limits;
	bool _tracing;
	List<string> _trace;
	ThreadState[] _threads;
	List<ReactiveEvent> _reactive;
	Dictionary<int, LoadedChunk> _maps;
	List<LoadedChunk> _screens;
	LoadedChunk _global;
	InterpreterCounters[] _counters;

	static Interpreter Create(ScriptChunk globalScripts, StateSizes globalSizes, RuntimeLimits limits)
	{
		var interpreter = Interpreter
		{
			_limits = limits,
			_tracing = false,
			_trace = List<string>.Create(),
			_threads = new ThreadState[limits.MaxThreads],
			_reactive = List<ReactiveEvent>.Create(),
			_maps = Dictionary<int, LoadedChunk>.Create(),
			_screens = List<LoadedChunk>.Create(),
			_counters = new InterpreterCounters[1]
		};

		for (var i = 0; i < interpreter._threads.Length; i += 1)
		{
			interpreter._threads[i].OwnerMap = -1;
			interpreter._threads[i].Locals = new int16[8];
		}

		interpreter._counters[0].NextChunkKey = 1;
		interpreter._counters[0].Ticks = 0;
		interpreter._counters[0].Random = 0x2545F491;
		interpreter._global = LoadedChunk.Create(interpreter.NextKey(), globalScripts, ScopeKind.Global, 0, StateStore.Create(globalSizes));

		return interpreter;
	}

	/// The same interpreter with a trace (spec section 12.3): every step is added to the list.
	static Interpreter CreateTraced(ScriptChunk globalScripts, StateSizes globalSizes, RuntimeLimits limits, List<string> trace)
	{
		var interpreter = Create(globalScripts, globalSizes, limits);

		interpreter._tracing = true;
		interpreter._trace = trace;

		return interpreter;
	}

	int NextKey()
	{
		int key = _counters[0].NextChunkKey;

		_counters[0].NextChunkKey = key + 1;

		return key;
	}

	StateStore Global()
	{
		return _global.State;
	}

	/// The loaded global chunk (for RunGroup of global groups).
	LoadedChunk GlobalChunk()
	{
		return _global;
	}

	int64 Ticks()
	{
		return _counters[0].Ticks;
	}

	int ActiveThreadCount()
	{
		int count = 0;

		for (var i = 0; i < _threads.Length; i += 1)
		{
			if (_threads[i].Active)
				count += 1;
		}

		return count;
	}

	/// The IDs of the running threads which belong to a map (the owner map of their rule).
	List<int> ActiveThreadsOf(int ownerMap)
	{
		var result = List<int>.Create();

		for (var i = 0; i < _threads.Length; i += 1)
		{
			if (_threads[i].Active && _threads[i].OwnerMap == ownerMap)
				result.Add(i);
		}

		return result;
	}

	bool IsThreadActive(int threadId)
	{
		return threadId >= 0 && threadId < _threads.Length && _threads[threadId].Active;
	}

	/// State of the random number generator (part of the savegame).
	uint32 RandomState()
	{
		return _counters[0].Random;
	}

	void SetRandomState(uint32 value)
	{
		_counters[0].Random = value == 0 ? 1 : value;
	}

	LoadedChunk LoadMap(int mapId, ScriptChunk chunk, StateSizes sizes)
	{
		return LoadMap(mapId, chunk, StateStore.Create(sizes));
	}

	/// Loads a map with existing state (a map the party comes back to). The host keeps the StateStore of LoadedChunk.State
	/// while the map is unloaded; map-bound bindings only run while the map is loaded.
	LoadedChunk LoadMap(int mapId, ScriptChunk chunk, StateStore state)
	{
		var loaded = LoadedChunk.Create(NextKey(), chunk, ScopeKind.Map, mapId, state);

		_maps.Set(mapId, loaded);

		return loaded;
	}

	/// Unloads a map. Threads owned by the map end, except the given thread (the one which teleported; -1 for none).
	void UnloadMap(int mapId, int exceptThread)
	{
		for (var i = 0; i < _threads.Length; i += 1)
		{
			if (i != exceptThread && _threads[i].Active && _threads[i].OwnerMap == mapId)
				_threads[i].Active = false;
		}

		_maps.Remove(mapId);
	}

	LoadedChunk LoadScreen(int screenId, ScriptChunk chunk, StateSizes sizes)
	{
		var loaded = LoadedChunk.Create(NextKey(), chunk, ScopeKind.Screen, screenId, StateStore.Create(sizes));

		_screens.Add(loaded);

		return loaded;
	}

	void UnloadScreen(LoadedChunk screen)
	{
		for (var i = 0; i < _threads.Length; i += 1)
		{
			if (_threads[i].Active && _threads[i].HasScreen && _threads[i].Screen.Same(screen))
				_threads[i].Active = false;
		}

		for (var i = 0; i < _screens.Count(); i += 1)
		{
			if (_screens.Get(i).Same(screen))
			{
				_screens.RemoveAt(i);
				break;
			}
		}
	}

	Optional<LoadedChunk> GetMap(int mapId)
	{
		return _maps.TryGet(mapId);
	}

	/// Computes the state hash of golden traces (spec section 12.3); mapId -1 for the global state only.
	uint32 StateHash(int mapId)
	{
		var crc = Crc32.Create();

		_global.State.AddToHash(ref crc);

		if (mapId >= 0)
		{
			if (_maps.TryGet(mapId) is LoadedChunk map)
				map.State.AddToHash(ref crc);
		}

		crc.AddDword(_counters[0].Random);

		return crc.Value();
	}

	void TraceHash(int mapId)
	{
		Trace("hash crc32=0x" + Hex(StateHash(mapId), 8));
	}

	/// Reports an event of the host and starts the threads of all matching bindings. Returns the number of started threads.
	int Trigger<THost>(ref THost host, const ref TriggerContext context)
		where THost : IGameHost
	{
		int started = Dispatch(ref host, _global, context, context.MapId);

		if (context.MapId >= 0)
		{
			if (_maps.TryGet(context.MapId) is LoadedChunk map)
				started += Dispatch(ref host, map, context, context.MapId);
		}

		if (context.ScreenId >= 0)
		{
			foreach (var screen in ArrayOf(_screens))
			{
				if (screen.Id == context.ScreenId)
					started += Dispatch(ref host, screen, context, context.MapId);
			}
		}

		return started;
	}

	/// Continues a blocked thread with the result of the awaited action.
	void Resume<THost>(ref THost host, int threadId, int16 result)
		where THost : IGameHost
	{
		if (threadId < 0 || threadId >= _threads.Length)
			return;

		if (!_threads[threadId].Active || !_threads[threadId].Waiting)
			return;

		_threads[threadId].Result = result;
		_threads[threadId].Waiting = false;
		_threads[threadId].WaitTicks = 0;

		Trace("resume thread=" + threadId + " result=" + result);
		Advance(ref host, threadId);
	}

	/// Advances the clock by one tick: reactive events, map ticks and wait timers.
	void Tick<THost>(ref THost host)
		where THost : IGameHost
	{
		_counters[0].Ticks = _counters[0].Ticks + 1;

		int pending = _reactive.Count();

		for (var i = 0; i < pending; i += 1)
		{
			var reactiveEvent = _reactive.Get(0);

			_reactive.RemoveAt(0);
			DispatchReactive(ref host, reactiveEvent);
		}

		foreach (var map in _maps.Values())
			RunMapTicks(ref host, map);

		for (var i = 0; i < _threads.Length; i += 1)
		{
			if (_threads[i].Active && _threads[i].Waiting && _threads[i].WaitTicks > 0)
			{
				_threads[i].WaitTicks -= 1;

				if (_threads[i].WaitTicks == 0)
					Resume(ref host, i, 0);
			}
		}
	}

	int Dispatch<THost>(ref THost host, LoadedChunk chunk, const ref TriggerContext context, int ownerMap)
		where THost : IGameHost
	{
		int started = 0;

		for (var i = 0; i < chunk.Chunk.BindingCount; i += 1)
		{
			var binding = BindingAt(chunk.Chunk, i);

			if (binding.Trigger == context.Type && Matches(binding, context) && StartThread(ref host, chunk, i, binding, context.X, context.Y, context.Arg, ownerMap))
				started += 1;
		}

		return started;
	}

	void DispatchReactive<THost>(ref THost host, ReactiveEvent reactiveEvent)
		where THost : IGameHost
	{
		var context = TriggerContext.Of(reactiveEvent.Type);

		context.MapId = reactiveEvent.MapId;
		context.Arg = (uint32)reactiveEvent.Value;

		DispatchReactiveIn(ref host, _global, reactiveEvent, context);

		if (reactiveEvent.MapId >= 0)
		{
			if (_maps.TryGet(reactiveEvent.MapId) is LoadedChunk map)
				DispatchReactiveIn(ref host, map, reactiveEvent, context);
		}

		foreach (var screen in ArrayOf(_screens))
		{
			if (screen.Key == reactiveEvent.ScreenKey)
				DispatchReactiveIn(ref host, screen, reactiveEvent, context);
		}
	}

	void DispatchReactiveIn<THost>(ref THost host, LoadedChunk chunk, ReactiveEvent reactiveEvent, const ref TriggerContext context)
		where THost : IGameHost
	{
		for (var i = 0; i < chunk.Chunk.BindingCount; i += 1)
		{
			var binding = BindingAt(chunk.Chunk, i);

			if (binding.Trigger != reactiveEvent.Type || binding.P1 != reactiveEvent.Slot)
				continue;

			if (binding.Trigger == TriggerType.FlagChanged)
			{
				bool matchesMode = binding.P2 == 0 || (binding.P2 == 1 && reactiveEvent.Value != 0) || (binding.P2 == 2 && reactiveEvent.Value == 0);

				if (!matchesMode)
					continue;
			}

			StartThread(ref host, chunk, i, binding, Wire.None, Wire.None, context.Arg, reactiveEvent.MapId);
		}
	}

	void RunMapTicks<THost>(ref THost host, LoadedChunk map)
		where THost : IGameHost
	{
		for (var i = 0; i < map.Chunk.BindingCount; i += 1)
		{
			var binding = BindingAt(map.Chunk, i);

			if (binding.Trigger != TriggerType.MapTick || binding.P1 == 0)
				continue;

			map.TickCounters[i] += 1;

			if (map.TickCounters[i] >= (int)binding.P1)
			{
				map.TickCounters[i] = 0;
				StartThread(ref host, map, i, binding, Wire.None, Wire.None, 0, map.Id);
			}
		}
	}

	bool StartThread<THost>(ref THost host, LoadedChunk chunk, int bindingIndex, BindingRecord binding, uint16 x, uint16 y, uint32 arg, int ownerMap)
		where THost : IGameHost
	{
		string description = "start " + TriggerName(binding.Trigger) + " chunk=" + ScopeKindName(chunk.Kind) + ":" + chunk.Id + " binding=" + bindingIndex;

		return StartThreadWithKey(ref host, chunk, chunk.Key * 4096 + bindingIndex, binding.Group, description, x, y, arg, ownerMap);
	}

	/// Runs a group of a loaded chunk directly, for handlers which are not bindings (the on_click, on_open ... groups of a
	/// screen definition). The value becomes the trigger argument; ownerMap is -1 if none. Returns false if the group is
	/// already running or no thread is free.
	bool RunGroup<THost>(ref THost host, LoadedChunk chunk, uint16 group, uint32 arg, int ownerMap)
		where THost : IGameHost
	{
		string description = "run group " + Hex((int)group, 4) + " chunk=" + ScopeKindName(chunk.Kind) + ":" + chunk.Id;

		return StartThreadWithKey(ref host, chunk, chunk.Key * 4096 + 2048 + Wire.GroupIndex(group), group, description, Wire.None, Wire.None, arg, ownerMap);
	}

	bool StartThreadWithKey<THost>(ref THost host, LoadedChunk chunk, int key, uint16 group, string description, uint16 x, uint16 y, uint32 arg, int ownerMap)
		where THost : IGameHost
	{
		int free = -1;

		for (var i = 0; i < _threads.Length; i += 1)
		{
			if (_threads[i].Active && _threads[i].BindingKey == key)
			{
				Trace("skip " + description + " (already running)");

				return false;
			}

			if (free < 0 && !_threads[i].Active)
				free = i;
		}

		if (free < 0)
		{
			Trace("drop " + description + " (no free thread)");

			return false;
		}

		_threads[free].Active = true;
		_threads[free].Waiting = false;
		_threads[free].WaitTicks = 0;
		_threads[free].Phase = ThreadPhase.Enter;
		_threads[free].Home = chunk;
		_threads[free].Current = chunk;
		_threads[free].OwnerMap = chunk.Kind == ScopeKind.Map ? chunk.Id : ownerMap;
		_threads[free].HasScreen = chunk.Kind == ScopeKind.Screen;
		_threads[free].Screen = chunk;
		_threads[free].Group = group;
		_threads[free].Result = 0;
		_threads[free].Arg = arg;
		_threads[free].X = x;
		_threads[free].Y = y;
		_threads[free].Steps = 0;
		_threads[free].BindingKey = key;
		_threads[free].AutosaveRequested = false;

		for (var i = 0; i < _threads[free].Locals.Length; i += 1)
			_threads[free].Locals[i] = 0;

		Trace(description + " thread=" + free);
		Advance(ref host, free);

		return true;
	}

	void Advance<THost>(ref THost host, int threadId)
		where THost : IGameHost
	{
		while (_threads[threadId].Active && !_threads[threadId].Waiting)
		{
			switch (_threads[threadId].Phase)
			{
				case ThreadPhase.Enter:
					if (!EnterGroup(threadId))
					{
						Finish(ref host, threadId);

						return;
					}

					_threads[threadId].Phase = ThreadPhase.NextRule;
					break;
				case ThreadPhase.NextRule:
				{
					if (_threads[threadId].RuleIndex >= _threads[threadId].RuleCount)
					{
						Finish(ref host, threadId);

						return;
					}

					var header = RuleHeaderAt(_threads[threadId].Current.Chunk, _threads[threadId].RuleOffset);

					if (EvaluateConditions(ref host, threadId, header))
					{
						_threads[threadId].ActionOffset = header.ActionOffset;
						_threads[threadId].ActionEnd = header.NextRuleOffset;
						_threads[threadId].Next = header.Next;
						_threads[threadId].Phase = ThreadPhase.RunActions;
					}
					else
					{
						_threads[threadId].RuleOffset = header.NextRuleOffset;
						_threads[threadId].RuleIndex += 1;
					}

					break;
				}
				default:
				{
					if (!RunActions(ref host, threadId))
						return;

					if (_threads[threadId].Mode == GroupMode.First)
					{
						if (_threads[threadId].Next != Wire.None)
						{
							_threads[threadId].Group = _threads[threadId].Next;
							_threads[threadId].Phase = ThreadPhase.Enter;
						}
						else
						{
							Finish(ref host, threadId);

							return;
						}
					}
					else
					{
						var header = RuleHeaderAt(_threads[threadId].Current.Chunk, _threads[threadId].RuleOffset);

						_threads[threadId].RuleOffset = header.NextRuleOffset;
						_threads[threadId].RuleIndex += 1;
						_threads[threadId].Phase = ThreadPhase.NextRule;
					}

					break;
				}
			}
		}
	}

	bool EnterGroup(int threadId)
	{
		_threads[threadId].Steps += 1;

		if (_threads[threadId].Steps > _limits.MaxChainSteps)
		{
			Trace("abort thread: chain longer than " + _limits.MaxChainSteps + " steps");

			return false;
		}

		var chunk = Wire.IsLocalGroup(_threads[threadId].Group) ? _threads[threadId].Current : _global;
		int index = Wire.GroupIndex(_threads[threadId].Group);

		if (index >= chunk.Chunk.GroupCount)
		{
			Trace("abort thread: group " + index + " does not exist in " + ScopeKindName(chunk.Kind) + ":" + chunk.Id);

			return false;
		}

		var header = GroupHeaderAt(chunk.Chunk, index);

		_threads[threadId].Current = chunk;
		_threads[threadId].Mode = header.Mode;
		_threads[threadId].RuleCount = header.RuleCount;
		_threads[threadId].RuleIndex = 0;
		_threads[threadId].RuleOffset = header.FirstRuleOffset;

		return true;
	}

	/// Runs the actions of the current rule. Returns false if the thread blocked or ended.
	bool RunActions<THost>(ref THost host, int threadId)
		where THost : IGameHost
	{
		var chunk = _threads[threadId].Current.Chunk;

		while (_threads[threadId].ActionOffset < _threads[threadId].ActionEnd)
		{
			int offset = _threads[threadId].ActionOffset;
			uint16 instruction = WordAt(chunk, offset);
			uint8 op = Wire.InstructionOp(instruction);
			int length = Wire.InstructionLength(instruction);
			var operands = new uint16[length];

			for (var i = 0; i < length; i += 1)
				operands[i] = WordAt(chunk, offset + 2 + i * 2);

			_threads[threadId].ActionOffset = offset + 2 + length * 2;

			var outcome = ExecuteAction(ref host, threadId, (ActionOp)op, operands);

			if (!_threads[threadId].Active)
				return false;

			if (outcome == ActionOutcome.Blocked)
			{
				_threads[threadId].Waiting = true;

				return false;
			}
		}

		return true;
	}

	ThreadContext ContextOf(int threadId)
	{
		return ThreadContext
		{
			ThreadId = threadId,
			OwnerMap = _threads[threadId].OwnerMap,
			TriggerX = _threads[threadId].X,
			TriggerY = _threads[threadId].Y,
			TriggerArg = _threads[threadId].Arg,
			Result = _threads[threadId].Result,
			ScreenKey = _threads[threadId].HasScreen ? _threads[threadId].Screen.Key : -1
		};
	}

	ActionOutcome ExecuteAction<THost>(ref THost host, int threadId, ActionOp op, uint16[] operands)
		where THost : IGameHost
	{
		switch (op)
		{
			case ActionOp.SetFlag:
				return ChangeFlag(threadId, operands[0], FlagChange.Set);
			case ActionOp.ClearFlag:
				return ChangeFlag(threadId, operands[0], FlagChange.Clear);
			case ActionOp.ToggleFlag:
				return ChangeFlag(threadId, operands[0], FlagChange.Toggle);
			case ActionOp.SetVar:
				return ChangeVar(threadId, operands[0], (int16)operands[1], false);
			case ActionOp.AddVar:
				return ChangeVar(threadId, operands[0], (int16)operands[1], true);
			case ActionOp.SetVar32:
				return ChangeVar32(threadId, operands[0], (int)Wire.Combine(operands[1], operands[2]), false);
			case ActionOp.AddVar32:
				return ChangeVar32(threadId, operands[0], (int)Wire.Combine(operands[1], operands[2]), true);
			case ActionOp.CopyVar:
			{
				if (TryGetVar(threadId, operands[1]) is int16 value)
					return ChangeVar(threadId, operands[0], value, false);

				return Fault(threadId, "invalid slot " + Hex((int)operands[1], 4));
			}
			case ActionOp.Raise:
			{
				Enqueue(ReactiveEvent { Type = TriggerType.Custom, Slot = operands[0], Value = (int)(int16)operands[1], MapId = _threads[threadId].OwnerMap, ScreenKey = -1 });

				return ActionOutcome.Done;
			}
			case ActionOp.Wait:
				_threads[threadId].WaitTicks = Math.Max(1, (int)operands[0]);
				Trace("act wait ticks=" + _threads[threadId].WaitTicks);

				return ActionOutcome.Blocked;
			case ActionOp.Autosave:
				_threads[threadId].AutosaveRequested = true;

				return ActionOutcome.Done;
			default:
				break;
		}

		var context = ContextOf(threadId);
		var outcome = host.Execute(op, operands, context);

		Trace(outcome == ActionOutcome.Blocked ? "act " + ActionName(op) + " blocked" : "act " + ActionName(op));

		// push_screen with the nowait flag never blocks
		if ((op == ActionOp.PushScreen || op == ActionOp.ReplaceScreen) && operands.Length > 1 && ((int)operands[1] & 1) != 0)
			return ActionOutcome.Done;

		return outcome;
	}

	ActionOutcome ChangeFlag(int threadId, uint16 slot, FlagChange change)
	{
		if (FindStore(threadId, slot) is StateStore store)
		{
			int index = Wire.SlotIndex(slot);

			if (!store.IsValidFlag(index))
				return Fault(threadId, "invalid flag slot " + Hex((int)slot, 4));

			bool value = change == FlagChange.Set ? true : (change == FlagChange.Clear ? false : !store.GetFlag(index));

			if (store.SetFlag(index, value))
				Enqueue(ReactiveEvent { Type = TriggerType.FlagChanged, Slot = slot, Value = value ? 1 : 0, MapId = _threads[threadId].OwnerMap, ScreenKey = ScreenKeyOf(threadId, slot) });

			return ActionOutcome.Done;
		}

		return Fault(threadId, "invalid flag slot " + Hex((int)slot, 4));
	}

	ActionOutcome ChangeVar(int threadId, uint16 slot, int16 value, bool relative)
	{
		if (Wire.SlotNamespace(slot) == StateNamespace.Thread)
		{
			int local = Wire.SlotIndex(slot);

			if (local >= _threads[threadId].Locals.Length)
				return Fault(threadId, "invalid thread variable " + local);

			_threads[threadId].Locals[local] = relative ? Saturate((int)_threads[threadId].Locals[local] + (int)value) : value;

			return ActionOutcome.Done;
		}

		if (FindStore(threadId, slot) is StateStore store)
		{
			int index = Wire.SlotIndex(slot);

			if (!store.IsValidVar(index))
				return Fault(threadId, "invalid variable slot " + Hex((int)slot, 4));

			int16 result = relative ? Saturate((int)store.GetVar(index) + (int)value) : value;

			if (store.SetVar(index, result))
				Enqueue(ReactiveEvent { Type = TriggerType.VarChanged, Slot = slot, Value = (int)result, MapId = _threads[threadId].OwnerMap, ScreenKey = ScreenKeyOf(threadId, slot) });

			return ActionOutcome.Done;
		}

		return Fault(threadId, "invalid variable slot " + Hex((int)slot, 4));
	}

	ActionOutcome ChangeVar32(int threadId, uint16 slot, int value, bool relative)
	{
		if (FindStore(threadId, slot) is StateStore store)
		{
			int index = Wire.SlotIndex(slot);

			if (!store.IsValidVar32(index))
				return Fault(threadId, "invalid 32 bit variable slot " + Hex((int)slot, 4));

			int result = value;

			if (relative)
				result = (int)Math.Clamp((int64)store.GetVar32(index) + (int64)value, (int64)int.MinValue, (int64)int.MaxValue);

			store.SetVar32(index, result);

			return ActionOutcome.Done;
		}

		return Fault(threadId, "invalid 32 bit variable slot " + Hex((int)slot, 4));
	}

	int16 Saturate(int value)
	{
		return (int16)Math.Clamp(value, (int)int16.MinValue, (int)int16.MaxValue);
	}

	Optional<StateStore> FindStore(int threadId, uint16 slot)
	{
		switch (Wire.SlotNamespace(slot))
		{
			case StateNamespace.Global:
				return _global.State;
			case StateNamespace.Map:
			{
				if (_threads[threadId].OwnerMap >= 0)
				{
					if (_maps.TryGet(_threads[threadId].OwnerMap) is LoadedChunk map)
						return map.State;
				}

				return null;
			}
			case StateNamespace.Screen:
			{
				if (_threads[threadId].HasScreen)
					return _threads[threadId].Screen.State;

				return null;
			}
			default:
				return null;
		}
	}

	int ScreenKeyOf(int threadId, uint16 slot)
	{
		return Wire.SlotNamespace(slot) == StateNamespace.Screen && _threads[threadId].HasScreen ? _threads[threadId].Screen.Key : -1;
	}

	Optional<int16> TryGetVar(int threadId, uint16 slot)
	{
		if (Wire.SlotNamespace(slot) == StateNamespace.Thread)
		{
			int local = Wire.SlotIndex(slot);

			if (local >= _threads[threadId].Locals.Length)
				return null;

			return _threads[threadId].Locals[local];
		}

		if (FindStore(threadId, slot) is StateStore store)
		{
			if (!store.IsValidVar(Wire.SlotIndex(slot)))
				return null;

			return store.GetVar(Wire.SlotIndex(slot));
		}

		return null;
	}

	ActionOutcome Fault(int threadId, string message)
	{
		Trace("fault: " + message);
		_threads[threadId].Active = false;

		return ActionOutcome.Done;
	}

	void Enqueue(ReactiveEvent reactiveEvent)
	{
		if (_reactive.Count() >= _limits.MaxPendingEvents)
		{
			Trace("drop event " + TriggerName(reactiveEvent.Type) + " (queue full)");

			return;
		}

		_reactive.Add(reactiveEvent);
	}

	void Finish<THost>(ref THost host, int threadId)
		where THost : IGameHost
	{
		if (_threads[threadId].AutosaveRequested && _threads[threadId].Active)
		{
			var context = ContextOf(threadId);

			host.Execute(ActionOp.Autosave, new uint16[0], context);
			_threads[threadId].AutosaveRequested = false;
		}

		if (_threads[threadId].Active)
			Trace("end thread=" + threadId);

		_threads[threadId].Active = false;
	}

	bool EvaluateConditions<THost>(ref THost host, int threadId, RuleHeader header)
		where THost : IGameHost
	{
		var chunk = _threads[threadId].Current.Chunk;
		int offset = header.ConditionOffset;
		bool clauseTrue = false;

		while (offset < header.ActionOffset)
		{
			uint16 instruction = WordAt(chunk, offset);
			uint8 op = Wire.InstructionOp(instruction);
			int length = Wire.InstructionLength(instruction);
			var operands = new uint16[length];

			for (var i = 0; i < length; i += 1)
				operands[i] = WordAt(chunk, offset + 2 + i * 2);

			offset += 2 + length * 2;

			bool value = EvaluateCondition(ref host, threadId, (ConditionOp)op, operands) != Wire.InstructionNeg(instruction);

			clauseTrue = clauseTrue || value;

			if (!Wire.InstructionOrNext(instruction))
			{
				if (!clauseTrue)
					return false;

				clauseTrue = false;
			}
		}

		return true;
	}

	bool EvaluateCondition<THost>(ref THost host, int threadId, ConditionOp op, uint16[] operands)
		where THost : IGameHost
	{
		switch (op)
		{
			case ConditionOp.Flag:
			{
				if (FindStore(threadId, operands[0]) is StateStore store)
					return store.IsValidFlag(Wire.SlotIndex(operands[0])) && store.GetFlag(Wire.SlotIndex(operands[0]));

				return false;
			}
			case ConditionOp.Var:
			{
				if (TryGetVar(threadId, operands[0]) is int16 value)
					return Compare((int64)value, operands[1], (int64)(int16)operands[2]);

				return false;
			}
			case ConditionOp.Var32:
			{
				if (FindStore(threadId, operands[0]) is StateStore store)
				{
					return store.IsValidVar32(Wire.SlotIndex(operands[0]))
						&& Compare((int64)store.GetVar32(Wire.SlotIndex(operands[0])), operands[1], (int64)(int)Wire.Combine(operands[2], operands[3]));
				}

				return false;
			}
			case ConditionOp.VarVar:
			{
				if (TryGetVar(threadId, operands[0]) is int16 a)
				{
					if (TryGetVar(threadId, operands[2]) is int16 b)
						return Compare((int64)a, operands[1], (int64)b);
				}

				return false;
			}
			case ConditionOp.Result:
				return Compare((int64)_threads[threadId].Result, operands[0], (int64)(int16)operands[1]);
			case ConditionOp.Arg:
				return Compare((int64)(int)_threads[threadId].Arg, operands[0], (int64)(int)Wire.Combine(operands[1], operands[2]));
			case ConditionOp.Chance:
				return (((uint32)NextRandom16() * 100) >> 16) < (uint32)operands[0];
			default:
				break;
		}

		var context = ContextOf(threadId);

		return host.Evaluate(op, operands, context);
	}

	/// xorshift32 (spec section 12.1); returns the upper 16 bit of the new state.
	uint16 NextRandom16()
	{
		uint32 random = _counters[0].Random;

		random = random ^ (random << 13);
		random = random ^ (random >> 17);
		random = random ^ (random << 5);
		_counters[0].Random = random;

		return (uint16)(random >> 16);
	}

	void Trace(string message)
	{
		if (_tracing)
			_trace.Add("tick=" + _counters[0].Ticks + " " + message);
	}
}

bool Compare(int64 left, uint16 comparison, int64 right)
{
	switch ((Comparison)comparison)
	{
		case Comparison.Equal:
			return left == right;
		case Comparison.NotEqual:
			return left != right;
		case Comparison.Less:
			return left < right;
		case Comparison.LessOrEqual:
			return left <= right;
		case Comparison.Greater:
			return left > right;
		case Comparison.GreaterOrEqual:
			return left >= right;
		default:
			return false;
	}
}

bool Matches(BindingRecord binding, const ref TriggerContext context)
{
	switch (binding.Scope)
	{
		case TriggerScope.Tile:
			if (context.X != binding.Sx || context.Y != binding.Sy)
				return false;

			break;
		case TriggerScope.Area:
		{
			if (binding.Trigger == TriggerType.EnterTile || binding.Trigger == TriggerType.LeaveTile)
			{
				if (!Inside(binding, context.X, context.Y) || Inside(binding, context.OtherX, context.OtherY))
					return false;
			}
			else if (!Inside(binding, context.X, context.Y))
			{
				return false;
			}

			break;
		}
		case TriggerScope.Entity:
			if (context.EntityId != (int)binding.Sx)
				return false;

			break;
		case TriggerScope.Screen:
			if (context.ScreenId != (int)binding.Sx)
				return false;

			break;
		case TriggerScope.Node:
			if (context.NodeId != (int)binding.Sx)
				return false;

			break;
		default:
			break;
	}

	switch (binding.Trigger)
	{
		case TriggerType.SeeParty:
			return context.Param <= binding.P1;
		case TriggerType.Click:
		case TriggerType.RegionClick:
			return binding.P1 == Wire.None || ((int)binding.P1 & (int)context.Param) != 0;
		case TriggerType.UseItem:
		case TriggerType.CastSpell:
		case TriggerType.BattleEnd:
		case TriggerType.ItemGained:
		case TriggerType.MemberJoined:
		case TriggerType.MemberLeft:
		case TriggerType.WeatherChange:
		case TriggerType.Hour:
		case TriggerType.Key:
			return binding.P1 == Wire.None || binding.P1 == context.Param;
		default:
			return true;
	}
}

bool Inside(BindingRecord binding, uint16 x, uint16 y)
{
	if (x == Wire.None || y == Wire.None)
		return false;

	return (int)x >= (int)binding.Sx && (int)x < (int)binding.Sx + (int)binding.Sw && (int)y >= (int)binding.Sy && (int)y < (int)binding.Sy + (int)binding.Sh;
}

string ActionName(ActionOp op)
{
	if (ActionTable.ByOp((int)op) is OpInfo info)
		return info.Name;

	return ActionOpName(op);
}

string TriggerName(TriggerType type)
{
	if (TriggerTable.ByType(type) is TriggerInfo info)
		return info.Name;

	return TriggerTypeName(type);
}

// Reads that a loaded chunk must allow: a damaged chunk ends the program (C#: an exception that nobody catches).

uint16 WordAt(ScriptChunk chunk, int offset)
{
	var result = chunk.ReadGroupWord(offset);

	if (result is uint16 word)
		return word;

	Environment.Panic(result.Message);

	return 0;
}

BindingRecord BindingAt(ScriptChunk chunk, int index)
{
	var result = chunk.ReadBinding(index);

	if (result is BindingRecord binding)
		return binding;

	Environment.Panic(result.Message);

	return new BindingRecord();
}

GroupHeader GroupHeaderAt(ScriptChunk chunk, int index)
{
	var result = chunk.ReadGroupHeader(index);

	if (result is GroupHeader header)
		return header;

	Environment.Panic(result.Message);

	return new GroupHeader();
}

RuleHeader RuleHeaderAt(ScriptChunk chunk, int offset)
{
	var result = chunk.ReadRuleHeader(offset);

	if (result is RuleHeader header)
		return header;

	Environment.Panic(result.Message);

	return new RuleHeader();
}
