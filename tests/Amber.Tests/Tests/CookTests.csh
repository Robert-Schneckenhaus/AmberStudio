namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Conformance;
using Amber.Cook;
using Amber.Pack;
using Amber.Runtime;
using Amber.Screens;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

// The cook (compiler result to pack) and the loader: the game must behave the same from the pack as from the sources.

void RegisterCookTests(ref TestList tests)
{
	foreach (var file in ScenarioFiles())
		tests.Theory("Cook.AScenarioGivesTheSameTraceFromAPack", AScenarioGivesTheSameTraceFromAPack, file);

	tests.Fact("Cook.AScenarioCanNameAPackFile", AScenarioCanNameAPackFile);
	tests.Fact("Cook.ThePackHoldsScriptsMapsLayoutAndSymbols", ThePackHoldsScriptsMapsLayoutAndSymbols);
	tests.Fact("Cook.EntitiesOfAMapSurviveThePack", EntitiesOfAMapSurviveThePack);
	tests.Fact("Cook.RoutinesAreBakedIntoTheMapChunk", RoutinesAreBakedIntoTheMapChunk);
	tests.Fact("Cook.ScreensAreCookedWithTheirScriptsAndNatives", ScreensAreCookedWithTheirScriptsAndNatives);
	tests.Fact("Cook.TheLoadCheckNamesTheMissingNatives", TheLoadCheckNamesTheMissingNatives);
	tests.Fact("Cook.TextsAndTablesAreWritten", TextsAndTablesAreWritten);
	tests.Fact("Cook.ThePackCanLeaveOutTheDebugNames", ThePackCanLeaveOutTheDebugNames);
	tests.Fact("Cook.ScriptsWithErrorsAreNotCooked", ScriptsWithErrorsAreNotCooked);
	tests.Fact("Cook.AWrongLayoutHashIsALoadError", AWrongLayoutHashIsALoadError);
}

Error<CompilationResult> CompileShrine()
{
	return ScriptCompiler.CompileText(try File.ReadAllText(Path.Combine(ScenarioFolder(), "schrein.ams")), "schrein.ams", CompileOptions { LenientSymbols = true });
}

/// The content of a pack in memory.
Error<PackContent> ContentOf(uint8[] data)
{
	return PackContent.Of(try PackReader.FromMemory(data));
}

/// A map, entity or screen ID of the pack: the only one (C#: Assert.Single(pack.MapIds)).
Error<int> SingleId(List<int> ids)
{
	return Assert.Single(ids);
}

Error<void> AScenarioGivesTheSameTraceFromAPack(string[] arguments)
{
	string path = Path.Combine(ScenarioFolder(), arguments[0]);
	var scenario = try Scenario.Load(path);
	var fromSources = try ScenarioRunner.Run(scenario, false);
	var fromPack = try ScenarioRunner.Run(scenario, true);

	try Assert.True(fromPack.Failures.Count() == 0, "failures: " + JoinList("; ", fromPack.Failures));
	try SameTrace(ArrayOf(fromSources.Trace), ArrayOf(fromPack.Trace));
	try SameTrace(try GoldenLines(path), ArrayOf(fromPack.Trace));

	return;
}

Error<void> AScenarioCanNameAPackFile()
{
	string folder = NewTempFolder("cook");

	try PackBuilder.Create(try CompileShrine()).Save(Path.Combine(folder, "schrein.pack"));

	string text = (try File.ReadAllText(Path.Combine(ScenarioFolder(), "schrein.scenario"))).Replace("script schrein.ams", "pack schrein.pack");
	var result = try ScenarioRunner.Run(try Scenario.Parse(text, folder, "scenario"), false);

	try Assert.True(result.Failures.Count() == 0, "failures: " + JoinList("; ", result.Failures));
	try SameTrace(try GoldenLines(Path.Combine(ScenarioFolder(), "schrein.scenario")), ArrayOf(result.Trace));

	return;
}

Error<void> ThePackHoldsScriptsMapsLayoutAndSymbols()
{
	var result = try CompileShrine();
	var pack = try ContentOf(try PackBuilder.Create(result).Build());

	try Assert.Equal(result.LayoutHash, pack.Header().LayoutHash);
	try Assert.Equal(result.LayoutHash, (try pack.Layout()).Hash());
	try Assert.Bytes(result.Global.GroupsChunk.Get(), (try pack.GlobalScript()).Groups);
	try Assert.True(pack.Header().SymbolsIncluded());

	int mapId = try SingleId(pack.MapIds());
	var map = try pack.LoadMap(mapId);
	var source = try Assert.Single(result.Maps);

	try Assert.Equal("spannenberg_keller", map.Name);
	try Assert.Equal(source.FlagCount.Get(), map.Sizes.Flags);
	try Assert.Bytes(source.GroupsChunk.Get(), map.Script.Groups);
	try Assert.Bytes(source.BindingsChunk.Get(), map.Script.Bindings);

	bool amulet = false;

	foreach (var symbol in try pack.Symbols())
		amulet = amulet || (symbol.Name == "amulett" && symbol.Kind == (uint8)SymbolKind.Item);

	try Assert.True(amulet, "the symbol I.amulett");
	try pack.CreateInterpreter();

	return;
}

