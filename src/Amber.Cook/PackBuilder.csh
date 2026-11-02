namespace Amber.Cook;

using System;
using Amber.Base;
using Amber.Pack;
using Amber.Runtime;
using Amber.Screens;
using Amber.Script.Common;
using Amber.Script.Compilation;

/// The cook: turns the result of the script compiler, the screen definitions and the tables of the game into a pack (spec
/// section 9). Chunks: SCRIPTS and BINDINGS (global), one MAP per map, one SCREEN per screen definition, NATIVES, LAYOUT,
/// SYMBOLS (optional), TEXT per language and TABLE chunks for the name tables and the tables of the game.
///
/// Create it with Create(result) and set the options (the fields in the first block) before Build().
struct PackBuilder
{
	/// The screen definitions (YAML); a screen with a script but no definition gets an empty definition.
	Optional<ScreenLibrary> Screens;
	/// Write the debug names of all symbols (SYMBOLS chunk).
	bool IncludeSymbols;
	uint16 ProfileId;
	/// Allow deflate for chunks (default). The Amiga profile leaves it out: the C runtime unpacks only none and RLE0.
	bool AllowDeflate;
	RuntimeLimits Limits;
	uint16 MaxScreenDepth;

	CompilationResult Result;
	List<string> Graphics;
	List<string> Cursors;
	Dictionary<string, NativeEntry> Natives;
	Dictionary<int, Dictionary<int, string>> Texts;
	Dictionary<int, Dictionary<int, string>> StringTables;
	/// Tables of the game in their own format (TABLE chunks, from PackTableFirstGameTable).
	Dictionary<int, uint8[]> RawTables;
	/// Things the cook skipped or could not check.
	List<string> Warnings;

	static PackBuilder Create(CompilationResult result)
	{
		return PackBuilder
		{
			Screens = null,
			IncludeSymbols = true,
			ProfileId = 0,
			AllowDeflate = true,
			Limits = RuntimeLimits.Default(),
			MaxScreenDepth = 8,
			Result = result,
			Graphics = List<string>.Create(),
			Cursors = List<string>.Create(),
			Natives = Dictionary<string, NativeEntry>.Create(),
			Texts = Dictionary<int, Dictionary<int, string>>.Create(),
			StringTables = Dictionary<int, Dictionary<int, string>>.Create(),
			RawTables = Dictionary<int, uint8[]>.Create(),
			Warnings = List<string>.Create()
		};
	}

	/// The texts of a language by text ID (TEXT chunk, spec section 11). Language 0 is the base language.
	void AddTexts(int language, Dictionary<int, string> strings)
	{
		Texts.Set(language, strings);
	}

	/// A string table of the game (TABLE chunk with the given ID, from PackTableFirstGameTable).
	Error<void> AddStringTable(int tableId, Dictionary<int, string> strings)
	{
		if (tableId < PackTableFirstGameTable)
			return error("The table IDs below " + PackTableFirstGameTable + " belong to the cook.", (int)ErrorKind.Argument);

		StringTables.Set(tableId, strings);

		return;
	}

	/// A table of the game in its own format (TABLE chunk with the given ID, from PackTableFirstGameTable).
	Error<void> AddTable(int tableId, uint8[] data)
	{
		if (tableId < PackTableFirstGameTable)
			return error("The table IDs below " + PackTableFirstGameTable + " belong to the cook.", (int)ErrorKind.Argument);

		if (StringTables.ContainsKey(tableId))
			return error("The table " + tableId + " is already a string table.", (int)ErrorKind.Argument);

		RawTables.Set(tableId, data);

		return;
	}

	Error<uint8[]> Build()
	{
		var writer = try CreateWriter();

		return writer.ToArray();
	}

	Error<void> Save(string path)
	{
		return File.WriteAllBytes(path, try Build());
	}

