// amberc - the AmberScript compiler and the tools around it (compile, stats, pack, dump, trace, layout-diff, gen-c).

using System;
using Amber.Base;
using Amber.Conformance;
using Amber.Cook;
using Amber.Pack;
using Amber.Screens;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

const string Usage = "amberc - AmberScript compiler\n"
	+ "\n"
	+ "Usage:\n"
	+ "  amberc compile <file|directory>... [options]\n"
	+ "  amberc stats   <file|directory>... [options] [--top <n>] [--out <file>]\n"
	+ "  amberc pack    <file|directory>... --out <game.pack> [--screens <dir>] [--lenient] [--no-symbols]\n"
	+ "  amberc dump    <groups.bin> [<bindings.bin>] | <game.pack>\n"
	+ "  amberc trace   <scenario> [--out <file>] [--check <golden>] [--update <golden>] [--via-pack]\n"
	+ "  amberc layout-diff <old.layout> <new.layout>\n"
	+ "  amberc gen-c   <folder>          write amber_tables.h (constants and names for the C runtime)\n"
	+ "\n"
	+ "trace runs a golden trace scenario (spec section 12.3) and prints the trace. --check compares it with a golden file\n"
	+ "(exit code 1 if it differs), --update writes the golden file. Failed expectations of the scenario give exit code 1.\n"
	+ "\n"
	+ "Options:\n"
	+ "  --lenient        assign IDs to unknown table symbols instead of reporting E001\n"
	+ "  --screens <dir>  read screen arguments and node names from the YAML files in <dir>\n"
	+ "  --no-dedup       do not merge identical groups\n"
	+ "  --no-symbols     pack: leave the debug names (SYMBOLS chunk) out\n"
	+ "  --profile amiga  pack: profile 1 (no deflate, the C runtime reads only none and RLE0)\n"
	+ "  --via-pack       trace: cook the scripts into a pack and run the scenario from it\n"
	+ "  --out <dir>      compile: write the chunks (*.groups.bin, *.bindings.bin), layout.txt and symbols.txt\n"
	+ "  --dump           compile: print a readable dump of all chunks\n"
	+ "  --layout         compile: print the state layout";

int Main(string[] args)
{
	if (args.Length == 0 || args[0] == "-h" || args[0] == "--help")
	{
		Console.WriteLine(Usage);

		return 0;
	}

	var rest = new string[args.Length - 1];

	for (var i = 1; i < args.Length; i += 1)
		rest[i - 1] = args[i];

	switch (args[0])
	{
		case "compile":
			return Compile(rest);
		case "stats":
			return Statistics(rest);
		case "dump":
			return Dump(rest);
		case "pack":
			return PackCommand(rest);
		case "layout-diff":
			return LayoutDifference(rest);
		case "gen-c":
			return GenerateC(rest);
		case "trace":
			return Trace(rest);
		default:
			Console.WriteErrorLine("Unknown command '" + args[0] + "'.\n\n" + Usage);

			return 2;
	}
}

/// The options of a command.
struct CommandLine
{
	List<string> Inputs;
	string Screens;
	string Out;
	string Check;
	string Update;
	bool Lenient;
	bool NoDedup;
	bool NoSymbols;
	bool Amiga;
	bool ViaPack;
	bool Dump;
	bool Layout;
	int Top;

