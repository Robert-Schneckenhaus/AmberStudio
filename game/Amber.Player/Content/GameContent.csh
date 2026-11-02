namespace Amber.Player.Content;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Pack;
using Amber.Runtime;
using Amber.Screens;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

/// A screen with a screen block in the scripts: its chunk and state sizes from the pack and its groups by name.
struct ScreenScript
{
	ScriptChunk Chunk;
	StateSizes Sizes;
	Dictionary<string, uint16> GroupRefs;
}

/// Everything the game runs from, read from the pack (PackCook writes it from the content folder): the scripts of the
/// global scope, the maps and the screens, the layout, the symbol names and the tables of the game (texts, items,
/// keywords, deltas, chests, monster groups ...). Nothing is compiled or read from the content folder. Copies share the
/// tables.
struct GameContent
{
	ScriptChunk GlobalScript;
	StateSizes GlobalSizes;
	RuntimeLimits Limits;
	uint32 LayoutHash;
	LayoutTable Layout;
	/// The maps in the order of their IDs.
	List<PackedMap> Maps;
	/// The groups of the global scope by name (handlers of screens can name them).
	Dictionary<string, uint16> GlobalGroups;
	/// The screens with a screen block, by name.
	Dictionary<string, ScreenScript> ScreenScripts;
	/// The names of the symbols (SYMBOLS chunk), for savegames that store names instead of IDs.
	SymbolTable Symbols;
	Dictionary<int, TextInfo> Texts;
	Dictionary<int, ItemInfo> Items;
	Dictionary<int, string> Keywords;
	Dictionary<int, DeltaInfo> Deltas;
	/// The initial content of the chests (symbol CH.name).
	Dictionary<int, ChestInfo> Chests;
	/// The monster groups of the battles (symbol G.name).
	Dictionary<int, MonsterGroupInfo> Groups;
	/// Hit points, attack and defense the hero starts with.
	HeroInfo Hero;
	/// The companions by symbol ID (C.name).
	Dictionary<int, CompanionInfo> Companions;
	/// The spells by symbol ID (SP.name).
	Dictionary<int, SpellInfo> Spells;
	/// The item icon sheet (under the assets folder), or null if none is set or the pack is not installed. Icons are 16x16
	/// cells; an item's icon is the cell index (row * columns + column).
	string IconSheetPath;
	/// The user interface theme, or UiTheme.Empty() if the game has none.
	UiTheme Theme;
	Dictionary<string, int> MapIds;
	/// Display names of the maps (shown in the HUD).
	Dictionary<string, string> Places;
	/// Palette, night palette and day/night switch of the maps by name.
	Dictionary<string, MapLookInfo> MapLooks;
	/// The palettes of the tables by symbol ID (PAL.name).
	Dictionary<int, Palette> Palettes;
	/// Paper doll layers of the characters (see characters.yaml).
	Dictionary<string, string[]> Characters;
	/// The screen definitions (YAML, kept in the pack).
	ScreenLibrary Screens;
	Dictionary<string, int> ScreenIds;
	Dictionary<int, string> NativeNames;

	int ScreenId(string name)
	{
		return ScreenIds.GetOrDefault(name, -1);
	}

	/// The name of a screen by its ID, or null.
	string ScreenName(int id)
	{
		foreach (var pair in ScreenIds.Entries())
		{
			if (pair.Value == id)
				return pair.Key;
		}

		return null;
	}

	/// Name of a native function or data source by its ID (symbol N.name), or null.
	string NativeName(int id)
	{
		return NativeNames.GetOrDefault(id, null);
	}

	/// The text of a table symbol (T.name).
	Optional<TextInfo> TextByName(string name)
	{
		if (Symbols.TryResolve(SymbolKind.Text, name) is uint16 id)
			return Texts.TryGet((int)id);

		return null;
	}

	int KeywordId(string name)
	{
		if (Symbols.TryResolve(SymbolKind.Keyword, name) is uint16 id)
			return (int)id;

		return -1;
	}

