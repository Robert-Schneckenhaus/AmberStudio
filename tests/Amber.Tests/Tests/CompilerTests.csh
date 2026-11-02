namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

void RegisterCompilerTests(ref TestList tests)
{
	tests.Fact("Compiler.SpecExampleEncodesExactly", SpecExampleEncodesExactly);
	tests.Fact("Compiler.BindingEncodesExactly", BindingEncodesExactly);
	tests.Fact("Compiler.ChunkReaderReadsWhatTheEncoderWrote", ChunkReaderReadsWhatTheEncoderWrote);
	tests.Fact("Compiler.PaletteActionsCompile", PaletteActionsCompile);

	foreach (var file in AmsFiles())
		tests.Theory("Compiler.ExamplesCompileWithoutErrors", ExamplesCompileWithoutErrors, file);

	tests.Fact("Compiler.PresetsExampleShareGroupsAndKeepInstanceState", PresetsExampleShareGroupsAndKeepInstanceState);
	tests.Theory("Compiler.ReportsError", ReportsError, "group g { when flag(nope) do { } }", "E001");
	tests.Theory("Compiler.ReportsError", ReportsError, "group g { do { say(T.a); } then missing; }", "E004");
	tests.Theory("Compiler.ReportsError", ReportsError, "group g all { do { say(T.a); } then g; }", "E005");
	tests.Theory("Compiler.ReportsError", ReportsError, "group g { else do { } when chance(5) do { } }", "E011");
	tests.Theory("Compiler.ReportsError", ReportsError, "group g { do { set_tile(1, here, +1); } }\non enter_tile at (1, 1) -> g;\non map_enter -> g;", "E020");
	tests.Theory("Compiler.ReportsError", ReportsError, "map m { group g { do { set_tile(1, here, 5); } } on map_enter -> g; }", "E015");
	tests.Theory("Compiler.ReportsError", ReportsError, "flag a; flag a;", "E002");
	tests.Theory("Compiler.ReportsError", ReportsError, "group g { do { push_screen(S.x, 0, 2, 1); } }", "E014");
	tests.Theory("Compiler.ReportsError", ReportsError, "group g { do { give_item(I.a); } }", "E003");
	tests.Theory("Compiler.ReportsError", ReportsError, "preset bad(x) on step { do { } }\nmap m { use bad() at (1,1); }", "E017");
	tests.Theory("Compiler.ReportsError", ReportsError, "preset action set_flag() = say(T.a);", "E019");
	tests.Theory("Compiler.ReportsError", ReportsError, "group a { do { say(T.a); } then b; }\ngroup b { do { say(T.a); } then a; }", "E006");
	tests.Fact("Compiler.GlobalScriptCannotUseMapSlots", GlobalScriptCannotUseMapSlots);
	tests.Fact("Compiler.UnknownNativeFunctionIsReportedAsE013", UnknownNativeFunctionIsReportedAsE013);
	tests.Theory("Compiler.ReportsWarning", ReportsWarning, "flag a; group g { do { set_flag(a); } }\non hour(1) -> g;", "W002");
	tests.Theory("Compiler.ReportsWarning", ReportsWarning, "flag a; group g { do { clear_flag(a); } }\non hour(1) -> g;", "W002");
	tests.Theory("Compiler.ReportsWarning", ReportsWarning, "flag a; group g { when flag(a) do { } }\non hour(1) -> g;", "W003");
	tests.Theory("Compiler.ReportsWarning", ReportsWarning, "flag a; group g { when not flag(a) do { } }\non hour(1) -> g;", "W003");
	tests.Theory("Compiler.ReportsWarning", ReportsWarning, "group g { do { autosave(); say(T.a); } }\non hour(1) -> g;", "W004");
	tests.Theory("Compiler.ReportsWarning", ReportsWarning, "group g { do { autosave(); } then h; }\ngroup h { do { } }\non hour(1) -> g;", "W004");
	tests.Theory("Compiler.DoesNotWarnForUsedFlagsAndFinalAutosave", DoesNotWarnForUsedFlagsAndFinalAutosave, "flag a; group g { when flag(a) do { set_flag(a); } }\non hour(1) -> g;");
	tests.Theory("Compiler.DoesNotWarnForUsedFlagsAndFinalAutosave", DoesNotWarnForUsedFlagsAndFinalAutosave, "flag a; group g { do { toggle_flag(a); } }\non hour(1) -> g;");
	tests.Theory("Compiler.DoesNotWarnForUsedFlagsAndFinalAutosave", DoesNotWarnForUsedFlagsAndFinalAutosave, "flag a; group g { do { set_flag(a); } }\ngroup h { do { } }\non flag_changed(a, set) -> h;\non hour(1) -> g;");
	tests.Theory("Compiler.DoesNotWarnForUsedFlagsAndFinalAutosave", DoesNotWarnForUsedFlagsAndFinalAutosave, "group g { once do { say(T.a); } }\non hour(3) -> g;");
	tests.Theory("Compiler.DoesNotWarnForUsedFlagsAndFinalAutosave", DoesNotWarnForUsedFlagsAndFinalAutosave, "group g { do { say(T.a); autosave(); } }\non hour(1) -> g;");
	tests.Theory("Compiler.DoesNotWarnForUsedFlagsAndFinalAutosave", DoesNotWarnForUsedFlagsAndFinalAutosave, "flag a; group g { do { set_flag(a); } }\nmap m { group h { when flag(a) do { } } on map_enter -> h; }\non hour(1) -> g;");
	tests.Fact("Compiler.ThreadVariablesAreAvailableWithoutDeclaration", ThreadVariablesAreAvailableWithoutDeclaration);
	tests.Fact("Compiler.OnceAddsFlagAndSetFlag", OnceAddsFlagAndSetFlag);
	tests.Fact("Compiler.ConditionsUseConjunctiveNormalForm", ConditionsUseConjunctiveNormalForm);
	tests.Fact("Compiler.ConversationBecomesBindingsAndGroups", ConversationBecomesBindingsAndGroups);
	tests.Fact("Compiler.RosettaExampleProducesAllBindingsWithoutHereProblems", RosettaExampleProducesAllBindingsWithoutHereProblems);
}

