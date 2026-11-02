namespace Amber.Pack;

using System;

enum PackedRoutineStepKind : uint8
{
	WalkTo = 0,
	Stay = 1,
	Sleep = 2
}

/// One step of a routine entry. Target is the name of a waypoint of the map (walk_to, else null), the host finds the way
/// there; Ticks is the time to stay.
struct PackedRoutineStep
{
	PackedRoutineStepKind Kind;
	string Target;
	int64 Ticks;
}

/// The steps which start at a time of day (minutes since midnight).
struct PackedRoutineEntry
{
	int Minute;
	PackedRoutineStep[] Steps;
}

/// The daily schedule of an NPC (spec section 7.4, baked into the MAP chunk). The ID is the number set_routine uses; the
/// first routine of an entity is its default routine.
struct PackedRoutine
{
	int Id;
	string Name;
	int EntityId;
	PackedRoutineEntry[] Entries;
}