Error<void> EntitiesOfAMapSurviveThePack()
{
	var result = ScriptCompiler.CompileText("map m { npc oma at (4, 7) { } npc bob at (2, 3) { } }", "test.ams", CompileOptions { LenientSymbols = true });

	try NoErrors(result);

	var pack = try ContentOf(try PackBuilder.Create(result).Build());
	var map = try pack.LoadMap(try SingleId(pack.MapIds()));
	var infos = result.Maps.Get(0).EntityInfos;

	try Assert.Equal(infos.Count(), map.Entities.Length);

	for (var i = 0; i < infos.Count(); i += 1)
	{
		var info = infos.Get(i);
		var entity = map.Entities[i];

		try Assert.Equal(info.Name, entity.Name);
		try Assert.Ints(new int[] { info.Id, info.X, info.Y }, new int[] { entity.Id, entity.X, entity.Y });
	}

	try Assert.NotEmpty(map.Entities);

	return;
}

Error<void> SameStep(PackedRoutineStepKind kind, string target, int64 ticks, PackedRoutineStep actual)
{
	try Assert.Equal((int)kind, (int)actual.Kind);
	try Assert.Equal(target, actual.Target);
	try Assert.Equal(ticks, actual.Ticks);

	return;
}

Error<void> RoutinesAreBakedIntoTheMapChunk()
{
	var result = ScriptCompiler.CompileText("map m {\n"
		+ "  npc mira at (4, 7) {\n"
		+ "    routine day { 07:00 sleep; 06:00 walk_to bench; stay 1h; 09:30 walk_to stone; walk_to bench; stay 30s; }\n"
		+ "    routine night { 20:00 sleep; }\n"
		+ "  }\n"
		+ "  npc bob at (2, 3) { routine walk { 08:00 walk_to stone; } }\n"
		+ "}", "test.ams", CompileOptions { LenientSymbols = true });

	try NoErrors(result);

	var pack = try ContentOf(try PackBuilder.Create(result).Build());
	var map = try pack.LoadMap(try SingleId(pack.MapIds()));
	int mira = result.Maps.Get(0).Entities.GetOrDefault("mira", -1);
	int bob = result.Maps.Get(0).Entities.GetOrDefault("bob", -1);
	var names = List<string>.Create();
	var ids = List<int>.Create();
	var entities = List<int>.Create();

	foreach (var routine in map.Routines)
	{
		names.Add(routine.Name);
		ids.Add(routine.Id);
		entities.Add(routine.EntityId);
	}

	try Assert.Strings(new string[] { "day", "night", "walk" }, names);
	try Assert.Ints(new int[] { 0, 1, 2 }, ArrayOf(ids));
	try Assert.Ints(new int[] { mira, mira, bob }, ArrayOf(entities));

	// the entries are sorted by time, the durations are ticks
	var day = map.Routines[0];

	try Assert.Ints(new int[] { 360, 420, 570 }, new int[] { day.Entries[0].Minute, day.Entries[1].Minute, day.Entries[2].Minute });
	try Assert.Equal(2, day.Entries[0].Steps.Length);
	try SameStep(PackedRoutineStepKind.WalkTo, "bench", 0, day.Entries[0].Steps[0]);
	try SameStep(PackedRoutineStepKind.Stay, null, 6000, day.Entries[0].Steps[1]);
	try Assert.Equal(1, day.Entries[1].Steps.Length);
	try SameStep(PackedRoutineStepKind.Sleep, null, 0, day.Entries[1].Steps[0]);

	var targets = List<string>.Create();

	foreach (var step in day.Entries[2].Steps)
	{
		if (step.Target != null)
			targets.Add(step.Target);
	}

	try Assert.Strings(new string[] { "stone", "bench" }, targets);
	try Assert.Equal(1500, day.Entries[2].Steps[day.Entries[2].Steps.Length - 1].Ticks);

	// what the cook bakes is what the game gets from the pack
	var baked = List<string>.Create();

	foreach (var routine in try RoutineBaker.Bake(result.Maps.Get(0)))
		baked.Add(routine.Name);

	return Assert.Strings(ArrayOf(baked), names);
}

