namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Runtime;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

void RegisterRuntimeTests(ref TestList tests)
{
	tests.Fact("Runtime.ThenChainContinuesWithTheResultOfABlockingAction", ThenChainContinuesWithTheResultOfABlockingAction);
	tests.Fact("Runtime.WrongAnswerTakesTheElseRule", WrongAnswerTakesTheElseRule);
	tests.Fact("Runtime.FirstModeRunsOnlyTheFirstMatchingRule", FirstModeRunsOnlyTheFirstMatchingRule);
	tests.Fact("Runtime.AllModeRunsEveryMatchingRule", AllModeRunsEveryMatchingRule);
	tests.Theory("Runtime.ConditionsFollowConjunctiveNormalForm", ConditionsFollowConjunctiveNormalForm, new string[] { "false", "false", "false", "false" });
	tests.Theory("Runtime.ConditionsFollowConjunctiveNormalForm", ConditionsFollowConjunctiveNormalForm, new string[] { "true", "false", "false", "true" });
	tests.Theory("Runtime.ConditionsFollowConjunctiveNormalForm", ConditionsFollowConjunctiveNormalForm, new string[] { "false", "true", "false", "true" });
	tests.Theory("Runtime.ConditionsFollowConjunctiveNormalForm", ConditionsFollowConjunctiveNormalForm, new string[] { "true", "true", "false", "true" });
	tests.Theory("Runtime.ConditionsFollowConjunctiveNormalForm", ConditionsFollowConjunctiveNormalForm, new string[] { "true", "false", "true", "false" });
	tests.Theory("Runtime.ConditionsFollowConjunctiveNormalForm", ConditionsFollowConjunctiveNormalForm, new string[] { "false", "false", "true", "false" });
	tests.Fact("Runtime.OneGroupServesManyBindingsWithTheirOwnTriggerPosition", OneGroupServesManyBindingsWithTheirOwnTriggerPosition);
	tests.Fact("Runtime.AreaEnterFiresOnlyWhenCrossingTheBorder", AreaEnterFiresOnlyWhenCrossingTheBorder);
	tests.Fact("Runtime.RunGroupStartsAScreenHandlerWithArgumentAndScreenKey", RunGroupStartsAScreenHandlerWithArgumentAndScreenKey);
	tests.Fact("Runtime.NativeTakesASymbolAndArguments", NativeTakesASymbolAndArguments);
	tests.Fact("Runtime.MapStateSurvivesUnloadAndReloadWithTheSameStore", MapStateSurvivesUnloadAndReloadWithTheSameStore);
	tests.Fact("Runtime.InteractionTriggersAcceptAnAreaAndFireForEveryTileInIt", InteractionTriggersAcceptAnAreaAndFireForEveryTileInIt);
	tests.Fact("Runtime.ReactiveBindingsFireOncePerRealChangeOnTheNextTick", ReactiveBindingsFireOncePerRealChangeOnTheNextTick);
	tests.Fact("Runtime.RaiseStartsCustomSubscribers", RaiseStartsCustomSubscribers);
	tests.Fact("Runtime.ABindingDoesNotRestartWhileItsThreadIsRunning", ABindingDoesNotRestartWhileItsThreadIsRunning);
	tests.Fact("Runtime.ChainsAreLimited", ChainsAreLimited);
	tests.Fact("Runtime.WaitBlocksForTheGivenNumberOfTicks", WaitBlocksForTheGivenNumberOfTicks);
	tests.Fact("Runtime.OnceRunsOnlyOnce", OnceRunsOnlyOnce);
	tests.Fact("Runtime.ConversationKeywordsSelectTheMatchingTopic", ConversationKeywordsSelectTheMatchingTopic);
	tests.Fact("Runtime.ScreenNamespaceHoldsTheArguments", ScreenNamespaceHoldsTheArguments);
	tests.Fact("Runtime.AutosaveHappensAtTheEndOfTheChain", AutosaveHappensAtTheEndOfTheChain);
	tests.Fact("Runtime.RandomNumbersAreDeterministic", RandomNumbersAreDeterministic);
	tests.Fact("Runtime.ChanceExtremesAreExact", ChanceExtremesAreExact);
	tests.Fact("Runtime.StateHashChangesWithTheState", StateHashChangesWithTheState);
	tests.Fact("Runtime.HostConditionsAreForwarded", HostConditionsAreForwarded);
	tests.Fact("Runtime.MapStateIsSeparatePerMap", MapStateIsSeparatePerMap);
}

