namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Conformance;
using Amber.Cook;

// The C runtime (folder c/, task 6.2 to 6.5): the header generated from the opcode tables is up to date, and the C
// interpreter gives the same traces as the CShift interpreter for every golden trace scenario, from a pack of the Amiga
// profile. The tests which run the C code need a C compiler (clang or gcc: environment variable AMBER_CC or the PATH);
// without one they do nothing.

void RegisterCRuntimeTests(ref TestList tests)
{
	tests.Fact("CRuntime.TheGeneratedHeaderIsUpToDate", TheGeneratedHeaderIsUpToDate);

	foreach (var file in ScenarioFiles())
		tests.Theory("CRuntime.TheCRuntimeGivesTheGoldenTrace", TheCRuntimeGivesTheGoldenTrace, file);

	tests.Fact("CRuntime.ADamagedPackIsRefused", ADamagedPackIsRefused);
	tests.Fact("CRuntime.AFailedExpectationGivesExitCodeOne", AFailedExpectationGivesExitCodeOne);
}

/// The C runner, built on first use: "" before, null if there is no C compiler.
string CRunnerPath = "";

string CFolder()
{
	return RootPath("c");
}

Error<void> TheGeneratedHeaderIsUpToDate()
{
	string current = (try File.ReadAllText(Path.Combine(CFolder(), "include/amber_tables.h"))).Replace("\r\n", "\n");

	return Assert.True(CTables.Generate().Replace("\r\n", "\n") == current, "c/include/amber_tables.h is not up to date (amberc gen-c c)");
}

/// The result of a program run: exit code, stdout and stderr.
struct ProgramRun
{
	int ExitCode;
	string Output;
	string Error;
}

Error<void> TheCRuntimeGivesTheGoldenTrace(string[] arguments)
{
	string exe = try CRunner();

	if (exe == null)
		return;

	var run = try RunCScenario(exe, arguments[0], Unchanged);

	try Assert.Equal(0, run.ExitCode);
	try SameTrace(try GoldenLines(Path.Combine(ScenarioFolder(), arguments[0])), TraceComparer.Lines(run.Output));

	return;
}

uint8[] Unchanged(uint8[] pack)
{
	return pack;
}

/// A flipped byte in a chunk: the checksum fails.
uint8[] FlipAByte(uint8[] pack)
{
	var copy = Slice(pack, 0, pack.Length);

	copy[41] = (uint8)((int)copy[41] ^ 0xFF);

	return copy;
}

uint8[] Truncate(uint8[] pack)
{
	return Slice(pack, 0, pack.Length - 30);
}

Error<void> ADamagedPackIsRefused()
{
	string exe = try CRunner();

	if (exe == null)
		return;

	var damaged = try RunCScenario(exe, "schrein.scenario", FlipAByte);

	try Assert.Equal(2, damaged.ExitCode);
	try Assert.Contains("damaged", damaged.Error);

	var truncated = try RunCScenario(exe, "schrein.scenario", Truncate);

	try Assert.Equal(2, truncated.ExitCode);
	try Assert.Contains("not a valid pack", truncated.Error);

	return;
}

Error<void> AFailedExpectationGivesExitCodeOne()
{
	string exe = try CRunner();

	if (exe == null)
		return;

	string folder = NewTempFolder("c");
	string scenarioPath = Path.Combine(ScenarioFolder(), "schrein.scenario");
	string text = (try File.ReadAllText(scenarioPath)).Replace("script schrein.ams", "pack schrein.pack") + "at 66 expect gold 1\n";

	try File.WriteAllBytes(Path.Combine(folder, "schrein.pack"), try CookAmiga(scenarioPath));
	try File.WriteAllText(Path.Combine(folder, "test.scenario"), text);

	var run = try RunProgram(exe, Path.Combine(folder, "test.scenario"));

	try Assert.Equal(1, run.ExitCode);
	try Assert.Contains("FAILED (expected 1, actual 101)", run.Output);
	try Assert.Contains("failed:", run.Error);

	return;
}

