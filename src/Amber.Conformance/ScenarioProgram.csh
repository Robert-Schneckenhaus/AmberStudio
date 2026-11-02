namespace Amber.Conformance;

using System;
using Amber.Base;
using Amber.Cook;
using Amber.Pack;
using Amber.Runtime;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

/// A map of the program under test.
struct ScenarioMap
{
	int Id;
	string Name;
	StateSizes Sizes;
	ScriptChunk Script;
	Dictionary<string, int> Entities;
}

/// A screen of the program under test (the script part: its state and its groups and bindings).
struct ScenarioScreen
{
	int Id;
	string Name;
	StateSizes Sizes;
	ScriptChunk Script;
}

/// What a scenario runs against: the global scripts, the maps, the state layout and the symbol IDs. It comes either from
/// the compiler directly or from a pack, and both have to give the same trace.
struct ScenarioProgram
{
	ScriptChunk Global;
	StateSizes GlobalSizes;
	RuntimeLimits Limits;
	ScenarioMap[] Maps;
	ScenarioScreen[] Screens;
	LayoutTable Layout;
	/// The symbols (C#: the function Symbol): of the compiler (lenient: an unknown name gets the next ID) or of the pack.
	bool _fromCompiler;
	SymbolTable _table;
	Dictionary<SymbolKey, int> _packSymbols;

	/// The ID of a table symbol, or no value.
	Optional<int> Symbol(SymbolKind kind, string name)
	{
		if (_fromCompiler)
		{
			if (_table.TryResolve(kind, name) is uint16 id)
				return (int)id;

			return null;
		}

		return _packSymbols.TryGet(SymbolKey { Kind = kind, Name = name });
	}

	Optional<ScenarioMap> FindMap(string name)
	{
		foreach (var map in Maps)
		{
			if (map.Name == name)
				return map;
		}

		return null;
	}

	Optional<ScenarioScreen> FindScreen(string name)
	{
		foreach (var screen in Screens)
		{
			if (screen.Name == name)
				return screen;
		}

		return null;
	}

	/// Compiles the scripts of a scenario (lenient symbols: the IDs are assigned in order of use).
	static Error<CompilationResult> Compile(Scenario scenario)
	{
		var files = List<SourceFile>.Create();

		foreach (var path in scenario.Scripts)
		{
			if (Directory.Exists(path))
			{
				foreach (var file in Directory.FindFiles(path, ".ams"))
					files.Add(SourceFile.Create(file, try ReadScenarioText(file)));
			}
			else
			{
				files.Add(SourceFile.Create(path, try ReadScenarioText(path)));
			}
		}

		var compilation = ScriptCompiler.Compile(ArrayOf(files), CompileOptions { LenientSymbols = true });

		if (compilation.HasErrors())
		{
			var errors = List<string>.Create();

			foreach (var item in compilation.Diagnostics.Items)
			{
				if (item.Severity == Severity.Error)
					errors.Add(item.Text());
			}

			return error(scenario.Name + ": the scripts have errors:\n" + JoinList("\n", errors), (int)ErrorKind.Scenario);
		}

		return compilation;
	}

	static Error<ScenarioProgram> FromCompilation(CompilationResult compilation)
	{
		var global = compilation.Global;
		var maps = List<ScenarioMap>.Create();

		foreach (var map in compilation.Maps)
		{
			var id = compilation.Symbols.TryResolve(SymbolKind.Map, map.Name);

			if (id == null)
				return error("The map '" + map.Name + "' has no ID.", (int)ErrorKind.Scenario);

			int mapId = 0;

			if (id is uint16 value)
				mapId = (int)value;

			maps.Add(ScenarioMap { Id = mapId, Name = map.Name, Sizes = StateSizes.Of(map.FlagCount.Get(), map.VarCount.Get(), map.Var32Count.Get()), Script = map.ToChunk(), Entities = map.Entities });
		}

		var screens = List<ScenarioScreen>.Create();

		foreach (var screen in compilation.Screens)
		{
			var id = compilation.Symbols.TryResolve(SymbolKind.Screen, screen.Name);

			if (id == null)
				return error("The screen '" + screen.Name + "' has no ID.", (int)ErrorKind.Scenario);

			int screenId = 0;

			if (id is uint16 value)
				screenId = (int)value;

			screens.Add(ScenarioScreen { Id = screenId, Name = screen.Name, Sizes = StateSizes.Of(screen.FlagCount.Get(), screen.VarCount.Get(), screen.Var32Count.Get()), Script = screen.ToChunk() });
		}

		return ScenarioProgram
		{
			Global = global.ToChunk(),
			GlobalSizes = StateSizes.Of(global.FlagCount.Get(), global.VarCount.Get(), global.Var32Count.Get()),
			Limits = RuntimeLimits.Default(),
			Maps = ArrayOf(maps),
			Screens = ArrayOf(screens),
			Layout = try LayoutTable.Parse(compilation.LayoutText),
			_fromCompiler = true,
			_table = compilation.Symbols,
			_packSymbols = Dictionary<SymbolKey, int>.Create()
		};
	}

	/// Cooks the compiled scripts into a pack (in memory) and loads them from it, like a game would.
	static Error<ScenarioProgram> ViaPack(CompilationResult compilation)
	{
		var pack = try PackBuilder.Create(compilation).Build();

		return FromPack(PackContent.Of(try PackReader.FromMemory(pack)));
	}

	static Error<ScenarioProgram> FromPack(PackContent pack)
	{
		var maps = List<ScenarioMap>.Create();

		foreach (var id in pack.MapIds())
		{
			var map = try pack.LoadMap(id);

			maps.Add(ScenarioMap { Id = map.Id, Name = map.Name, Sizes = map.Sizes, Script = map.Script, Entities = map.EntityIds() });
		}

		var symbols = Dictionary<SymbolKey, int>.Create();
		var screenNames = Dictionary<int, string>.Create();

		foreach (var symbol in try pack.Symbols())
		{
			symbols.Set(SymbolKey { Kind = (SymbolKind)symbol.Kind, Name = symbol.Name }, (int)symbol.Id);

			if ((SymbolKind)symbol.Kind == SymbolKind.Screen)
				screenNames.Set((int)symbol.Id, symbol.Name);
		}

		var screens = List<ScenarioScreen>.Create();

		foreach (var id in pack.ScreenIds())
		{
			var screen = try pack.LoadScreen(id);

			screens.Add(ScenarioScreen { Id = screen.Id, Name = screenNames.GetOrDefault(screen.Id, "#" + screen.Id), Sizes = screen.Sizes, Script = screen.Script });
		}

		return ScenarioProgram
		{
			Global = try pack.GlobalScript(),
			GlobalSizes = pack.GlobalSizes(),
			Limits = pack.Limits(),
			Maps = ArrayOf(maps),
			Screens = ArrayOf(screens),
			Layout = try pack.Layout(),
			_fromCompiler = false,
			_table = SymbolTable.Create(false),
			_packSymbols = symbols
		};
	}
}