const string MouthSource = "map m {\n"
	+ "\tflag riddle_active;\n"
	+ "\tflag riddle_solved;\n"
	+ "\n"
	+ "\ton speak at (14, 9) -> mouth_speak;\n"
	+ "\n"
	+ "\tgroup mouth_speak first {\n"
	+ "\t\twhen flag(riddle_active) do { ask_word(W.schleuder); } then mouth_answer;\n"
	+ "\t\telse                     do { say(T.mouth_silent); }\n"
	+ "\t}\n"
	+ "\tgroup mouth_answer first {\n"
	+ "\t\twhen result == 1 do { set_tile(1, 15, 9, TILE.passage); set_flag(riddle_solved); }\n"
	+ "\t\telse             do { trap(TRAP.spikes, 20); }\n"
	+ "\t}\n"
	+ "}";

Error<void> ThenChainContinuesWithTheResultOfABlockingAction()
{
	var rig = try Rig.Create(MouthSource);
	var map = rig.Result.Maps.Get(0);

	rig.Host.Blocking.Add(ActionOp.AskWord);
	(try rig.Map(0)).State.SetFlag(try FlagIndex(map, "riddle_active"), true);

	try Assert.Equal(1, rig.Trigger(AtTile(TriggerType.Speak, 0, 14, 9)));
	try OpsAre(rig.Host, new ActionOp[] { ActionOp.AskWord });

	int threadId = rig.Host.Actions.Get(0).Context.ThreadId;

	rig.Resume(threadId, 1);

	try OpsAre(rig.Host, new ActionOp[] { ActionOp.AskWord, ActionOp.SetTile });
	try Assert.True((try rig.Map(0)).State.GetFlag(try FlagIndex(map, "riddle_solved")), "riddle_solved is set");
	try Assert.Equal(0, rig.Interpreter.ActiveThreadCount());

	return;
}

Error<void> WrongAnswerTakesTheElseRule()
{
	var rig = try Rig.Create(MouthSource);

	rig.Host.Blocking.Add(ActionOp.AskWord);
	(try rig.Map(0)).State.SetFlag(try FlagIndex(rig.Result.Maps.Get(0), "riddle_active"), true);
	rig.Trigger(AtTile(TriggerType.Speak, 0, 14, 9));
	rig.Resume(rig.Host.Actions.Get(0).Context.ThreadId, 0);

	return OpsAre(rig.Host, new ActionOp[] { ActionOp.AskWord, ActionOp.Trap });
}

Error<void> FirstModeRunsOnlyTheFirstMatchingRule()
{
	var rig = try Rig.Create("flag a;\n"
		+ "group g first { when flag(a) do { sfx(SND.one); } else do { sfx(SND.two); } }\n"
		+ "on hour(3) -> g;");

	rig.Trigger(WithParam(TriggerType.Hour, 3));

	try Assert.Equal(try rig.Symbol(SymbolKind.Sound, "two"), (try Assert.Single(rig.Host.Actions)).Operands[0]);

	rig.Host.Actions.Clear();
	rig.Interpreter.Global().SetFlag(0, true);
	rig.Trigger(WithParam(TriggerType.Hour, 3));

	try Assert.Equal(try rig.Symbol(SymbolKind.Sound, "one"), (try Assert.Single(rig.Host.Actions)).Operands[0]);

	return;
}