CompilationResult CompileLenient(string source)
{
	return ScriptCompiler.CompileText(source, "test.ams", CompileOptions { LenientSymbols = true });
}

/// The error diagnostics as text.
List<string> Errors(CompilationResult result)
{
	var errors = List<string>.Create();

	foreach (var item in result.Diagnostics.Items)
	{
		if (item.Severity == Severity.Error)
			errors.Add(item.Text());
	}

	return errors;
}

/// The result has no errors (C#: Assert.Empty(Errors(result))), the check names them.
Error<void> NoErrors(CompilationResult result)
{
	var errors = Errors(result);

	return Assert.True(errors.Count() == 0, "unexpected errors: " + JoinList("; ", errors));
}

uint16[] WordsOf(uint8[] data, int startByte, int wordCount)
{
	var words = new uint16[wordCount];

	for (var i = 0; i < wordCount; i += 1)
		words[i] = (uint16)(((int)data[startByte + i * 2] << 8) | (int)data[startByte + i * 2 + 1]);

	return words;
}

Error<void> SpecExampleEncodesExactly()
{
	// spec section 6.2: flag 137 = 0x0089, T.geist = 42, G.geist = 7
	var symbols = SymbolTable.Create(true);

	symbols.Define(SymbolKind.Text, "geist", 42);
	symbols.Define(SymbolKind.MonsterGroup, "geist", 7);

	var source = StringBuilder.Create();

	for (var i = 0; i < 137; i += 1)
		source.Append("flag dummy" + i + ";\n");

	source.Append("flag schrein_benutzt;\n"
		+ "group schrein first {\n"
		+ "\twhen not flag(schrein_benutzt) and hour_in(20, 6)\n"
		+ "\tdo { say(T.geist); set_flag(schrein_benutzt); battle(G.geist, 0); }\n"
		+ "}");

	var result = ScriptCompiler.CompileText(source.ToString(), "test.ams", CompileOptions { Symbols = symbols });

	try NoErrors(result);

	var chunk = result.Global.GroupsChunk.Get();

	// group table: count 1, reserved, offset 8 (hi, lo); then the record
	try Assert.Words(new uint16[] { 1, 0, 0, 8 }, WordsOf(chunk, 0, 4));
	try Assert.Words(new uint16[]
	{
		0x0001, 0x0012,
		0x0005, 0x0007, 0xFFFF, 0x0000,
		0x0105, 0x0089, 0x1208, 0x0014, 0x0006,
		0x4004, 0x002A, 0x0104, 0x0089, 0x3008, 0x0007, 0x0000
	}, WordsOf(chunk, 8, 18));
	try Assert.Equal(8 + 18 * 2, chunk.Length);

	return;
}

Error<void> BindingEncodesExactly()
{
	// spec section 6.3
	var result = CompileLenient("map m {\n"
		+ "\tgroup schrein { do { sfx(SND.x); } }\n"
		+ "\ton step at (3, 4) -> schrein;\n"
		+ "}");

	try NoErrors(result);

	var bindings = result.Maps.Get(0).BindingsChunk.Get();

	try Assert.Words(new uint16[] { 1, 0 }, WordsOf(bindings, 0, 2));
	try Assert.Words(new uint16[] { 0x0302, 0x8000, 0x0000, 0x0000, 0x0003, 0x0004, 0x0000, 0x0000 }, WordsOf(bindings, 4, 8));

	return;
}

