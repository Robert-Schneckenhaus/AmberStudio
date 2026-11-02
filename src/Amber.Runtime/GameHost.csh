namespace Amber.Runtime;

using System;
using Amber.Script.Common;

/// Result of executing an action in the host.
enum ActionOutcome : int32
{
	/// The action is complete, the thread continues.
	Done,
	/// The thread waits until the host calls Interpreter.Resume.
	Blocked
}

/// Data of the running thread which conditions and actions may need. OwnerMap: ID of the map the rule belongs to or -1.
/// TriggerX/TriggerY: the trigger position ("here") or Wire.None. Result: of the last blocking action. ScreenKey: key of the
/// screen instance (LoadedChunk.Key) if the rule belongs to a screen, else -1.
struct ThreadContext
{
	int ThreadId;
	int OwnerMap;
	uint16 TriggerX;
	uint16 TriggerY;
	uint32 TriggerArg;
	int16 Result;
	int ScreenKey;
}

/// The native mechanisms of the game. The interpreter handles state changes, results, the random generator and waiting
/// itself and forwards everything else to the host. The interpreter functions that run scripts take the host as a
/// 'ref THost host' parameter (a generic constraint, CShift has no interface values).
interface IGameHost
{
	/// Executes an action. Operands are the raw words of the instruction (spec section 5).
	ActionOutcome Execute(ActionOp op, uint16[] operands, const ref ThreadContext context);

	/// Evaluates a condition which depends on game data (party, time, map ...).
	bool Evaluate(ConditionOp op, uint16[] operands, const ref ThreadContext context);
}

/// Describes an event of the host for which bindings are searched. Create it with Of(type): the other fields start at
/// "none" (-1 or Wire.None).
struct TriggerContext
{
	TriggerType Type;
	/// Map which is the owner of map-bound bindings (or -1).
	int MapId;
	uint16 X;
	uint16 Y;
	/// The other tile for enter_tile/leave_tile (where the party came from or goes to), used for area scopes.
	uint16 OtherX;
	uint16 OtherY;
	int EntityId;
	int ScreenId;
	int NodeId;
	/// Value compared with the trigger parameter p1 (item, spell, hour, range ...).
	uint16 Param;
	/// Value available to rules as trigger_arg.
	uint32 Arg;

	static TriggerContext Of(TriggerType type)
	{
		return TriggerContext
		{
			Type = type, MapId = -1, X = Wire.None, Y = Wire.None, OtherX = Wire.None, OtherY = Wire.None, EntityId = -1, ScreenId = -1,
			NodeId = -1, Param = Wire.None, Arg = 0
		};
	}
}

/// Fixed limits (spec section 2.5). They come from the pack header.
struct RuntimeLimits
{
	int MaxThreads;
	int MaxChainSteps;
	int MaxPendingEvents;

	static RuntimeLimits Default()
	{
		return RuntimeLimits { MaxThreads = 16, MaxChainSteps = 64, MaxPendingEvents = 32 };
	}

	static RuntimeLimits Of(int maxThreads, int maxChainSteps, int maxPendingEvents)
	{
		return RuntimeLimits { MaxThreads = maxThreads, MaxChainSteps = maxChainSteps, MaxPendingEvents = maxPendingEvents };
	}
}

/// A host that does nothing: every action is done, every condition false.
struct NullHost : IGameHost
{
	ActionOutcome Execute(ActionOp op, uint16[] operands, const ref ThreadContext context)
	{
		return ActionOutcome.Done;
	}

	bool Evaluate(ConditionOp op, uint16[] operands, const ref ThreadContext context)
	{
		return false;
	}
}