Error<void> AllModeRunsEveryMatchingRule()
{
	var rig = try Rig.Create("flag a;\n"
		+ "group g all {\n"
		+ "\tdo { sfx(SND.one); }\n"
		+ "\twhen flag(a) do { sfx(SND.two); }\n"
		+ "\tdo { sfx(SND.three); }\n"
		+ "}\n"
		+ "on hour(3) -> g;");

	rig.Trigger(WithParam(TriggerType.Hour, 3));

	try Assert.Equal(2, rig.Host.Actions.Count());

	rig.Host.Actions.Clear();
	rig.Interpreter.Global().SetFlag(0, true);
	rig.Trigger(WithParam(TriggerType.Hour, 3));

	try Assert.Equal(3, rig.Host.Actions.Count());

	return;
}

Error<void> ConditionsFollowConjunctiveNormalForm(string[] arguments)
{
	var rig = try Rig.Create("flag a; flag b; flag c;\ngroup g { when (flag(a) or flag(b)) and not flag(c) do { sfx(SND.x); } }\non hour(1) -> g;");

	rig.Interpreter.Global().SetFlag(0, arguments[0] == "true");
	rig.Interpreter.Global().SetFlag(1, arguments[1] == "true");
	rig.Interpreter.Global().SetFlag(2, arguments[2] == "true");
	rig.Trigger(WithParam(TriggerType.Hour, 1));

	return Assert.Equal(arguments[3] == "true", rig.Host.Actions.Count() == 1);
}

Error<void> OneGroupServesManyBindingsWithTheirOwnTriggerPosition()
{
	var rig = try Rig.Create("map m {\n"
		+ "\tgroup toggle { do { set_tile(1, here, +1); } }\n"
		+ "\ton interact at (12, 6) -> toggle;\n"
		+ "\ton interact at (30, 4) -> toggle;\n"
		+ "}");

	rig.Trigger(AtTile(TriggerType.Interact, 0, 30, 4));

	var action = try Assert.Single(rig.Host.Actions);

	try Assert.Equal((int)ActionOp.SetTile, (int)action.Op);
	try Assert.Words(new uint16[] { 1, Wire.Here, Wire.Here, Wire.RelativeTile(1) }, action.Operands);
	try Assert.Equal(30, action.Context.TriggerX);
	try Assert.Equal(4, action.Context.TriggerY);
	try Assert.Equal(0, action.Context.OwnerMap);

	return;
}

Error<void> AreaEnterFiresOnlyWhenCrossingTheBorder()
{
	var rig = try Rig.Create("map m { group g { do { sfx(SND.x); } }\non enter_tile in (10, 5, 3, 2) -> g;\non leave_tile in (10, 5, 3, 2) -> g; }");

	try Assert.Equal(1, rig.Trigger(Moving(TriggerType.EnterTile, 0, 10, 5, 9, 5)));
	try Assert.Equal(0, rig.Trigger(Moving(TriggerType.EnterTile, 0, 11, 5, 10, 5)));
	try Assert.Equal(1, rig.Trigger(Moving(TriggerType.LeaveTile, 0, 12, 6, 13, 6)));

	return;
}

Error<void> RunGroupStartsAScreenHandlerWithArgumentAndScreenKey()
{
	var result = ScriptCompiler.CompileText("screen dlg { group ok { do { sfx(SND.a); } } }", "test.ams", CompileOptions { LenientSymbols = true });

	try NoErrors(result);

	var host = FakeHost.Create();
	var interpreter = Interpreter.Create(result.Global.ToChunk(), SizesOf(result.Global), RuntimeLimits.Default());
	var screen = interpreter.LoadScreen(1, result.Screens.Get(0).ToChunk(), SizesOf(result.Screens.Get(0)));
	uint16 group = result.Screens.Get(0).GroupRefs.GetOrDefault("ok", Wire.None);

	try Assert.True(interpreter.RunGroup(ref host, screen, group, 7, -1), "the group runs");

	var action = try Assert.Single(host.Actions);

	try Assert.Equal((int)ActionOp.Sfx, (int)action.Op);
	try Assert.Equal(7, action.Context.TriggerArg);
	try Assert.Equal(screen.Key, action.Context.ScreenKey);

	return;
}

