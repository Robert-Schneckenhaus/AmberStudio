// Runs a scenario against the interpreter with a scripted host and produces the trace of spec section 12.3. The host is
// deterministic: the party has gold, items and words, blocking actions wait for an "answer" step, and the clock runs with
// the ticks (game start 09:00, 6000 ticks per hour).

namespace Amber.Conformance.ScenarioRunner;

using System;
using Amber.Base;
using Amber.Pack;
using Amber.Runtime;

/// Runs the scenario against the scripts of the scenario file (compiled in memory) or the pack it names. With 'viaPack' the
/// compiled scripts are cooked into a pack and loaded from it first. Errors of the scenario are Scenario errors.
Error<ScenarioResult> Run(Scenario scenario, bool viaPack)
{
	if (scenario.PackPath != null)
		return RunProgram(scenario, try ScenarioProgram.FromPack(PackContent.Of(try PackReader.FromFile(scenario.PackPath))));

	var compilation = try ScenarioProgram.Compile(scenario);

	if (viaPack)
		return RunProgram(scenario, try ScenarioProgram.ViaPack(compilation));

	return RunProgram(scenario, try ScenarioProgram.FromCompilation(compilation));
}

Error<ScenarioResult> RunProgram(Scenario scenario, ScenarioProgram program)
{
	var trace = List<string>.Create();
	var host = ScenarioHost.Create();
	var interpreter = Interpreter.CreateTraced(program.Global, program.GlobalSizes, program.Limits, trace);
	Optional<ScenarioMap> map = null;

	if (scenario.MapName != null)
	{
		map = program.FindMap(scenario.MapName);

		if (map == null)
			return error(scenario.Name + ": the map '" + scenario.MapName + "' does not exist.", (int)ErrorKind.Scenario);
	}

	host.SetInterpreter(interpreter);
	interpreter.SetRandomState(scenario.Seed);

	if (map is ScenarioMap loaded)
	{
		host.MapId.Set(loaded.Id);
		interpreter.LoadMap(loaded.Id, loaded.Script, loaded.Sizes);
	}

	var run = ScenarioSession
	{
		Scenario = scenario,
		Program = program,
		Map = map,
		Interpreter = interpreter,
		Host = host,
		Trace = trace,
		OpenScreens = Dictionary<string, LoadedChunk>.Create(),
		Failures = List<string>.Create()
	};
	int next = 0;

	for (var tick = 0; tick <= scenario.EndTick; tick += 1)
	{
		while (next < scenario.Steps.Length && scenario.Steps[next].Tick == tick)
		{
			try run.Execute(scenario.Steps[next]);
			next += 1;
		}

		interpreter.Tick(ref host);
	}

	run.Hash();

	return ScenarioResult { Trace = trace, Failures = run.Failures };
}