	/// The index of a flag in the layout: of the map with the name (namespace map), or of the global scope (scopeName null).
	int FlagIndex(string scopeName, string name)
	{
		string scopeKind = scopeName == null ? ScopeKindName(ScopeKind.Global) : ScopeKindName(ScopeKind.Map);
		string space = scopeName == null ? StateNamespaceName(StateNamespace.Global) : StateNamespaceName(StateNamespace.Map);
		string kind = SlotKindName(SlotKind.Flag);

		foreach (var slot in Layout.Slots)
		{
			if (slot.ScopeKind == scopeKind && (scopeName == null || slot.ScopeName == scopeName) && slot.Namespace == space && slot.Kind == kind && slot.Name == name)
				return slot.Index;
		}

		return -1;
	}

	/// Reads a pack cooked by PackCook. repositoryRoot is where the assets folder (item icons) is looked for.
	static Error<GameContent> FromPack(uint8[] data, string repositoryRoot)
	{
		var reader = try PackReader.FromMemory(data);
		var pack = PackContent.Of(reader);

		try pack.CheckLayout();

		if ((reader.Header.Flags & PackHasSymbols) == 0)
			return error("The pack has no symbol names (cooked with --no-symbols); the game needs them for its savegames.", (int)ErrorKind.InvalidPack);

		var content = GameContent
		{
			GlobalScript = try pack.GlobalScript(),
			GlobalSizes = pack.GlobalSizes(),
			Limits = pack.Limits(),
			LayoutHash = reader.Header.LayoutHash,
			Layout = try pack.Layout(),
			Maps = List<PackedMap>.Create(),
			GlobalGroups = Dictionary<string, uint16>.Create(),
			ScreenScripts = Dictionary<string, ScreenScript>.Create(),
			Symbols = SymbolTable.Create(false),
			Texts = Dictionary<int, TextInfo>.Create(),
			Items = Dictionary<int, ItemInfo>.Create(),
			Keywords = try pack.Strings(KeywordTable),
			Deltas = Dictionary<int, DeltaInfo>.Create(),
			Chests = Dictionary<int, ChestInfo>.Create(),
			Groups = Dictionary<int, MonsterGroupInfo>.Create(),
			Hero = HeroInfo { Hp = 30, Attack = 5, Defense = 1, StartMap = "", StartX = -1, StartY = -1 },
			Companions = Dictionary<int, CompanionInfo>.Create(),
			Spells = Dictionary<int, SpellInfo>.Create(),
			IconSheetPath = null,
			Theme = UiTheme.Empty(),
			MapIds = Dictionary<string, int>.Create(),
			Places = Dictionary<string, string>.Create(),
			MapLooks = Dictionary<string, MapLookInfo>.Create(),
			Palettes = Dictionary<int, Palette>.Create(),
			Characters = Dictionary<string, string[]>.Create(),
			Screens = ScreenLibrary.Create(),
			ScreenIds = Dictionary<string, int>.Create(),
			NativeNames = Dictionary<int, string>.Create()
		};

		foreach (var symbol in try pack.Symbols())
			content.Symbols.Define((SymbolKind)symbol.Kind, symbol.Name, symbol.Id);

		foreach (var native in try pack.Natives())
		{
			if (!native.DataSource)
				content.NativeNames.Set((int)native.Id, native.Name);
		}

		var mapIds = pack.MapIds();

		SortList(mapIds, CompareInt);

		foreach (var id in mapIds)
		{
			var map = try pack.LoadMap(id);

			content.Maps.Add(map);
			content.MapIds.Set(map.Name, id);
		}

		foreach (var pair in (try pack.Strings(PlaceTable)).Entries())
		{
			string mapName = SymbolName(content.Symbols, SymbolKind.Map, pair.Key);

			if (mapName != null)
				content.Places.Set(mapName, pair.Value);
		}

		// the screens: all of the symbol table, the ones with a screen block get their chunk and group names
		foreach (var pair in content.Symbols.Ids.Entries())
		{
			if (pair.Key.Kind == SymbolKind.Screen)
				content.ScreenIds.Set(pair.Key.Name, (int)pair.Value);
		}

		foreach (var entry in try pack.Names(GroupNameTable))
		{
			if (entry.Kind == GlobalGroupName)
				content.GlobalGroups.Set(entry.Name, entry.Id);
			else if (entry.Kind == ScriptedScreenName)
			{
				var screen = try pack.LoadScreen(content.ScreenId(entry.Name));

				content.ScreenScripts.Set(entry.Name, ScreenScript { Chunk = screen.Script, Sizes = screen.Sizes, GroupRefs = Dictionary<string, uint16>.Create() });
			}
			else if (entry.Kind == ScreenGroupName)
			{
				var parts = SplitToList(entry.Name, "/");

				if (parts.Count() == 2 && content.ScreenScripts.TryGet(parts.Get(0)) is ScreenScript script)
					script.GroupRefs.Set(parts.Get(1), entry.Id);
			}
		}

		var texts = try pack.Texts(0);
		var speakers = try pack.Strings(SpeakerTable);

		foreach (var pair in texts.Entries())
			content.Texts.Set(pair.Key, TextInfo { Speaker = speakers.GetOrDefault(pair.Key, ""), Text = pair.Value });

		var names = try pack.Strings(ItemNameTable);
		var descriptions = try pack.Strings(ItemDescriptionTable);

		foreach (var item in try ReadItems(try reader.Get(PackChunkType.Table, ItemTable)))
		{
			var full = item;
			string key = SymbolName(content.Symbols, SymbolKind.Item, item.Id);

			full.Key = key != null ? key : "" + item.Id;
			full.Name = names.GetOrDefault(item.Id, "");
			full.Description = descriptions.GetOrDefault(item.Id, "");
			content.Items.Set(item.Id, full);
		}

		content.Deltas = try ReadDeltas(try reader.Get(PackChunkType.Table, DeltaTable));
		content.Chests = try ReadChests(try reader.Get(PackChunkType.Table, ChestTable));
		content.Groups = try ReadMonsterGroups(try reader.Get(PackChunkType.Table, MonsterGroupTable), content.Symbols);
		content.Characters = try ReadCharacters(try reader.Get(PackChunkType.Table, CharacterTable));

		content.Spells = try ReadSpells(try reader.Get(PackChunkType.Table, SpellTable));
		content.Companions = try ReadCompanions(try reader.Get(PackChunkType.Table, CompanionTable));
		content.Palettes = try ReadPalettes(try reader.Get(PackChunkType.Table, PaletteTable));

		foreach (var pair in (try ReadMapLooks(try reader.Get(PackChunkType.Table, MapLookTable))).Entries())
		{
			string mapName = SymbolName(content.Symbols, SymbolKind.Map, pair.Key);

			if (mapName != null)
				content.MapLooks.Set(mapName, pair.Value);
		}

		var info = try ReadGameInfo(try reader.Get(PackChunkType.Table, GameInfoTable));

		content.Hero = info.Hero;

		if (info.IconSheet.Length > 0 && !(Process.GetEnv("AMBERWORLDS_NO_ICONS") is string noIcons && noIcons == "1"))
		{
			string sheet = Path.Combine(Path.Combine(repositoryRoot, "assets"), info.IconSheet);

			content.IconSheetPath = File.Exists(sheet) ? sheet : null;
		}

		// the screen definitions and the theme are YAML files of the pack (see PackCook)
		var fileNames = try pack.Names(FileNameTable);
		var fileTexts = try pack.Strings(FileTextTable);
		var screenFiles = List<ScreenFile>.Create();

		foreach (var file in fileNames)
		{
			string text = fileTexts.GetOrDefault((int)file.Id, "");

			if (file.Kind == ThemeFile)
				content.Theme = try UiTheme.Parse(text);
			else if (file.Kind == ScreenFileKind)
				screenFiles.Add(ScreenFile { Path = file.Name, Text = text });
		}

		content.Screens = try ScreenLibrary.LoadFiles(screenFiles);

		return content;
	}

	static Error<GameContent> Load(string packPath, string repositoryRoot)
	{
		var data = File.ReadAllBytes(packPath);

		if (data is uint8[] bytes)
			return FromPack(bytes, repositoryRoot);

		return error("cannot read the pack '" + packPath + "': " + data.Message, (int)ErrorKind.Io);
	}
}

/// The name of a symbol by its ID, or null.
string SymbolName(SymbolTable symbols, SymbolKind kind, int id)
{
	foreach (var pair in symbols.Ids.Entries())
	{
		if (pair.Key.Kind == kind && (int)pair.Value == id)
			return pair.Key.Name;
	}

	return null;
}