Error<void> ChunkReaderReadsWhatTheEncoderWrote()
{
	var result = CompileLenient("flag a;\n"
		+ "group g first {\n"
		+ "\twhen flag(a) do { set_flag(a); } then h;\n"
		+ "\telse do { clear_flag(a); }\n"
		+ "}\n"
		+ "group h { do { sfx(SND.x); } }");

	try NoErrors(result);

	var chunk = result.Global.ToChunk();

	try Assert.Equal(2, chunk.GroupCount);

	var header = try chunk.ReadGroupHeader(0);

	try Assert.Equal((int)GroupMode.First, (int)header.Mode);
	try Assert.Equal(2, header.RuleCount);

	var rule = try chunk.ReadRuleHeader(header.FirstRuleOffset);

	try Assert.Equal(Wire.GlobalGroup(1), rule.Next);
	try Assert.Equal(2, rule.ConditionWords);
	try Assert.Equal(2, rule.ActionWords);

	return;
}

/// set_palette and fade_palette take a palette (PAL.name) or 0xFFFF to give the palette back to day and night.
Error<void> PaletteActionsCompile()
{
	var result = CompileLenient("group g { do { set_palette(PAL.dusk); fade_palette(PAL.dusk, 50, 1); set_palette(0xFFFF); flash(0xFD8, 40); } }\non hour(1) -> g;");

	try NoErrors(result);

	string dump = try ScriptDumper.Dump(result.Global.ToChunk());

	try Assert.Contains("set_palette", dump);
	try Assert.Contains("fade_palette", dump);
	try Assert.Contains("65535", dump);

	return;
}

Error<void> ExamplesCompileWithoutErrors(string[] arguments)
{
	string file = arguments[0];
	var result = ScriptCompiler.CompileText(try ReadRootText(file), file, CompileOptions { LenientSymbols = true });

	return NoErrors(result);
}

Error<void> PresetsExampleShareGroupsAndKeepInstanceState()
{
	var result = ScriptCompiler.CompileText(try File.ReadAllText(Example("presets", "presets.ams")), "presets.ams", CompileOptions { LenientSymbols = true });

	try NoErrors(result);

	var map = try Assert.Single(result.Maps);

	// two lever uses, flip, two bindings to the shared group "tor" and one to the lever-triggered gate
	bool hasLever = false;

	foreach (var group in map.Groups)
		hasLever = hasLever || group.Name.StartsWith("lever@");

	try Assert.True(hasLever, "a group lever@...");

	int interactions = 0;

	foreach (var binding in map.Bindings)
	{
		if (binding.Trigger == TriggerType.Interact && binding.Scope == TriggerScope.Tile)
			interactions += 1;
	}

	try Assert.Equal(6, interactions);

	// give_once has its own flag
	bool hasFlag = false;

	foreach (var entry in map.Layout)
		hasFlag = hasFlag || entry.Name.StartsWith("__give_once_");

	try Assert.True(hasFlag, "a flag __give_once_...");

	return;
}

Error<void> ReportsError(string[] arguments)
{
	var result = CompileLenient(arguments[0]);

	return Assert.True(result.Diagnostics.Contains(arguments[1], Severity.Error), arguments[1] + " is reported as an error");
}

Error<void> GlobalScriptCannotUseMapSlots()
{
	var result = CompileLenient("map m { flag a; }\ngroup g { when flag(a) do { } }\non hour(1) -> g;");

	try Assert.True(result.Diagnostics.Contains("E007", Severity.Error), "E007 is reported");
	try Assert.False(result.Diagnostics.ContainsCode("E001"), "E001 is not reported");

	return;
}

Error<void> UnknownNativeFunctionIsReportedAsE013()
{
	var symbols = SymbolTable.Create(false);

	symbols.Define(SymbolKind.Native, "known", 1);

	var result = ScriptCompiler.CompileText("group g { do { native(N.known, 0); native(N.missing, 0); } }\non hour(1) -> g;", "test.ams", CompileOptions { Symbols = symbols });
	var errors = List<Diagnostic>.Create();

	foreach (var item in result.Diagnostics.Items)
	{
		if (item.Severity == Severity.Error)
			errors.Add(item);
	}

	try Assert.Equal("E013", (try Assert.Single(errors)).Code);

	return;
}

Error<void> ReportsWarning(string[] arguments)
{
	var result = CompileLenient(arguments[0]);

	try NoErrors(result);
	try Assert.True(result.Diagnostics.Contains(arguments[1], Severity.Warning), arguments[1] + " is reported as a warning");

	return;
}