Error<void> ScreensAreCookedWithTheirScriptsAndNatives()
{
	string folder = RootPath("examples/screens");
	var library = try ScreenLibrary.Load(folder);
	var result = ScriptCompiler.CompileText(try File.ReadAllText(Path.Combine(folder, "screens.ams")), "screens.ams", CompileOptions { LenientSymbols = true, Screens = library.Signatures() });

	try NoErrors(result);

	var builder = PackBuilder.Create(result);

	builder.Screens = library;

	var pack = try ContentOf(try builder.Build());

	try Assert.Equal(library.Screens.Count(), pack.ScreenIds().Count());

	int chestId = (int)(try ResolveSymbol(result.Symbols, SymbolKind.Screen, "chest"));
	var chest = try pack.LoadScreen(chestId);
	var definition = try FindScreen(library, "chest");

	try Assert.Equal(ScreenDefinition.Flatten(definition.Nodes).Count(), chest.Definition.Nodes.Length);
	try Assert.NotEqual(Wire.None, chest.Definition.OnOpen);

	var chestScope = result.FindScreen("chest");

	try Assert.True(chestScope is CompiledScope, "the screen scope chest");

	if (chestScope is CompiledScope scope)
		try Assert.Bytes(scope.GroupsChunk.Get(), chest.Script.Groups);

	// the data sources of the nodes are natives of the pack, marked as sources
	var natives = try pack.Natives();
	bool gold = false;

	foreach (var native in natives)
		gold = gold || (native.Name == "chest.gold" && native.DataSource);

	try Assert.True(gold, "the data source chest.gold");
	try Assert.Equal(natives.Count(), pack.Header().NativeCount);

	// the icons are in the UI graphics table
	bool take = false;

	foreach (var name in try pack.Names(PackTableUiGraphics))
		take = take || name.Name == "take";

	return Assert.True(take, "the icon take");
}

Error<void> TheLoadCheckNamesTheMissingNatives()
{
	var result = ScriptCompiler.CompileText("group g { do { native(N.one, 0); native(N.two, 0); } }\non hour(1) -> g;", "test.ams", CompileOptions { LenientSymbols = true });
	var pack = try ContentOf(try PackBuilder.Create(result).Build());
	var names = List<string>.Create();

	foreach (var native in try pack.Natives())
		names.Add(native.Name);

	try Assert.Strings(new string[] { "one", "two" }, names);
	try pack.RequireNatives(new string[] { "one", "two", "three" });

	string message = try Assert.FailsVoid(pack.RequireNatives(new string[] { "one" }), ErrorKind.MissingNative);

	return Assert.Strings(new string[] { "two" }, MissingNativeNames(message));
}

Dictionary<int, string> Strings2(int firstKey, string firstText, int secondKey, string secondText)
{
	var strings = Dictionary<int, string>.Create();

	strings.Set(firstKey, firstText);

	if (secondText != null)
		strings.Set(secondKey, secondText);

	return strings;
}

Error<void> TextsAndTablesAreWritten()
{
	var builder = PackBuilder.Create(try CompileShrine());

	builder.AddTexts(0, Strings2(1, "Hello", 3, "Café"));
	builder.AddTexts(1, Strings2(1, "Hallo", 0, null));
	try builder.AddStringTable(PackTableFirstGameTable, Strings2(2, "Elder", 0, null));

	var pack = try ContentOf(try builder.Build());

	try Assert.Equal("Café", (try pack.Texts(0)).GetOrDefault(3, null));
	try Assert.Equal("Hallo", (try pack.Texts(1)).GetOrDefault(1, null));
	try Assert.Equal(0, (try pack.Texts(2)).Count());
	try Assert.Equal("Elder", (try pack.Strings(PackTableFirstGameTable)).GetOrDefault(2, null));
	try Assert.FailsVoid(builder.AddStringTable(1, Dictionary<int, string>.Create()), ErrorKind.Argument);

	return;
}

Error<void> ThePackCanLeaveOutTheDebugNames()
{
	var builder = PackBuilder.Create(try CompileShrine());

	builder.IncludeSymbols = false;

	var reader = try PackReader.FromMemory(try builder.Build());
	var pack = PackContent.Of(reader);

	try Assert.False(pack.Header().SymbolsIncluded());
	try Assert.Empty(try pack.Symbols());
	try Assert.False(reader.Contains(PackChunkType.Symbols, 0));

	return;
}

Error<void> ScriptsWithErrorsAreNotCooked()
{
	var result = ScriptCompiler.CompileText("group g { when flag(nope) do { } }", "test.ams", CompileOptions { LenientSymbols = true });

	try Assert.Fails(PackBuilder.Create(result).Build(), ErrorKind.InvalidOperation);

	return;
}

Error<void> AWrongLayoutHashIsALoadError()
{
	var data = try PackBuilder.Create(try CompileShrine()).Build();

	data[19] = (uint8)((int)data[19] ^ 0xFF);

	try Assert.Fails((try ContentOf(data)).CreateInterpreter(), ErrorKind.InvalidPack);

	return;
}
