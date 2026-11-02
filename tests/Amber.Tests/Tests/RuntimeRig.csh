namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Runtime;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

/// An action the fake host was asked to do.
struct HostAction
{
	ActionOp Op;
	uint16[] Operands;
	ThreadContext Context;
}

/// Records the actions, blocks the chosen ones and answers the host conditions from a table. Copies share the lists.
struct FakeHost : IGameHost
{
	List<HostAction> Actions;
	List<ActionOp> Blocking;
	Dictionary<ConditionOp, bool> Conditions;

	static FakeHost Create()
	{
		return FakeHost { Actions = List<HostAction>.Create(), Blocking = List<ActionOp>.Create(), Conditions = Dictionary<ConditionOp, bool>.Create() };
	}

	ActionOutcome Execute(ActionOp op, uint16[] operands, const ref ThreadContext context)
	{
		Actions.Add(HostAction { Op = op, Operands = operands, Context = context });

		return Blocking.Contains(op) ? ActionOutcome.Blocked : ActionOutcome.Done;
	}

	bool Evaluate(ConditionOp op, uint16[] operands, const ref ThreadContext context)
	{
		return Conditions.GetOrDefault(op, false);
	}

	/// The opcodes of the recorded actions.
	int[] Ops()
	{
		var ops = new int[Actions.Count()];

		for (var i = 0; i < ops.Length; i += 1)
			ops[i] = (int)Actions.Get(i).Op;

		return ops;
	}

	int Count(ActionOp op)
	{
		int count = 0;

		foreach (var action in Actions)
		{
			if (action.Op == op)
				count += 1;
		}

		return count;
	}
}

/// The recorded actions are exactly these opcodes (C#: Assert.Equal([ActionOp.Say, ...], host.Ops)).
Error<void> OpsAre(FakeHost host, ActionOp[] expected)
{
	var ops = new int[expected.Length];

	for (var i = 0; i < ops.Length; i += 1)
		ops[i] = (int)expected[i];

	return Assert.Ints(ops, host.Ops());
}

/// A compiled script with its interpreter, the fake host and the trace (C#: Rig).
struct Rig
{
	CompilationResult Result;
	FakeHost Host;
	Interpreter Interpreter;
	List<string> Trace;

	static Error<Rig> Create(string source)
	{
		return Create(source, RuntimeLimits.Default());
	}

	static Error<Rig> Create(string source, RuntimeLimits limits)
	{
		var result = ScriptCompiler.CompileText(source, "test.ams", CompileOptions { LenientSymbols = true });

		try NoErrors(result);

		var trace = List<string>.Create();
		var interpreter = Amber.Runtime.Interpreter.CreateTraced(result.Global.ToChunk(), SizesOf(result.Global), limits, trace);

		for (var i = 0; i < result.Maps.Count(); i += 1)
			interpreter.LoadMap(i, result.Maps.Get(i).ToChunk(), SizesOf(result.Maps.Get(i)));

		return Rig { Result = result, Host = FakeHost.Create(), Interpreter = interpreter, Trace = trace };
	}

	int Trigger(TriggerContext context)
	{
		return Interpreter.Trigger(ref Host, context);
	}

	void Resume(int threadId, int result)
	{
		Interpreter.Resume(ref Host, threadId, (int16)result);
	}

	void Tick()
	{
		Interpreter.Tick(ref Host);
	}

	Error<uint16> Symbol(SymbolKind kind, string name)
	{
		return ResolveSymbol(Result.Symbols, kind, name);
	}

	/// The state of a loaded map (C#: rig.Interpreter.GetMap(id)!).
	Error<LoadedChunk> Map(int mapId)
	{
		if (Interpreter.GetMap(mapId) is LoadedChunk map)
			return map;

		return error("the map " + mapId + " is not loaded", -1);
	}
}

/// The ID of a symbol (C#: Assert.True(symbols.TryResolve(kind, name, out word id))).
Error<uint16> ResolveSymbol(SymbolTable symbols, SymbolKind kind, string name)
{
	if (symbols.TryResolve(kind, name) is uint16 id)
		return id;

	return error("the symbol " + SymbolKindName(kind) + " " + name + " is not defined", -1);
}

StateSizes SizesOf(CompiledScope scope)
{
	return StateSizes.Of(scope.FlagCount.Get(), scope.VarCount.Get(), scope.Var32Count.Get());
}

/// The index of a flag of the scope (C#: rig.FlagIndex).
Error<int> FlagIndex(CompiledScope scope, string name)
{
	foreach (var entry in scope.Layout)
	{
		if (entry.Kind == SlotKind.Flag && entry.Name == name)
			return entry.Index;
	}

	return error("the flag " + name + " is not in the layout", -1);
}

/// A trigger of the global script with a parameter (hour(3) ...).
TriggerContext WithParam(TriggerType type, int param)
{
	var context = TriggerContext.Of(type);

	context.Param = (uint16)param;

	return context;
}

/// A trigger of a map without a position (map_enter ...).
TriggerContext OnMap(TriggerType type, int mapId)
{
	var context = TriggerContext.Of(type);

	context.MapId = mapId;

	return context;
}

/// A trigger at a tile of a map.
TriggerContext AtTile(TriggerType type, int mapId, int x, int y)
{
	var context = OnMap(type, mapId);

	context.X = (uint16)x;
	context.Y = (uint16)y;

	return context;
}

/// A movement trigger (enter_tile, leave_tile) with the other tile.
TriggerContext Moving(TriggerType type, int mapId, int x, int y, int otherX, int otherY)
{
	var context = AtTile(type, mapId, x, y);

	context.OtherX = (uint16)otherX;
	context.OtherY = (uint16)otherY;

	return context;
}
