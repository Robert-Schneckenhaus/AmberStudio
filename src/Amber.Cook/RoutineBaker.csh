// Turns the routines of a map (spec section 7.4) into the schedule tables of the MAP chunk. The waypoints stay names: the
// host knows the map and finds the way (the script cook does not see the tiles).

namespace Amber.Cook.RoutineBaker;

using System;
using Amber.Base;
using Amber.Pack;
using Amber.Script.Compilation;
using Amber.Script.Syntax;

Error<List<PackedRoutine>> Bake(CompiledScope map)
{
	var routines = List<PackedRoutine>.Create();

	foreach (var info in map.RoutineInfos)
	{
		var found = map.Entities.TryGet(info.Entity);

		if (found == null)
			return error("The routine '" + info.Name + "' belongs to the unknown entity '" + info.Entity + "'.", (int)ErrorKind.InvalidData);

		int entity = 0;

		if (found is int id)
			entity = id;

		var entries = SortArray(info.Node.Entries, CompareByMinute);
		var packed = new PackedRoutineEntry[entries.Length];

		for (var i = 0; i < entries.Length; i += 1)
		{
			var steps = new PackedRoutineStep[entries[i].Steps.Length];

			for (var s = 0; s < steps.Length; s += 1)
				steps[s] = Step(entries[i].Steps[s]);

			packed[i] = PackedRoutineEntry { Minute = (int)entries[i].Minute, Steps = steps };
		}

		routines.Add(PackedRoutine { Id = info.Id, Name = info.Name, EntityId = entity, Entries = packed });
	}

	return routines;
}

int CompareByMinute(RoutineEntry a, RoutineEntry b)
{
	return a.Minute < b.Minute ? -1 : (a.Minute > b.Minute ? 1 : 0);
}

PackedRoutineStep Step(RoutineStep step)
{
	switch (step.Kind)
	{
		case RoutineStepKind.WalkTo:
			return PackedRoutineStep { Kind = PackedRoutineStepKind.WalkTo, Target = step.Target, Ticks = 0 };
		case RoutineStepKind.Stay:
		{
			int64 ticks = TicksPerGameMinute;

			if (step.Duration is DurationValue duration)
				ticks = duration.ToTicks();

			return PackedRoutineStep { Kind = PackedRoutineStepKind.Stay, Target = null, Ticks = ticks };
		}
		default:
			return PackedRoutineStep { Kind = PackedRoutineStepKind.Sleep, Target = null, Ticks = 0 };
	}
}
