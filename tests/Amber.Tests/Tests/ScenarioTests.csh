namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Conformance;

// The golden trace harness (spec section 12.3, task 1.12): scenario files, the trace and its comparison.

void RegisterScenarioTests(ref TestList tests)
{
	foreach (var file in ScenarioFiles())
		tests.Theory("Scenario.ScenariosMatchTheirGoldenTraces", ScenariosMatchTheirGoldenTraces, file);

	tests.Fact("Scenario.RunsAreDeterministic", RunsAreDeterministic);
	tests.Fact("Scenario.TheSeedDecidesRandomOutcomes", TheSeedDecidesRandomOutcomes);
	tests.Fact("Scenario.FailedExpectationsAreReportedAndTraced", FailedExpectationsAreReportedAndTraced);
	tests.Fact("Scenario.AnAnswerWithoutAWaitingThreadIsAFailure", AnAnswerWithoutAWaitingThreadIsAFailure);
	tests.Theory("Scenario.BrokenScenariosAreRejected", BrokenScenariosAreRejected, "bogus 1", "unknown line");
	tests.Theory("Scenario.BrokenScenariosAreRejected", BrokenScenariosAreRejected, "at x fire step", "not a number");
	tests.Theory("Scenario.BrokenScenariosAreRejected", BrokenScenariosAreRejected, "at 5 fire step\nat 3 fire step", "backwards");
	tests.Theory("Scenario.BrokenScenariosAreRejected", BrokenScenariosAreRejected, "at 1", "needs more arguments");
	tests.Theory("Scenario.ScenariosWhichCannotRunAreRejected", ScenariosWhichCannotRunAreRejected, "script schrein.ams\nload map nowhere\n", "does not exist");
	tests.Theory("Scenario.ScenariosWhichCannotRunAreRejected", ScenariosWhichCannotRunAreRejected, "script schrein.ams\nload map spannenberg_keller\nat 0 fire no_such_trigger\n", "unknown trigger");
	tests.Theory("Scenario.ScenariosWhichCannotRunAreRejected", ScenariosWhichCannotRunAreRejected, "script schrein.ams\nload map spannenberg_keller\nat 0 fire enter_tile bogus=1\n", "unknown trigger parameter");
	tests.Theory("Scenario.ScenariosWhichCannotRunAreRejected", ScenariosWhichCannotRunAreRejected, "script schrein.ams\nload map spannenberg_keller\nat 0 expect flag nope\n", "unknown flag");
	tests.Fact("Scenario.TheComparerFindsTheFirstDifference", TheComparerFindsTheFirstDifference);
}

string ScenarioFolder()
{
	return RootPath("examples/scenarios");
}

/// The *.scenario files of examples/scenarios (file names).
List<string> ScenarioFiles()
{
	return FileNames("examples/scenarios", ".scenario");
}

/// The lines of the golden trace next to a scenario.
Error<string[]> GoldenLines(string scenarioPath)
{
	return TraceComparer.Lines(try File.ReadAllText(Path.ChangeExtension(scenarioPath, ".golden")));
}

/// C#: Assert.Null(TraceComparer.Compare(expected, actual)).
Error<void> SameTrace(string[] expected, string[] actual)
{
	string difference = TraceComparer.Compare(expected, actual);

	return Assert.True(difference == null, "the traces differ: " + difference);
}

Error<void> ScenariosMatchTheirGoldenTraces(string[] arguments)
{
	string path = Path.Combine(ScenarioFolder(), arguments[0]);
	var result = try ScenarioRunner.Run(try Scenario.Load(path), false);

	try Assert.True(result.Failures.Count() == 0, "failures: " + JoinList("; ", result.Failures));
	try SameTrace(try GoldenLines(path), ArrayOf(result.Trace));

	return;
}

Error<void> RunsAreDeterministic()
{
	var scenario = try Scenario.Load(Path.Combine(ScenarioFolder(), "schrein.scenario"));

	return Assert.Strings(ArrayOf((try ScenarioRunner.Run(scenario, false)).Trace), (try ScenarioRunner.Run(scenario, false)).Trace);
}

Error<void> TheSeedDecidesRandomOutcomes()
{
	string text = try File.ReadAllText(Path.Combine(ScenarioFolder(), "schrein.scenario"));
	var traces = List<string>.Create();

	for (var seed = 1; seed <= 12; seed += 1)
	{
		var scenario = try Scenario.Parse(text.Replace("seed 12345", "seed " + seed), ScenarioFolder(), "scenario");
		var trace = (try ScenarioRunner.Run(scenario, false)).Trace;
		string last = trace.Get(trace.Count() - 1);

		if (!ContainsText(traces, last))
			traces.Add(last);
	}

	// chance(50) gives 5 or 1 gold: the state hash differs between the outcomes
	return Assert.True(traces.Count() >= 2, "at least two different outcomes");
}

Error<void> FailedExpectationsAreReportedAndTraced()
{
	var scenario = try Scenario.Parse("script schrein.ams\nload map spannenberg_keller\nat 0 expect gold 5\n", ScenarioFolder(), "test");
	var result = try ScenarioRunner.Run(scenario, false);

	try Assert.False(result.Passed());
	try Assert.AnyContains(result.Trace, "expect gold 5 FAILED (expected 5, actual 0)");

	return;
}

Error<void> AnAnswerWithoutAWaitingThreadIsAFailure()
{
	var scenario = try Scenario.Parse("script schrein.ams\nload map spannenberg_keller\nat 0 answer say\n", ScenarioFolder(), "test");

	return Assert.False((try ScenarioRunner.Run(scenario, false)).Passed());
}

Error<void> BrokenScenariosAreRejected(string[] arguments)
{
	string message = try Assert.Fails(Scenario.Parse(arguments[0], ScenarioFolder(), "test"), ErrorKind.Scenario);

	return Assert.Contains(arguments[1], message);
}

Error<void> ScenariosWhichCannotRunAreRejected(string[] arguments)
{
	var scenario = try Scenario.Parse(arguments[0], ScenarioFolder(), "test");
	string message = try Assert.Fails(ScenarioRunner.Run(scenario, false), ErrorKind.Scenario);

	return Assert.Contains(arguments[1], message);
}

Error<void> TheComparerFindsTheFirstDifference()
{
	try Assert.Null(TraceComparer.Compare(new string[] { "a", "b" }, new string[] { "a", "b" }));
	try Assert.Contains("line 2", TraceComparer.Compare(new string[] { "a", "b" }, new string[] { "a", "c" }));
	try Assert.Contains("end of trace", TraceComparer.Compare(new string[] { "a", "b" }, new string[] { "a" }));
	try Assert.Contains("end of trace", TraceComparer.Compare(new string[] { "a" }, new string[] { "a", "b" }));

	return;
}