Error<void> NativeTakesASymbolAndArguments()
{
	var rig = try Rig.Create("group g { do { native(N.ask_word, 1, K.hello); } }\non hour(1) -> g;");

	rig.Trigger(WithParam(TriggerType.Hour, 1));

	var action = try Assert.Single(rig.Host.Actions);

	try Assert.Equal((int)ActionOp.Native, (int)action.Op);
	try Assert.Equal(3, action.Operands.Length);
	try Assert.Equal(try rig.Symbol(SymbolKind.Native, "ask_word"), action.Operands[0]);
	try Assert.Equal(1, action.Operands[1]);

	return;
}

Error<void> MapStateSurvivesUnloadAndReloadWithTheSameStore()
{
	var rig = try Rig.Create("map m { flag seen; group g { do { set_flag(seen); } }\non map_enter -> g; }");
	var scope = rig.Result.Maps.Get(0);
	int seen = try FlagIndex(scope, "seen");

	rig.Trigger(OnMap(TriggerType.MapEnter, 0));

	var state = (try rig.Map(0)).State;

	try Assert.True(state.GetFlag(seen), "seen is set");

	rig.Interpreter.UnloadMap(0, -1);

	try Assert.False(rig.Interpreter.GetMap(0) is LoadedChunk, "the map is unloaded");

	// the map-bound binding does not run while the map is unloaded
	try Assert.Equal(0, rig.Trigger(OnMap(TriggerType.MapEnter, 0)));

	var reloaded = rig.Interpreter.LoadMap(0, scope.ToChunk(), state);

	try Assert.True(reloaded.State.GetFlag(seen), "seen is still set");

	return;
}

Error<void> InteractionTriggersAcceptAnAreaAndFireForEveryTileInIt()
{
	var rig = try Rig.Create("map m { group g { do { sfx(SND.x); } }\non examine in (14, 18, 2, 1) -> g; }");

	try Assert.Equal(1, rig.Trigger(AtTile(TriggerType.Examine, 0, 14, 18)));
	try Assert.Equal(1, rig.Trigger(AtTile(TriggerType.Examine, 0, 15, 18)));
	try Assert.Equal(0, rig.Trigger(AtTile(TriggerType.Examine, 0, 16, 18)));
	try Assert.Equal(0, rig.Trigger(AtTile(TriggerType.Examine, 0, 14, 19)));

	return;
}

Error<void> ReactiveBindingsFireOncePerRealChangeOnTheNextTick()
{
	var rig = try Rig.Create("flag plague_cured;\n"
		+ "group start { do { set_flag(plague_cured); set_flag(plague_cured); } }\n"
		+ "group reaction { do { sfx(SND.party); } }\n"
		+ "on flag_changed(plague_cured, set) -> reaction;\n"
		+ "on hour(1) -> start;");

	rig.Trigger(WithParam(TriggerType.Hour, 1));

	try Assert.Empty(rig.Host.Actions);

	rig.Tick();

	try Assert.Equal(1, rig.Host.Actions.Count());

	rig.Tick();

	try Assert.Equal(1, rig.Host.Actions.Count());

	return;
}

Error<void> RaiseStartsCustomSubscribers()
{
	var rig = try Rig.Create("group start { do { raise(alarm, 5); } }\n"
		+ "group listener_a { do { sfx(SND.a); } }\n"
		+ "group listener_b { when arg == 5 do { sfx(SND.b); } }\n"
		+ "on custom(alarm) -> listener_a;\n"
		+ "on custom(alarm) -> listener_b;\n"
		+ "on hour(1) -> start;");

	rig.Trigger(WithParam(TriggerType.Hour, 1));
	rig.Tick();

	return Assert.Equal(2, rig.Host.Actions.Count());
}