/// Cooks the scripts of the scenario into a pack of the Amiga profile (no deflate), lets the caller change the bytes, and
/// runs the scenario against it with the C runner.
Error<ProgramRun> RunCScenario(string exe, string file, Func<uint8[], uint8[]> change)
{
	string folder = NewTempFolder("c");
	string scenarioPath = Path.Combine(ScenarioFolder(), file);
	string text = try File.ReadAllText(scenarioPath);
	string script = null;

	foreach (var line in text.Split("\n"))
	{
		string trimmed = line.Trim().ToString();

		if (script == null && trimmed.StartsWith("script "))
			script = trimmed.Substring("script ".Length).Trim().ToString();
	}

	if (script == null)
		return error("the scenario " + file + " has no script line", -1);

	try File.WriteAllBytes(Path.Combine(folder, "game.pack"), change(try CookAmiga(scenarioPath)));
	try File.WriteAllText(Path.Combine(folder, "test.scenario"), text.Replace("script " + script, "pack game.pack"));

	return RunProgram(exe, Path.Combine(folder, "test.scenario"));
}

Error<uint8[]> CookAmiga(string scenarioPath)
{
	var builder = PackBuilder.Create(try ScenarioProgram.Compile(try Scenario.Load(scenarioPath)));

	builder.ProfileId = 1;

	return builder.Build();
}

/// Runs the program with one argument; stdout and stderr go through files next to the argument.
Error<ProgramRun> RunProgram(string exe, string argument)
{
	string output = argument + ".out";
	string errors = argument + ".err";
	int exitCode = Process.Run(Quote(exe) + " " + Quote(argument) + " > " + Quote(output) + " 2> " + Quote(errors));

	return ProgramRun { ExitCode = exitCode, Output = try File.ReadAllText(output), Error = try File.ReadAllText(errors) };
}

string Quote(string path)
{
	return "\"" + Path.ToNative(path) + "\"";
}

/// Compiles the C runtime and the scenario runner (strict warnings, warnings are errors) once. Returns the executable or
/// null if there is no C compiler.
Error<string> CRunner()
{
	if (CRunnerPath == null || CRunnerPath.Length > 0)
		return CRunnerPath;

	string compiler = FindCCompiler();

	if (compiler == null)
	{
		Console.WriteLine("No C compiler found (AMBER_CC, PATH): the C runtime tests are skipped.");
		CRunnerPath = null;

		return CRunnerPath;
	}

	string folder = NewTempFolder("c-runner");
	string exe = Path.Combine(folder, Process.IsWindows() ? "amber_trace.exe" : "amber_trace");
	string c = CFolder();
	string log = Path.Combine(folder, "build.log");
	string command = compiler + " -std=c99 -Wall -Wextra -pedantic -Werror -I" + Quote(Path.Combine(c, "include"))
		+ " " + Quote(Path.Combine(c, "src/amber_pack.c")) + " " + Quote(Path.Combine(c, "src/amber_rt.c"))
		+ " " + Quote(Path.Combine(c, "tools/amber_trace.c")) + " -o " + Quote(exe) + " > " + Quote(log) + " 2>&1";

	if (Process.Run(command) != 0)
	{
		string text = File.ReadAllText(log) is string written ? written : "";

		return error("The C runtime does not compile:\n" + text, -1);
	}

	CRunnerPath = exe;

	return CRunnerPath;
}

/// AMBER_CC, or clang, gcc or cc from the PATH; null if there is none.
string FindCCompiler()
{
	if (Process.GetEnv("AMBER_CC") is string given)
	{
		if (given.Length > 0)
			return given;
	}

	string silent = Process.IsWindows() ? " > nul 2>&1" : " > /dev/null 2>&1";

	foreach (var name in new string[] { "clang", "gcc", "cc" })
	{
		if (Process.Run(name + " --version" + silent) == 0)
			return name;
	}

	return null;
}