	Error<PackWriter> CreateWriter()
	{
		if (Result.HasErrors())
			return error("The scripts have errors, no pack can be cooked.", (int)ErrorKind.InvalidOperation);

		// the natives of the symbol table are functions; data sources are added while the screens are cooked
		var nativeSymbols = List<SymbolEntry>.Create();

		foreach (var pair in Result.Symbols.Ids.Entries())
		{
			if (pair.Key.Kind == SymbolKind.Native)
				nativeSymbols.Add(SymbolEntry { Kind = pair.Key.Kind, Name = pair.Key.Name, Id = pair.Value });
		}

		SortList(nativeSymbols, CompareSymbolById);

		foreach (var symbol in nativeSymbols)
			Natives.Set(symbol.Name, NativeEntry { Id = symbol.Id, Blocking = false, DataSource = false, ArgumentCount = 0, Name = symbol.Name });

		var global = Result.Global;
		var writer = PackWriter.Create();

		writer.ProfileId = ProfileId;
		writer.AllowDeflate = AllowDeflate && ProfileId != 1;
		writer.LayoutHash = Result.LayoutHash;
		writer.MaxThreads = (uint16)Limits.MaxThreads;
		writer.MaxChainSteps = (uint16)Limits.MaxChainSteps;
		writer.MaxPendingEvents = (uint16)Limits.MaxPendingEvents;
		writer.MaxScreenDepth = MaxScreenDepth;
		writer.GlobalFlags = (uint16)global.FlagCount.Get();
		writer.GlobalVars = (uint16)global.VarCount.Get();
		writer.GlobalVars32 = (uint16)global.Var32Count.Get();
		writer.Flags = IncludeSymbols ? PackHasSymbols : (uint16)0;

		try writer.AddBest(PackChunkType.Scripts, 0, global.GroupsChunk.Get());
		try writer.AddBest(PackChunkType.Bindings, 0, global.BindingsChunk.Get());

		foreach (var map in Result.Maps)
		{
			var entities = List<PackedEntity>.Create();

			foreach (var entity in map.EntityInfos)
				entities.Add(PackedEntity { Id = entity.Id, Name = entity.Name, X = entity.X, Y = entity.Y, Kind = (uint8)entity.Kind });

			var sizes = StateSizes.Of(map.FlagCount.Get(), map.VarCount.Get(), map.Var32Count.Get());

			try writer.AddBest(PackChunkType.Map, try Resolve(SymbolKind.Map, map.Name),
				PackedMap.Write(map.Name, sizes, entities, map.GroupsChunk.Get(), map.BindingsChunk.Get(), try RoutineBaker.Bake(map)));
		}

		// screens with a YAML definition, then the screens which only have a script (they get an empty definition)
		var definitions = List<ScreenDefinition>.Create();

		if (Screens is ScreenLibrary library)
		{
			foreach (var definition in library.Screens.Values())
				definitions.Add(definition);
		}

		foreach (var scope in Result.Screens)
		{
			bool defined = false;

			if (Screens is ScreenLibrary known)
			{
				if (known.Find(scope.Name) is ScreenDefinition found)
					defined = true;
			}

			if (!defined)
				definitions.Add(ScreenDefinition.Empty(scope.Name));
		}

		SortList(definitions, CompareScreenByName);

		foreach (var definition in definitions)
		{
			var scope = Result.FindScreen(definition.Name);
			var symbols = CookSymbols { Builder = this, Scope = scope };
			var chunk = try ScreenChunk.Write(definition, ref symbols);
			var sizes = StateSizes.Of(0, 0, 0);
			var groups = new uint8[0];
			var bindings = new uint8[0];

			if (scope is CompiledScope screenScope)
			{
				sizes = StateSizes.Of(screenScope.FlagCount.Get(), screenScope.VarCount.Get(), screenScope.Var32Count.Get());
				groups = screenScope.GroupsChunk.Get();
				bindings = screenScope.BindingsChunk.Get();
			}

			try writer.AddBest(PackChunkType.Screen, try Resolve(SymbolKind.Screen, definition.Name), PackedScreen.Write(chunk, sizes, groups, bindings));
		}

		var nativeList = Natives.Values();
		var sortedNatives = List<NativeEntry>.Create();

		sortedNatives.AddRange(SortArray(nativeList, CompareNativeById));
		writer.NativeCount = (uint16)sortedNatives.Count();
		try writer.AddBest(PackChunkType.Natives, 0, try NativeEntry.Write(sortedNatives));
		try writer.AddBest(PackChunkType.Layout, 0, Utf8Bytes(Result.LayoutText));

		if (IncludeSymbols)
		{
			var entries = List<SymbolEntry>.Create();

			foreach (var pair in Result.Symbols.Ids.Entries())
				entries.Add(SymbolEntry { Kind = pair.Key.Kind, Name = pair.Key.Name, Id = pair.Value });

			SortList(entries, CompareSymbolByKindThenId);

			var names = List<NamedId>.Create();

			foreach (var entry in entries)
				names.Add(NamedId { Kind = (uint8)entry.Kind, Id = entry.Id, Name = entry.Name });

			try writer.AddBest(PackChunkType.Symbols, 0, NamedId.Write(names));
		}

		foreach (var language in SortedKeys(Texts))
			try writer.AddBest(PackChunkType.Text, language, try StringTable.Write(Texts.GetOrDefault(language, Dictionary<int, string>.Create())));

		foreach (var tableId in SortedKeys(StringTables))
			try writer.AddBest(PackChunkType.Table, tableId, try StringTable.Write(StringTables.GetOrDefault(tableId, Dictionary<int, string>.Create())));

		foreach (var tableId in SortArray(RawTables.Keys(), CompareInt))
			try writer.AddBest(PackChunkType.Table, tableId, RawTables.GetOrDefault(tableId, new uint8[0]));

		try AddNameTable(writer, PackTableUiGraphics, Graphics);
		try AddNameTable(writer, PackTableCursors, Cursors);

		return writer;
	}