	static CommandLine Parse(string[] arguments)
	{
		var line = CommandLine { Inputs = List<string>.Create(), Top = 20 };

		for (var i = 0; i < arguments.Length; i += 1)
		{
			string argument = arguments[i];
			bool hasValue = i + 1 < arguments.Length;

			if (argument == "--lenient")
				line.Lenient = true;
			else if (argument == "--profile" && hasValue)
			{
				i += 1;
				line.Amiga = arguments[i] == "amiga";
			}
			else if (argument == "--no-symbols")
				line.NoSymbols = true;
			else if (argument == "--via-pack")
				line.ViaPack = true;
			else if (argument == "--no-dedup")
				line.NoDedup = true;
			else if (argument == "--dump")
				line.Dump = true;
			else if (argument == "--layout")
				line.Layout = true;
			else if (argument == "--screens" && hasValue)
			{
				i += 1;
				line.Screens = arguments[i];
			}
			else if (argument == "--out" && hasValue)
			{
				i += 1;
				line.Out = arguments[i];
			}
			else if (argument == "--check" && hasValue)
			{
				i += 1;
				line.Check = arguments[i];
			}
			else if (argument == "--update" && hasValue)
			{
				i += 1;
				line.Update = arguments[i];
			}
			else if (argument == "--top" && hasValue && TryParseInt(arguments[i + 1]) != null)
			{
				if (TryParseInt(arguments[i + 1]) is int top)
					line.Top = top;

				i += 1;
			}
			else
				line.Inputs.Add(argument);
		}

		return line;
	}
}

/// Compiles the inputs (files and directories with *.ams files) and prints the diagnostics. No value if the input is
/// missing or unreadable.
Optional<CompilationResult> Build(CommandLine line, bool deduplicate, Optional<ScreenLibrary> library)
{
	if (line.Inputs.Count() == 0)
	{
		Console.WriteErrorLine("No input files.");

		return null;
	}

	var files = List<SourceFile>.Create();

	foreach (var input in line.Inputs)
	{
		var paths = List<string>.Create();

		if (Directory.Exists(input))
			paths = Directory.FindFiles(input, ".ams");
		else
			paths.Add(input);

		foreach (var path in paths)
		{
			var text = File.ReadAllText(path);

			if (text is string source)
			{
				files.Add(SourceFile.Create(path, source));
			}
			else
			{
				Console.WriteErrorLine(path + ": " + text.Message);

				return null;
			}
		}
	}

	var options = CompileOptions { LenientSymbols = line.Lenient, NoDeduplicate = !deduplicate };

	if (library is ScreenLibrary given)
	{
		options.Screens = given.Signatures();
	}
	else if (line.Screens != null)
	{
		var loaded = ScreenLibrary.Load(line.Screens);

		if (loaded is ScreenLibrary screens)
		{
			options.Screens = screens.Signatures();
		}
		else
		{
			Console.WriteErrorLine(loaded.Message);

			return null;
		}
	}

	var result = ScriptCompiler.Compile(ArrayOf(files), options);

	foreach (var diagnostic in result.Diagnostics.Items)
		Console.WriteErrorLine(diagnostic.Text());

	Console.WriteErrorLine(result.Diagnostics.ErrorCount() + " error(s), " + result.Diagnostics.WarningCount() + " warning(s).");

	return result;
}

int Compile(string[] arguments)
{
	var line = CommandLine.Parse(arguments);

	if (Build(line, !line.NoDedup, null) is CompilationResult result)
	{
		if (result.HasErrors())
			return 1;

		foreach (var scope in result.AllScopes())
		{
			Console.WriteLine(ScopeKindName(scope.Kind) + " " + scope.Name + ": " + scope.Groups.Count() + " group(s), " + scope.Bindings.Count() + " binding(s), "
				+ scope.FlagCount.Get() + " flag(s), " + scope.VarCount.Get() + " var(s), " + scope.Var32Count.Get() + " var32(s), "
				+ (scope.GroupsChunk.Get().Length + scope.BindingsChunk.Get().Length) + " bytes");

			if (line.Dump)
			{
				Console.WriteLine("");

				if (ScriptDumper.Dump(scope.ToChunk()) is string text)
					Console.WriteLine(text);
			}

			if (line.Layout)
			{
				foreach (var entry in scope.Layout)
					Console.WriteLine("  " + StateNamespaceName(entry.Namespace) + "." + SlotKindName(entry.Kind) + "[" + entry.Index + "] = " + entry.Name);
			}
		}

		Console.WriteLine("Merged " + result.DuplicateGroupsRemoved + " duplicate group(s). Layout hash 0x" + Hex(result.LayoutHash, 8) + ".");

		if (line.Out != null)
		{
			var written = WriteOutput(result, line.Out);

			if (written is error)
			{
				Console.WriteErrorLine(written.Message);

				return 1;
			}
		}

		return 0;
	}

	return 2;
}