Error<void> DoesNotWarnForUsedFlagsAndFinalAutosave(string[] arguments)
{
	var result = CompileLenient(arguments[0]);

	try NoErrors(result);
	try Assert.False(result.Diagnostics.ContainsCode("W002") || result.Diagnostics.ContainsCode("W003") || result.Diagnostics.ContainsCode("W004"), "no W002, W003 or W004");

	return;
}

Error<void> ThreadVariablesAreAvailableWithoutDeclaration()
{
	var result = CompileLenient("group g first { do { set_var(t0, 5); add_var(t7, 2); } then h; }\ngroup h first { when t0 == 5 do { } }\non hour(1) -> g;");

	try NoErrors(result);

	var actions = result.Global.Groups.Get(0).Rules.Get(0).Actions;
	var condition = try Assert.Single(result.Global.Groups.Get(1).Rules.Get(0).Conditions);

	try Assert.Equal(Wire.Slot(StateNamespace.Thread, 0), actions.Get(0).Operands[0]);
	try Assert.Equal(Wire.Slot(StateNamespace.Thread, 7), actions.Get(1).Operands[0]);
	try Assert.Equal(Wire.Slot(StateNamespace.Thread, 0), condition.Operands[0]);
	try Assert.Empty(result.Global.Layout);

	// only t0 to t7 exist
	try Assert.True(CompileLenient("group g { do { set_var(t8, 1); } }").Diagnostics.ContainsCode("E001"), "t8 is E001");

	return;
}

Error<void> OnceAddsFlagAndSetFlag()
{
	var result = CompileLenient("group g { once do { say(T.a); } }\non hour(3) -> g;");

	try NoErrors(result);

	var rule = result.Global.Groups.Get(0).Rules.Get(0);
	var condition = try Assert.Single(rule.Conditions);

	try Assert.Equal((int)ConditionOp.Flag, (int)condition.Op);
	try Assert.True(condition.Neg);
	try Assert.Equal((int)ActionOp.SetFlag, (int)rule.Actions.Get(0).Op);
	try Assert.Equal(condition.Operands[0], rule.Actions.Get(0).Operands[0]);

	return;
}

Error<void> ConditionsUseConjunctiveNormalForm()
{
	var result = CompileLenient("flag a; flag b; flag c;\ngroup g { when (flag(a) or flag(b)) and not flag(c) do { } }\non hour(1) -> g;");

	try NoErrors(result);

	var conditions = result.Global.Groups.Get(0).Rules.Get(0).Conditions;

	try Assert.Equal(3, conditions.Count());
	try Assert.True(conditions.Get(0).OrNext);
	try Assert.False(conditions.Get(1).OrNext);
	try Assert.False(conditions.Get(2).OrNext);
	try Assert.True(conditions.Get(2).Neg);

	return;
}

Error<void> ConversationBecomesBindingsAndGroups()
{
	var result = ScriptCompiler.CompileText(try File.ReadAllText(Example("conversation", "shandra.ams")), "shandra.ams", CompileOptions { LenientSymbols = true });

	try NoErrors(result);

	var map = try Assert.Single(result.Maps);
	bool keywordBinding = false;
	bool showItem = false;
	bool giveItem = false;

	foreach (var binding in map.Bindings)
	{
		keywordBinding = keywordBinding || (binding.Trigger == TriggerType.Keyword && binding.Scope == TriggerScope.Entity);
		showItem = showItem || binding.Trigger == TriggerType.ShowItem;
		giveItem = giveItem || binding.Trigger == TriggerType.GiveItem;
	}

	try Assert.True(keywordBinding, "a keyword binding of the entity");
	try Assert.True(showItem, "a show_item binding");
	try Assert.True(giveItem, "a give_item binding");

	// the last topic ("*") is an unconditional else rule
	var keyword = try Assert.Single(GroupsNamed(map, "shandra$keyword"));

	try Assert.Empty(keyword.Rules.Get(keyword.Rules.Count() - 1).Conditions);

	return;
}

List<IrGroup> GroupsNamed(CompiledScope scope, string name)
{
	var groups = List<IrGroup>.Create();

	foreach (var group in scope.Groups)
	{
		if (group.Name == name)
			groups.Add(group);
	}

	return groups;
}

Error<void> RosettaExampleProducesAllBindingsWithoutHereProblems()
{
	var result = ScriptCompiler.CompileText(try File.ReadAllText(Example("rosetta", "amberstar-events.ams")), "rosetta.ams", CompileOptions { LenientSymbols = true });

	try NoErrors(result);
	try Assert.Equal(24, result.Maps.Get(0).Bindings.Count());

	return;
}