	static Error<void> AddNameTable(PackWriter writer, int tableId, List<string> names)
	{
		if (names.Count() > 0)
		{
			var entries = List<NamedId>.Create();

			for (var i = 0; i < names.Count(); i += 1)
				entries.Add(NamedId { Kind = 0, Id = (uint16)(i + 1), Name = names.Get(i) });

			try writer.AddBest(PackChunkType.Table, tableId, NamedId.Write(entries));
		}

		return;
	}

	Error<int> Resolve(SymbolKind kind, string name)
	{
		if (Result.Symbols.TryResolve(kind, name) is uint16 id)
			return (int)id;

		return error("The " + SymbolKinds.Prefix(kind) + "." + name + " has no ID in the tables.", (int)ErrorKind.InvalidData);
	}

	/// The ID of a native data source: an existing native of that name or a new entry behind the highest ID.
	int SourceId(string name)
	{
		if (Natives.TryGet(name) is NativeEntry existing)
			return (int)existing.Id;

		int id = 1;

		foreach (var native in Natives.Values())
			id = Math.Max(id, (int)native.Id + 1);

		Natives.Set(name, NativeEntry { Id = (uint16)id, Blocking = false, DataSource = true, ArgumentCount = 0, Name = name });

		return id;
	}
}

/// The IDs of a screen chunk from the tables of the cook (C#: the nested class CookSymbols).
struct CookSymbols : IScreenSymbols
{
	PackBuilder Builder;
	Optional<CompiledScope> Scope;

	Error<int> Screen(string name)
	{
		return Builder.Resolve(SymbolKind.Screen, name);
	}

	Error<int> Text(string name)
	{
		return Builder.Resolve(SymbolKind.Text, name);
	}

	Error<int> Graphic(string name)
	{
		return RegisterName(Builder.Graphics, name);
	}

	Error<int> Cursor(string name)
	{
		return RegisterName(Builder.Cursors, name);
	}

	Error<int> Source(string name)
	{
		return Builder.SourceId(name);
	}

	Error<int> Group(string screen, string group)
	{
		if (Scope is CompiledScope scope)
		{
			if (scope.GroupRefs.TryGet(group) is uint16 local)
				return (int)local;
		}

		if (Builder.Result.Global.GroupRefs.TryGet(group) is uint16 global)
			return (int)global;

		return error("Screen '" + screen + "': the handler group '" + group + "' does not exist.", (int)ErrorKind.InvalidData);
	}
}

/// The position of the name (plus one), added to the list if it is new.
int RegisterName(List<string> names, string name)
{
	int index = IndexOfText(names, name);

	if (index < 0)
	{
		names.Add(name);
		index = names.Count() - 1;
	}

	return index + 1;
}

/// A symbol of the symbol table (C#: KeyValuePair<(SymbolKind Kind, string Name), word>).
struct SymbolEntry
{
	SymbolKind Kind;
	string Name;
	uint16 Id;
}

int CompareSymbolById(SymbolEntry a, SymbolEntry b)
{
	return CompareInt((int)a.Id, (int)b.Id);
}

int CompareSymbolByKindThenId(SymbolEntry a, SymbolEntry b)
{
	if (a.Kind != b.Kind)
		return CompareInt((int)a.Kind, (int)b.Kind);

	return CompareInt((int)a.Id, (int)b.Id);
}

int CompareNativeById(NativeEntry a, NativeEntry b)
{
	return CompareInt((int)a.Id, (int)b.Id);
}

int CompareScreenByName(ScreenDefinition a, ScreenDefinition b)
{
	return CompareOrdinal(a.Name, b.Name);
}

/// The keys in ascending order (C#: SortedDictionary).
int[] SortedKeys(Dictionary<int, Dictionary<int, string>> map)
{
	return SortArray(ArrayOf(ListOfInts(map.Keys())), CompareInt);
}

List<int> ListOfInts(int[] values)
{
	var list = List<int>.Create();

	list.AddRange(values);

	return list;
}