int Statistics(string[] arguments)
{
	var line = CommandLine.Parse(arguments);

	if (Build(line, false, null) is CompilationResult result)
	{
		if (result.HasErrors())
			return 1;

		string text = PatternStatistics.Create(result, line.Top);

		if (line.Out != null)
			File.WriteAllText(line.Out, text);
		else
			Console.WriteLine(text);

		return 0;
	}

	return 2;
}

Error<void> WriteOutput(CompilationResult result, string directory)
{
	Directory.Create(directory);

	foreach (var scope in result.AllScopes())
	{
		string name = scope.Kind == ScopeKind.Global ? "global" : ScopeKindName(scope.Kind).ToLower() + "." + scope.Name;

		try File.WriteAllBytes(Path.Combine(directory, name + ".groups.bin"), scope.GroupsChunk.Get());
		try File.WriteAllBytes(Path.Combine(directory, name + ".bindings.bin"), scope.BindingsChunk.Get());
	}

	try File.WriteAllText(Path.Combine(directory, "layout.txt"), "# layout hash 0x" + Hex(result.LayoutHash, 8) + "\n" + result.LayoutText + "\n");

	var symbols = List<SymbolEntry>.Create();

	foreach (var pair in result.Symbols.Ids.Entries())
		symbols.Add(SymbolEntry { Kind = pair.Key.Kind, Name = pair.Key.Name, Id = pair.Value });

	SortList(symbols, CompareSymbolByKindThenId);

	var lines = StringBuilder.Create();

	foreach (var symbol in symbols)
		lines.Append(SymbolKinds.Prefix(symbol.Kind) + "." + symbol.Name + " = " + symbol.Id + "\n");

	return File.WriteAllText(Path.Combine(directory, "symbols.txt"), lines.ToString());
}

int Trace(string[] arguments)
{
	var line = CommandLine.Parse(arguments);

	if (line.Inputs.Count() != 1)
	{
		Console.WriteErrorLine("amberc trace needs exactly one scenario file.");

		return 2;
	}

	var loaded = Scenario.Load(line.Inputs.Get(0));

	if (loaded is error)
	{
		Console.WriteErrorLine(loaded.Message);

		return 2;
	}

	var scenario = new Scenario();

	if (loaded is Scenario parsed)
		scenario = parsed;

	var run = ScenarioRunner.Run(scenario, line.ViaPack);

	if (run is error)
	{
		Console.WriteErrorLine(run.Message);

		return 2;
	}

	var result = new ScenarioResult();

	if (run is ScenarioResult finished)
		result = finished;

	if (line.Out != null)
		File.WriteAllText(line.Out, result.TraceText());
	else if (line.Update == null)
		Console.Write(result.TraceText());

	foreach (var failure in result.Failures)
		Console.WriteErrorLine("failed: " + failure);

	if (line.Update != null)
	{
		File.WriteAllText(line.Update, result.TraceText());
		Console.WriteErrorLine("golden trace written: " + line.Update);
	}

	if (line.Check != null)
	{
		var golden = File.ReadAllText(line.Check);

		if (golden is string text)
		{
			string difference = TraceComparer.Compare(TraceComparer.Lines(text), ArrayOf(result.Trace));

			if (difference != null)
			{
				Console.WriteErrorLine("the trace differs from " + line.Check + ": " + difference);

				return 1;
			}

			Console.WriteErrorLine("the trace matches " + line.Check + " (" + result.Trace.Count() + " lines).");
		}
		else
		{
			Console.WriteErrorLine(golden.Message);

			return 2;
		}
	}

	return result.Passed() ? 0 : 1;
}

int GenerateC(string[] arguments)
{
	if (arguments.Length != 1)
	{
		Console.WriteErrorLine("amberc gen-c needs the folder for amber_tables.h (c/include).");

		return 2;
	}

	Directory.Create(arguments[0]);

	var written = File.WriteAllText(Path.Combine(arguments[0], "amber_tables.h"), CTables.Generate());

	if (written is error)
	{
		Console.WriteErrorLine(written.Message);

		return 1;
	}

	return 0;
}