Error<void> ABindingDoesNotRestartWhileItsThreadIsRunning()
{
	var rig = try Rig.Create("group g { do { say(T.a); } }\non hour(1) -> g;");

	rig.Host.Blocking.Add(ActionOp.Say);

	try Assert.Equal(1, rig.Trigger(WithParam(TriggerType.Hour, 1)));
	try Assert.Equal(0, rig.Trigger(WithParam(TriggerType.Hour, 1)));

	rig.Resume(rig.Host.Actions.Get(0).Context.ThreadId, 0);

	try Assert.Equal(1, rig.Trigger(WithParam(TriggerType.Hour, 1)));

	return;
}

Error<void> ChainsAreLimited()
{
	var rig = try Rig.Create("flag loop;\n"
		+ "group a { when flag(loop) do { sfx(SND.x); } then b; }\n"
		+ "group b { when flag(loop) do { sfx(SND.y); } then a; }\n"
		+ "on hour(1) -> a;", RuntimeLimits.Of(16, 8, 32));

	rig.Interpreter.Global().SetFlag(0, true);
	rig.Trigger(WithParam(TriggerType.Hour, 1));

	try Assert.Equal(8, rig.Host.Actions.Count());
	try Assert.Equal(0, rig.Interpreter.ActiveThreadCount());
	try Assert.AnyContains(rig.Trace, "chain longer");

	return;
}

Error<void> WaitBlocksForTheGivenNumberOfTicks()
{
	var rig = try Rig.Create("group g { do { wait(3); sfx(SND.x); } }\non hour(1) -> g;");

	rig.Trigger(WithParam(TriggerType.Hour, 1));
	rig.Tick();
	rig.Tick();

	try Assert.Empty(rig.Host.Actions);

	rig.Tick();

	return Assert.Equal(1, rig.Host.Actions.Count());
}

Error<void> OnceRunsOnlyOnce()
{
	var rig = try Rig.Create("group g { once do { sfx(SND.x); } }\non hour(1) -> g;");

	rig.Trigger(WithParam(TriggerType.Hour, 1));
	rig.Trigger(WithParam(TriggerType.Hour, 1));

	return Assert.Equal(1, rig.Host.Actions.Count());
}

Error<void> ConversationKeywordsSelectTheMatchingTopic()
{
	var result = ScriptCompiler.CompileText(try File.ReadAllText(Example("conversation", "shandra.ams")), "shandra.ams", CompileOptions { LenientSymbols = true });

	try NoErrors(result);

	var host = FakeHost.Create();
	var interpreter = Interpreter.Create(result.Global.ToChunk(), SizesOf(result.Global), RuntimeLimits.Default());

	interpreter.LoadMap(0, result.Maps.Get(0).ToChunk(), SizesOf(result.Maps.Get(0)));

	uint16 amberstar = try ResolveSymbol(result.Symbols, SymbolKind.Keyword, "amberstar");
	uint16 text1 = try ResolveSymbol(result.Symbols, SymbolKind.Text, "s_amberstar");
	uint16 textDefault = try ResolveSymbol(result.Symbols, SymbolKind.Text, "s_default");

	var context = OnMap(TriggerType.Keyword, 0);

	context.EntityId = 0;
	context.Arg = (uint32)amberstar;
	interpreter.Trigger(ref host, context);

	try OpsAre(host, new ActionOp[] { ActionOp.Say, ActionOp.LearnWord });
	try Assert.Equal(text1, host.Actions.Get(0).Operands[0]);

	host.Actions.Clear();
	context.Arg = 999;
	interpreter.Trigger(ref host, context);

	try Assert.Equal(textDefault, (try Assert.Single(host.Actions)).Operands[0]);

	return;
}

