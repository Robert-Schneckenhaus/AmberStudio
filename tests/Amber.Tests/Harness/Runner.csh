// The test runner (the xUnit runner): every test file adds its tests to a list, Main runs them and prints the failures.
//
//     amber-tests                 runs every test
//     amber-tests Pack Save       runs the tests whose names contain one of the words
//     amber-tests --list          prints the names
//     amber-tests --verbose       prints every name before the test runs (a panic then names its test)
//     amber-tests --root <dir>    the repository root (default: found from the current folder upwards)

namespace Amber.Tests;

using System;
using Amber.Base;

/// One test: a fact (Run) or one row of a theory (RunWith with its arguments). A test returns an error at the first failed
/// check, like the exception which ends an xUnit test.
struct TestCase
{
	string Name;
	bool IsTheory;
	Func<Error<void>> Run;
	Func<string[], Error<void>> RunWith;
	string[] Arguments;
}

/// The tests; the files add theirs in Register* functions.
struct TestList
{
	List<TestCase> Items;

	static TestList Create()
	{
		return TestList { Items = List<TestCase>.Create() };
	}

	void Fact(string name, Func<Error<void>> run)
	{
		Items.Add(TestCase { Name = name, IsTheory = false, Run = run, RunWith = NoTheory, Arguments = new string[0] });
	}

	/// One row of a theory; the name gets the arguments like the xUnit display name.
	void Theory(string name, Func<string[], Error<void>> run, string[] arguments)
	{
		var shown = List<string>.Create();

		foreach (var argument in arguments)
			shown.Add("\"" + argument.Replace("\n", "\\n") + "\"");

		Items.Add(TestCase { Name = name + "(" + JoinList(", ", shown) + ")", IsTheory = true, Run = NoFact, RunWith = run, Arguments = arguments });
	}

	void Theory(string name, Func<string[], Error<void>> run, string argument)
	{
		Theory(name, run, new string[] { argument });
	}

	void Theory(string name, Func<string[], Error<void>> run, string first, string second)
	{
		Theory(name, run, new string[] { first, second });
	}
}

Error<void> NoFact()
{
	return error("not a fact", -1);
}

Error<void> NoTheory(string[] arguments)
{
	return error("not a theory", -1);
}

/// The repository root: examples, spec, game/content, c and tools are read from there.
string RepositoryRoot = "";

string Root()
{
	return RepositoryRoot;
}

/// A path below the repository root.
string RootPath(string relative)
{
	return Path.Combine(RepositoryRoot, relative);
}

/// A file of the examples folder (C#: TestPaths.Example).
string Example(string folder, string file)
{
	return Path.Combine(Path.Combine(Path.Combine(RepositoryRoot, "examples"), folder), file);
}

/// The text of a file below the repository root.
Error<string> ReadRootText(string relative)
{
	return File.ReadAllText(RootPath(relative));
}

/// Every *.ams file of the examples, relative to the root with '/' (C#: TestPaths.AmsFiles).
List<string> AmsFiles()
{
	return RelativeFiles("examples", ".ams");
}

/// The files with the extension below a folder of the root (recursive), relative to the root with '/'.
List<string> RelativeFiles(string folder, string extension)
{
	var result = List<string>.Create();

	if (!Directory.Exists(RootPath(folder)))
		return result;

	foreach (var file in Directory.FindFiles(RootPath(folder), extension))
	{
		string normalized = Path.Normalize(file);
		string prefix = Path.Normalize(RepositoryRoot) + "/";

		result.Add(normalized.StartsWith(prefix) ? normalized.Substring(prefix.Length) : normalized);
	}

	return result;
}

/// The file names (without folder) of the files with the extension directly in a folder of the root.
List<string> FileNames(string folder, string extension)
{
	var result = List<string>.Create();

	foreach (var file in RelativeFiles(folder, extension))
	{
		if (Path.GetDirectory(file) == folder)
			result.Add(Path.GetFileName(file));
	}

	return result;
}

int TempCounter = 0;

/// A new empty folder for a test (C#: a folder in Path.GetTempPath() with a GUID); DeleteFolder removes it.
string NewTempFolder(string name)
{
	string parent = RootPath("tests/Amber.Tests/obj/tmp");

	TempCounter += 1;

	string folder = parent + "/" + name + "-" + TempCounter;

	DeleteFolder(folder);
	Directory.Create(folder);

	return folder;
}

void DeleteFolder(string folder)
{
	if (!Directory.Exists(folder))
		return;

	if (Process.IsWindows())
		Process.Run("rmdir /s /q \"" + Path.ToNative(folder) + "\"");
	else
		Process.Run("rm -rf \"" + folder + "\"");
}

/// Looks for the repository root from the current folder upwards (the folder with spec/schemas/screen.schema.json).
Optional<string> FindRoot()
{
	string candidate = ".";

	for (var i = 0; i < 8; i += 1)
	{
		if (File.Exists(candidate + "/spec/schemas/screen.schema.json") && Directory.Exists(candidate + "/examples"))
			return candidate;

		candidate = candidate == "." ? ".." : candidate + "/..";
	}

	return null;
}

int RunTests(string[] args)
{
	var filters = List<string>.Create();
	bool list = false;
	bool verbose = false;
	string root = null;

	for (var i = 0; i < args.Length; i += 1)
	{
		if (args[i] == "--list")
			list = true;
		else if (args[i] == "--verbose")
			verbose = true;
		else if (args[i] == "--root" && i + 1 < args.Length)
		{
			root = args[i + 1];
			i += 1;
		}
		else
			filters.Add(args[i]);
	}

	if (root == null)
	{
		if (FindRoot() is string found)
			root = found;
		else
		{
			Console.WriteErrorLine("Could not find the repository root; start the tests in the repository or pass --root <dir>.");

			return 2;
		}
	}

	RepositoryRoot = root;

	var tests = AllTests();
	int passed = 0;
	int failed = 0;
	var failures = List<string>.Create();

	foreach (var test in tests.Items)
	{
		if (!Selected(test.Name, filters))
			continue;

		if (list)
		{
			Console.WriteLine(test.Name);
			continue;
		}

		if (verbose)
			Console.WriteLine("  " + test.Name);

		Assert.CheckNumber = 0;

		Error<void> result = test.IsTheory ? test.RunWith(test.Arguments) : test.Run();

		if (result is not error)
			passed += 1;
		else
		{
			failed += 1;
			failures.Add(test.Name);
			Console.WriteLine("FAIL " + test.Name + ": " + result.Message);
		}
	}

	DeleteFolder(RootPath("tests/Amber.Tests/obj/tmp"));

	if (list)
		return 0;

	Console.WriteLine("");
	Console.WriteLine(failed == 0 ? "Passed: " + passed + " tests." : "Failed: " + failed + " of " + (passed + failed) + " tests.");

	return failed == 0 ? 0 : 1;
}

bool Selected(string name, List<string> filters)
{
	if (filters.Count() == 0)
		return true;

	foreach (var filter in filters)
	{
		if (name.Contains(filter))
			return true;
	}

	return false;
}