int LayoutDifference(string[] arguments)
{
	if (arguments.Length != 2)
	{
		Console.WriteErrorLine("amberc layout-diff needs the old and the new layout file.");

		return 2;
	}

	var result = CompareLayouts(arguments[0], arguments[1]);

	if (result is LayoutDiff diff)
	{
		Console.WriteLine(diff.IsEmpty() ? "The layouts are identical." : diff.ToText());

		return 0;
	}

	Console.WriteErrorLine(result.Message);

	return 1;
}

Error<LayoutDiff> CompareLayouts(string oldPath, string newPath)
{
	var oldLayout = try LayoutTable.Parse(try File.ReadAllText(oldPath));
	var newLayout = try LayoutTable.Parse(try File.ReadAllText(newPath));

	return LayoutDiff.Compare(oldLayout, newLayout);
}

int PackCommand(string[] arguments)
{
	var line = CommandLine.Parse(arguments);

	if (line.Out == null)
	{
		Console.WriteErrorLine("amberc pack needs --out <file>.");

		return 2;
	}

	Optional<ScreenLibrary> library = null;

	if (line.Screens != null)
	{
		var loaded = ScreenLibrary.Load(line.Screens);

		if (loaded is ScreenLibrary screens)
		{
			library = screens;
		}
		else
		{
			Console.WriteErrorLine(loaded.Message);

			return 1;
		}
	}

	if (Build(line, !line.NoDedup, library) is CompilationResult result)
	{
		if (result.HasErrors())
			return 1;

		var builder = PackBuilder.Create(result);

		builder.Screens = library;
		builder.IncludeSymbols = !line.NoSymbols;
		builder.ProfileId = line.Amiga ? (uint16)1 : (uint16)0;

		var built = builder.Build();

		if (built is uint8[] data)
		{
			var written = File.WriteAllBytes(line.Out, data);

			if (written is error)
			{
				Console.WriteErrorLine(written.Message);

				return 1;
			}

			foreach (var warning in builder.Warnings)
				Console.WriteErrorLine("warning: " + warning);

			if (PackReader.FromMemory(data) is PackReader reader)
			{
				Console.WriteLine(line.Out + ": " + data.Length + " bytes, " + reader.Header.TocCount + " chunks, " + reader.Header.NativeCount + " natives, layout hash 0x"
					+ Hex(reader.Header.LayoutHash, 8));
			}

			return 0;
		}

		Console.WriteErrorLine(built.Message);

		return 1;
	}

	return 2;
}

int Dump(string[] arguments)
{
	if (arguments.Length == 0)
	{
		Console.WriteErrorLine("No chunk file given.");

		return 2;
	}

	var read = File.ReadAllBytes(arguments[0]);

	if (read is error)
	{
		Console.WriteErrorLine(arguments[0] + ": " + read.Message);

		return 2;
	}

	var groups = new uint8[0];

	if (read is uint8[] bytes)
		groups = bytes;

	if (StartsWithAscii(groups, PackMagic))
	{
		var pack = PackReader.FromMemory(groups);

		if (pack is PackReader reader)
		{
			Console.WriteLine(PackDumper.Dump(reader));

			return 0;
		}

		Console.WriteErrorLine(arguments[0] + ": " + pack.Message);

		return 1;
	}

	var bindings = new uint8[0];

	if (arguments.Length > 1)
	{
		if (File.ReadAllBytes(arguments[1]) is uint8[] second)
			bindings = second;
	}

	var chunk = ScriptChunk.Create(groups, bindings);

	if (chunk is ScriptChunk script)
	{
		var dumped = ScriptDumper.Dump(script);

		if (dumped is string text)
		{
			Console.WriteLine(text);

			return 0;
		}

		Console.WriteErrorLine(dumped.Message);

		return 1;
	}

	Console.WriteErrorLine(chunk.Message);

	return 1;
}