Error<void> ScreenNamespaceHoldsTheArguments()
{
	var result = ScriptCompiler.CompileText("screen confirmation {\n"
		+ "\tvar x;\n"
		+ "\ton screen_open -> check;\n"
		+ "\tgroup check { when x == 7 do { sfx(SND.yes); } else do { sfx(SND.no); } }\n"
		+ "}", "screen.ams", CompileOptions { LenientSymbols = true });

	try NoErrors(result);

	var host = FakeHost.Create();
	var interpreter = Interpreter.Create(result.Global.ToChunk(), SizesOf(result.Global), RuntimeLimits.Default());
	int screenId = (int)(try ResolveSymbol(result.Symbols, SymbolKind.Screen, "confirmation"));
	var screen = interpreter.LoadScreen(screenId, result.Screens.Get(0).ToChunk(), SizesOf(result.Screens.Get(0)));

	screen.State.SetVar(0, 7);

	var context = TriggerContext.Of(TriggerType.ScreenOpen);

	context.ScreenId = screenId;
	interpreter.Trigger(ref host, context);

	try Assert.Equal(try ResolveSymbol(result.Symbols, SymbolKind.Sound, "yes"), (try Assert.Single(host.Actions)).Operands[0]);

	return;
}

Error<void> AutosaveHappensAtTheEndOfTheChain()
{
	var rig = try Rig.Create("group g { do { autosave(); say(T.a); } }\non hour(1) -> g;");

	rig.Trigger(WithParam(TriggerType.Hour, 1));

	return OpsAre(rig.Host, new ActionOp[] { ActionOp.Say, ActionOp.Autosave });
}

Error<void> RandomNumbersAreDeterministic()
{
	var rig = try Rig.Create("group g { do { sfx(SND.x); } }\non hour(1) -> g;");

	rig.Interpreter.SetRandomState(12345);

	uint32 state = 12345;
	var expected = new uint16[5];

	for (var i = 0; i < expected.Length; i += 1)
	{
		state ^= state << 13;
		state ^= state >> 17;
		state ^= state << 5;
		expected[i] = (uint16)(state >> 16);
	}

	var actual = new uint16[5];

	for (var i = 0; i < actual.Length; i += 1)
		actual[i] = rig.Interpreter.NextRandom16();

	return Assert.Words(expected, actual);
}

Error<void> ChanceExtremesAreExact()
{
	var rig = try Rig.Create("group g all { when chance(100) do { sfx(SND.always); } when chance(0) do { sfx(SND.never); } }\non hour(1) -> g;");

	for (var i = 0; i < 50; i += 1)
		rig.Trigger(WithParam(TriggerType.Hour, 1));

	return Assert.Equal(50, rig.Host.Actions.Count());
}

Error<void> StateHashChangesWithTheState()
{
	var rig = try Rig.Create("flag a;\ngroup g { do { set_flag(a); } }\non hour(1) -> g;");
	uint32 before = rig.Interpreter.StateHash(-1);

	try Assert.Equal(before, rig.Interpreter.StateHash(-1));

	rig.Trigger(WithParam(TriggerType.Hour, 1));

	try Assert.NotEqual(before, rig.Interpreter.StateHash(-1));

	return;
}

Error<void> HostConditionsAreForwarded()
{
	var rig = try Rig.Create("group g { when hour_in(20, 6) do { sfx(SND.night); } else do { sfx(SND.day); } }\non hour(1) -> g;");

	rig.Host.Conditions.Set(ConditionOp.HourIn, true);
	rig.Trigger(WithParam(TriggerType.Hour, 1));

	return Assert.Equal(try rig.Symbol(SymbolKind.Sound, "night"), (try Assert.Single(rig.Host.Actions)).Operands[0]);
}

Error<void> MapStateIsSeparatePerMap()
{
	var rig = try Rig.Create("map a { flag f; group g { do { set_flag(f); } } on map_enter -> g; }\nmap b { flag f; }");

	rig.Trigger(OnMap(TriggerType.MapEnter, 0));

	try Assert.True((try rig.Map(0)).State.GetFlag(0), "the flag of map a is set");
	try Assert.False((try rig.Map(1)).State.GetFlag(0), "the flag of map b is clear");

	return;
}
