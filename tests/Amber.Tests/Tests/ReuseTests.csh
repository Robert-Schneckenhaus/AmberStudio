namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Runtime;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

void RegisterReuseTests(ref TestList tests)
{
	tests.Fact("Reuse.IdenticalPresetInstancesShareOneGroup", IdenticalPresetInstancesShareOneGroup);
	tests.Fact("Reuse.DeduplicationCanBeSwitchedOff", DeduplicationCanBeSwitchedOff);
	tests.Fact("Reuse.MergedNamesKeepTheirGroupReferences", MergedNamesKeepTheirGroupReferences);
	tests.Fact("Reuse.ThenReferencesFollowMergedGroups", ThenReferencesFollowMergedGroups);
	tests.Fact("Reuse.DeduplicationDoesNotChangeBehaviour", DeduplicationDoesNotChangeBehaviour);
	tests.Fact("Reuse.LayoutHashIsStableAndChangesWithTheLayout", LayoutHashIsStableAndChangesWithTheLayout);
	tests.Fact("Reuse.StatisticsListShapesChainsAndDuplicates", StatisticsListShapesChainsAndDuplicates);
}

const string LeversSource = "preset lever(off: tile, on: tile) on interact {\n"
	+ "\twhen tile_is(1, here, off) do { set_tile(1, here, on); }\n"
	+ "\twhen tile_is(1, here, on)  do { set_tile(1, here, off); }\n"
	+ "}\n"
	+ "preset give_once(what: item) on examine {\n"
	+ "\tflag taken;\n"
	+ "\twhen not flag(taken) do { give_item(what, 1); set_flag(taken); }\n"
	+ "}\n"
	+ "map m {\n"
	+ "\tuse lever(TILE.up, TILE.down) at (1, 1);\n"
	+ "\tuse lever(TILE.up, TILE.down) at (2, 2);\n"
	+ "\tuse lever(TILE.left, TILE.right) at (3, 3);\n"
	+ "\tuse give_once(I.herb) at (4, 4);\n"
	+ "\tuse give_once(I.herb) at (5, 5);\n"
	+ "}";

CompilationResult CompileReuse(string source, bool deduplicate)
{
	return ScriptCompiler.CompileText(source, "test.ams", CompileOptions { LenientSymbols = true, NoDeduplicate = !deduplicate });
}

Error<void> IdenticalPresetInstancesShareOneGroup()
{
	var result = CompileReuse(LeversSource, true);

	try Assert.False(result.HasErrors());

	var map = result.Maps.Get(0);

	// 3 lever uses (2 identical) + 2 give_once uses (own flags, never identical)
	try Assert.Equal(4, map.Groups.Count());
	try Assert.Equal(1, result.DuplicateGroupsRemoved);
	try Assert.Equal(map.Bindings.Get(0).Group, map.Bindings.Get(1).Group);
	try Assert.NotEqual(map.Bindings.Get(0).Group, map.Bindings.Get(2).Group);
	try Assert.NotEqual(map.Bindings.Get(3).Group, map.Bindings.Get(4).Group);

	return;
}

Error<void> DeduplicationCanBeSwitchedOff()
{
	var result = CompileReuse(LeversSource, false);

	try Assert.Equal(5, result.Maps.Get(0).Groups.Count());
	try Assert.Equal(0, result.DuplicateGroupsRemoved);

	return;
}

Error<void> MergedNamesKeepTheirGroupReferences()
{
	var result = CompileReuse(LeversSource, true);
	var map = result.Maps.Get(0);

	foreach (var lever in map.Groups)
	{
		if (lever.Aliases.Count() > 0)
			return Assert.Equal(map.GroupRefs.GetOrDefault(lever.Name, 0), map.GroupRefs.GetOrDefault(lever.Aliases.Get(0), 1));
	}

	return Assert.True(false, "no group has aliases");
}

Error<void> ThenReferencesFollowMergedGroups()
{
	var result = CompileReuse("flag a;\n"
		+ "group tail_a { do { sfx(SND.x); } }\n"
		+ "group tail_b { do { sfx(SND.x); } }\n"
		+ "group head_a { do { say(T.one); } then tail_a; }\n"
		+ "group head_b { do { say(T.two); } then tail_b; }\n"
		+ "on hour(1) -> head_a;\n"
		+ "on hour(2) -> head_b;", true);

	try Assert.False(result.HasErrors());
	try Assert.Equal(3, result.Global.Groups.Count());

	// both heads end in the single remaining tail
	uint16 tail = result.Global.GroupRefs.GetOrDefault("tail_a", 0);

	try Assert.Equal(tail, result.Global.GroupRefs.GetOrDefault("tail_b", 1));

	foreach (var group in result.Global.Groups)
	{
		if (group.Name.StartsWith("head"))
			try Assert.Equal(tail, group.Rules.Get(0).Next);
	}

	return;
}

Error<void> DeduplicationDoesNotChangeBehaviour()
{
	foreach (bool dedup in new bool[] { false, true })
	{
		var result = CompileReuse(LeversSource, dedup);
		var host = FakeHost.Create();
		var interpreter = Interpreter.Create(result.Global.ToChunk(), SizesOf(result.Global), RuntimeLimits.Default());

		interpreter.LoadMap(0, result.Maps.Get(0).ToChunk(), SizesOf(result.Maps.Get(0)));

		foreach (int x in new int[] { 1, 2, 3 })
			interpreter.Trigger(ref host, AtTile(TriggerType.Interact, 0, x, x));

		// give_once keeps its own flag per use: two different herbs, the repeated examine does nothing
		interpreter.Trigger(ref host, AtTile(TriggerType.Examine, 0, 4, 4));
		interpreter.Trigger(ref host, AtTile(TriggerType.Examine, 0, 4, 4));
		interpreter.Trigger(ref host, AtTile(TriggerType.Examine, 0, 5, 5));

		try Assert.Equal(2, host.Count(ActionOp.GiveItem));
	}

	return;
}

Error<void> LayoutHashIsStableAndChangesWithTheLayout()
{
	var first = CompileReuse("flag a; var b;", true);
	var same = CompileReuse("flag a; var b;", true);
	var changed = CompileReuse("flag a; flag c; var b;", true);

	try Assert.Equal(first.LayoutHash, same.LayoutHash);
	try Assert.NotEqual(first.LayoutHash, changed.LayoutHash);
	try Assert.Contains("Global global Global.Flag[0] a", first.LayoutText);

	return;
}

Error<void> StatisticsListShapesChainsAndDuplicates()
{
	string text = PatternStatistics.Create(CompileReuse(LeversSource, false), 20);

	try Assert.Contains("## Most frequent rule shapes", text);
	try Assert.Contains("tile_is => set_tile", text);
	try Assert.Contains("## Chains (then)", text);
	try Assert.Contains("Groups with identical rules", text);

	return;
}
