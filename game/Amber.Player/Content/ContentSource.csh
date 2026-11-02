namespace Amber.Player.Content;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Screens;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

struct TextInfo
{
	string Speaker;
	string Text;
}

struct ItemInfo
{
	int Id;
	string Key;
	string Name;
	string Description;
	int Price;
	int Heal;
	int Icon;
	int Attack;
	int Defense;
	/// Ticks between two blows when the hero carries it as a weapon (0: not a weapon; see Combat).
	int Speed;
	/// What a companion can wear it as: "weapon", "armor" or "" (items: slot).
	string Slot;
	/// The spell a companion learns from it (a scroll; symbol ID, 0 for none; items: teaches).
	int Teaches;
}

/// A spell of the companions (tables.yaml spells:, symbol SP.name). kind: heal (a healer heals power more), shield (a
/// healer's shield gives power defense), bolt (a mage's blow is power stronger), blast (the mage's spell also hits the
/// monsters next to the target with half the force).
struct SpellInfo
{
	int Id;
	string Key;
	string Name;
	string Kind;
	int Power;
	string Description;
}

struct MonsterInfo
{
	string Key;
	string Name;
	int Hp;
	int Attack;
	int Defense;
}

/// A companion of the hero (tables.yaml companions:, symbol C.name): joins with add_member, follows the hero and fights on
/// its own by its role (healer, mage, ranger). Range in tiles (1: next to the target), speed in ticks between two actions,
/// heal: hit points a healer gives, look: the figure in characters.yaml (the key if not given).
struct CompanionInfo
{
	int Id;
	string Key;
	string Name;
	string Role;
	int Hp;
	int Attack;
	int Defense;
	int Range;
	int Speed;
	int Heal;
	string Look;
	/// The spells the companion knows from the start (symbol IDs).
	int[] Spells;
}

struct MonsterGroupInfo
{
	int Id;
	string Key;
	MonsterInfo[] Monsters;
}

struct HeroInfo
{
	int Hp;
	int Attack;
	int Defense;
	/// Where a new game starts (tables.yaml start:): the map ("" the first map of maps:) and the cell (-1: the middle).
	string StartMap;
	int StartX;
	int StartY;
}

struct DeltaTile
{
	int Layer;
	int X;
	int Y;
	uint32 Tile;
}

struct ChestInfo
{
	int Id;
	int Gold;
	/// Item ID to count, in the order of tables.yaml.
	Dictionary<int, int> Items;
}

struct DeltaInfo
{
	DeltaTile[] Tiles;
	int UnblockX;
	int UnblockY;
	int UnblockWidth;
	int UnblockHeight;
}

/// How a map looks (Ziele Z4): its palette, its night palette and whether the host blends between them by the clock.
/// The palettes are IDs of PAL symbols, 0 for none (the game builds the palette from the tiles, the night from the day).
struct MapLookInfo
{
	int Palette;
	int Night;
	bool Daylight;
}

/// The tile layers of a delta, in the order of the layer operand of set_tile (C#: GameContent.layerNames).
const ReadOnlySlice<string> DeltaLayerNames = ["ground", "decor", "objects", "over"];

/// The content folder as the cook reads it: the tables (texts, items, keywords, deltas ...), the compiled scripts, the
/// screen definitions and the resolved symbol IDs. PackCook turns it into the pack the game runs from (GameContent).
/// Copies share the tables.
struct ContentSource
{
	CompilationResult Compilation;
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
	/// The file of the item icon sheet (tables.yaml icon_sheet, relative to the assets folder), or null if none is set or
	/// the pack is not installed. Icons are 16x16 cells; an item's icon is the cell index (row * columns + column).
	string IconSheetPath;
	/// The user interface theme (content/ui.yaml), or UiTheme.Empty() if the game has none.
	UiTheme Theme;
	/// The text of content/ui.yaml, or null.
	string ThemeText;
	/// The file of the item icon sheet relative to the assets folder (tables.yaml icon_sheet), or "".
	string IconSheet;
	Dictionary<string, int> MapIds;
	/// Display names of the maps (shown in the HUD).
	Dictionary<string, string> Places;
	/// Palette, night palette and day/night switch of the maps by name.
	Dictionary<string, MapLookInfo> MapLooks;
	/// The palettes of tables.yaml (palettes: name: file.gpl, relative to the content folder) by symbol ID (PAL.name).
	Dictionary<int, Palette> Palettes;
	/// Paper doll layers of the characters (see characters.yaml).
	Dictionary<string, string[]> Characters;
	/// The screen definitions (YAML, folder screens).
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
		if (Compilation.Symbols.TryResolve(SymbolKind.Text, name) is uint16 id)
			return Texts.TryGet((int)id);

		return null;
	}

	int KeywordId(string name)
	{
		if (Compilation.Symbols.TryResolve(SymbolKind.Keyword, name) is uint16 id)
			return (int)id;

		return -1;
	}

	/// Reads the tables, compiles the scripts and checks the screens. repositoryRoot is where the assets folder is looked for.
	static Error<ContentSource> Load(string contentDirectory, string repositoryRoot)
	{
		var tables = try ReadYamlFile(Path.Combine(contentDirectory, "tables.yaml"));
		var symbols = SymbolTable.Create(false);
		var maps = Section(tables, "maps");
		var screens = Section(tables, "screens");
		var natives = Section(tables, "natives");
		var keywords = Section(tables, "keywords");
		var items = Section(tables, "items");
		var tiles = Section(tables, "tiles");
		var deltas = Section(tables, "deltas");
		var chests = Section(tables, "chests");
		var texts = Section(tables, "texts");
		var groups = Section(tables, "groups");
		var monsters = Section(tables, "monsters");
		var palettes = Section(tables, "palettes");
		var companions = Section(tables, "companions");
		var spells = Section(tables, "spells");

		DefineAll(symbols, SymbolKind.Map, KeysOf(maps));
		DefineAll(symbols, SymbolKind.Screen, ScalarsOf(screens));
		DefineAll(symbols, SymbolKind.Native, ScalarsOf(natives));
		DefineAll(symbols, SymbolKind.Keyword, KeysOf(keywords));
		DefineAll(symbols, SymbolKind.Item, KeysOf(items));
		DefineAll(symbols, SymbolKind.Text, KeysOf(texts));
		DefineAll(symbols, SymbolKind.Delta, KeysOf(deltas));
		DefineAll(symbols, SymbolKind.Chest, KeysOf(chests));
		DefineAll(symbols, SymbolKind.MonsterGroup, KeysOf(groups));
		DefineAll(symbols, SymbolKind.Palette, KeysOf(palettes));
		DefineAll(symbols, SymbolKind.Character, KeysOf(companions));
		DefineAll(symbols, SymbolKind.Spell, KeysOf(spells));

		for (var i = 0; i < tiles.Count(); i += 1)
			symbols.Define(SymbolKind.Tile, tiles.KeyAt(i), (uint16)(try NumberOf(tiles.ItemAt(i), "tile " + tiles.KeyAt(i))));

		var files = List<SourceFile>.Create();

		foreach (var path in Directory.FindFiles(Path.Combine(contentDirectory, "scripts"), ".ams"))
			files.Add(SourceFile.Create(path, try ReadText(path)));

		var library = try ScreenLibrary.Load(Path.Combine(contentDirectory, "screens"));
		var result = ScriptCompiler.Compile(ArrayOf(files), CompileOptions { Symbols = symbols, Screens = library.Signatures() });

		if (result.HasErrors())
		{
			var errors = List<string>.Create();

			foreach (var item in result.Diagnostics.Items)
			{
				if (item.Severity == Severity.Error)
					errors.Add(item.Text());
			}

			return error("The scripts have errors:\n" + JoinList("\n", errors), (int)ErrorKind.InvalidData);
		}

		foreach (var item in result.Diagnostics.Items)
		{
			if (item.Severity == Severity.Warning)
				Console.WriteErrorLine(item.Text());
		}

		var content = ContentSource
		{
			Compilation = result,
			Texts = Dictionary<int, TextInfo>.Create(),
			Items = Dictionary<int, ItemInfo>.Create(),
			Keywords = Dictionary<int, string>.Create(),
			Deltas = Dictionary<int, DeltaInfo>.Create(),
			Chests = Dictionary<int, ChestInfo>.Create(),
			Groups = Dictionary<int, MonsterGroupInfo>.Create(),
			Hero = HeroInfo { Hp = 30, Attack = 5, Defense = 1, StartMap = "", StartX = -1, StartY = -1 },
			Companions = Dictionary<int, CompanionInfo>.Create(),
			Spells = Dictionary<int, SpellInfo>.Create(),
			IconSheetPath = null,
			Theme = UiTheme.Empty(),
			ThemeText = null,
			IconSheet = "",
			MapIds = Dictionary<string, int>.Create(),
			Places = Dictionary<string, string>.Create(),
			MapLooks = Dictionary<string, MapLookInfo>.Create(),
			Palettes = Dictionary<int, Palette>.Create(),
			Characters = Dictionary<string, string[]>.Create(),
			Screens = library,
			ScreenIds = Dictionary<string, int>.Create(),
			NativeNames = Dictionary<int, string>.Create()
		};

		foreach (var native in ScalarsOf(natives))
			content.NativeNames.Set(try Id(symbols, SymbolKind.Native, native), native);

		// every screen of the tables has a definition, and every handler of a definition is a group of the screen or a global one
		var screenNames = ScalarsOf(screens);

		foreach (var screen in screenNames)
		{
			var definition = try DefinitionOf(library, screen);
			var scope = result.FindScreen(screen);

			foreach (var handler in definition.Handlers())
			{
				bool local = false;

				if (scope is CompiledScope screenScope)
					local = screenScope.GroupRefs.ContainsKey(handler);

				if (!local && !result.Global.GroupRefs.ContainsKey(handler))
					return error("Screen '" + screen + "': the handler group '" + handler + "' does not exist.", (int)ErrorKind.InvalidData);
			}
		}

		foreach (var screen in library.Screens.Keys())
		{
			if (!ContainsText(screenNames, screen))
				return error("Screen '" + screen + "' has a YAML definition but is not in the screens list of tables.yaml.", (int)ErrorKind.InvalidData);
		}

		for (var i = 0; i < texts.Count(); i += 1)
		{
			string key = texts.KeyAt(i);
			var entry = texts.ItemAt(i);
			string speaker = TextOr(entry, "speaker", "");
			string text = TextOr(entry, "text", "");

			try RequireLatin1("text '" + key + "'", speaker + text);
			content.Texts.Set(try Id(symbols, SymbolKind.Text, key), TextInfo { Speaker = speaker, Text = text });
		}

		for (var i = 0; i < items.Count(); i += 1)
		{
			string key = items.KeyAt(i);
			var entry = items.ItemAt(i);
			int id = try Id(symbols, SymbolKind.Item, key);

			content.Items.Set(id, ItemInfo
			{
				Id = id, Key = key, Name = TextOr(entry, "name", ""), Description = TextOr(entry, "description", ""),
				Price = try IntOr(entry, "price", 0), Heal = try IntOr(entry, "heal", 0), Icon = try IntOr(entry, "icon", -1),
				Attack = try IntOr(entry, "attack", 0), Defense = try IntOr(entry, "defense", 0), Speed = try IntOr(entry, "speed", 0),
				Slot = try SlotOf(entry, key), Teaches = try SpellId(symbols, TextOr(entry, "teaches", ""), "item " + key)
			});
		}

		for (var i = 0; i < keywords.Count(); i += 1)
			content.Keywords.Set(try Id(symbols, SymbolKind.Keyword, keywords.KeyAt(i)), ScalarText(keywords.ItemAt(i)));

		for (var i = 0; i < deltas.Count(); i += 1)
		{
			var entry = deltas.ItemAt(i);
			var deltaTiles = List<DeltaTile>.Create();

			foreach (var tile in ItemsOf(Section(entry, "tiles")))
			{
				string tileName = TextOr(tile, "tile", "");

				if (!tiles.ContainsKey(tileName))
					return error("The delta '" + deltas.KeyAt(i) + "' uses the unknown tile '" + tileName + "'.", (int)ErrorKind.InvalidData);

				deltaTiles.Add(DeltaTile
				{
					Layer = IndexOfText(DeltaLayerNames, TextOr(tile, "layer", "")), X = try IntOr(tile, "x", 0), Y = try IntOr(tile, "y", 0),
					Tile = (uint32)(try IntOr(tiles, tileName, 0))
				});
			}

			var unblock = Section(entry, "unblock");

			content.Deltas.Set(try Id(symbols, SymbolKind.Delta, deltas.KeyAt(i)), DeltaInfo
			{
				Tiles = ArrayOf(deltaTiles), UnblockX = try IntOr(unblock, "x", 0), UnblockY = try IntOr(unblock, "y", 0),
				UnblockWidth = try IntOr(unblock, "w", 0), UnblockHeight = try IntOr(unblock, "h", 0)
			});
		}

		for (var i = 0; i < chests.Count(); i += 1)
		{
			string key = chests.KeyAt(i);
			var entry = chests.ItemAt(i);
			int id = try Id(symbols, SymbolKind.Chest, key);
			var chestItems = Section(entry, "items");
			var contents = Dictionary<int, int>.Create();

			for (var j = 0; j < chestItems.Count(); j += 1)
			{
				if (symbols.TryResolve(SymbolKind.Item, chestItems.KeyAt(j)) == null)
					return error("Chest '" + key + "' holds the unknown item '" + chestItems.KeyAt(j) + "'.", (int)ErrorKind.InvalidData);

				contents.Set(try Id(symbols, SymbolKind.Item, chestItems.KeyAt(j)), try NumberOf(chestItems.ItemAt(j), "chest " + key));
			}

			content.Chests.Set(id, ChestInfo { Id = id, Gold = try IntOr(entry, "gold", 0), Items = contents });
		}

		string iconSheet = TextOr(tables, "icon_sheet", "");

		content.IconSheet = iconSheet;

		if (iconSheet.Length > 0 && !(Process.GetEnv("AMBERWORLDS_NO_ICONS") is string noIcons && noIcons == "1"))
		{
			string sheet = Path.Combine(Path.Combine(repositoryRoot, "assets"), iconSheet);

			content.IconSheetPath = File.Exists(sheet) ? sheet : null;
		}

		string themePath = Path.Combine(contentDirectory, "ui.yaml");

		if (File.Exists(themePath))
		{
			content.ThemeText = try ReadText(themePath);
			content.Theme = try UiTheme.Load(themePath);
		}

		var hero = Section(tables, "hero");

		var start = Section(tables, "start");

		content.Hero = HeroInfo
		{
			Hp = try IntOr(hero, "hp", 30), Attack = try IntOr(hero, "attack", 5), Defense = try IntOr(hero, "defense", 1),
			StartMap = TextOr(start, "map", maps.Count() > 0 ? maps.KeyAt(0) : ""), StartX = try IntOr(start, "x", -1), StartY = try IntOr(start, "y", -1)
		};

		if (content.Hero.StartMap.Length > 0 && !maps.ContainsKey(content.Hero.StartMap))
			return error("tables.yaml: the start map '" + content.Hero.StartMap + "' is not in maps.", (int)ErrorKind.InvalidData);

		for (var i = 0; i < groups.Count(); i += 1)
		{
			string key = groups.KeyAt(i);
			int id = try Id(symbols, SymbolKind.MonsterGroup, key);
			var members = groups.ItemAt(i);
			var list = List<MonsterInfo>.Create();

			for (var j = 0; j < members.Count(); j += 1)
			{
				string monster = members.KeyAt(j);

				if (!monsters.ContainsKey(monster))
					return error("Group '" + key + "' has the unknown monster '" + monster + "'.", (int)ErrorKind.InvalidData);

				var entry = Section(monsters, monster);
				string name = TextOr(entry, "name", "");

				try RequireLatin1("monster '" + monster + "'", name);

				int count = try NumberOf(members.ItemAt(j), "group " + key);

				for (var k = 0; k < count; k += 1)
					list.Add(MonsterInfo { Key = monster, Name = name, Hp = try IntOr(entry, "hp", 1), Attack = try IntOr(entry, "attack", 1), Defense = try IntOr(entry, "defense", 0) });
			}

			content.Groups.Set(id, MonsterGroupInfo { Id = id, Key = key, Monsters = ArrayOf(list) });
		}

		for (var i = 0; i < spells.Count(); i += 1)
		{
			string key = spells.KeyAt(i);
			var entry = spells.ItemAt(i);
			string kind = TextOr(entry, "kind", "");

			if (kind != "heal" && kind != "shield" && kind != "bolt" && kind != "blast")
				return error("tables.yaml: the spell '" + key + "' has the kind '" + kind + "'; it is heal, shield, bolt or blast.", (int)ErrorKind.InvalidData);

			string name = TextOr(entry, "name", key);
			string description = TextOr(entry, "description", "");

			try RequireLatin1("spell '" + key + "'", name + description);

			int id = try Id(symbols, SymbolKind.Spell, key);

			content.Spells.Set(id, SpellInfo { Id = id, Key = key, Name = name, Kind = kind, Power = try IntOr(entry, "power", 0), Description = description });
		}

		for (var i = 0; i < companions.Count(); i += 1)
		{
			string key = companions.KeyAt(i);
			var entry = companions.ItemAt(i);
			int id = try Id(symbols, SymbolKind.Character, key);
			string role = TextOr(entry, "role", "");

			if (role != "healer" && role != "mage" && role != "ranger")
				return error("tables.yaml: the companion '" + key + "' has the role '" + role + "'; it is healer, mage or ranger.", (int)ErrorKind.InvalidData);

			string name = TextOr(entry, "name", key);

			try RequireLatin1("companion '" + key + "'", name);
			content.Companions.Set(id, CompanionInfo
			{
				Id = id, Key = key, Name = name, Role = role, Hp = try IntOr(entry, "hp", 20), Attack = try IntOr(entry, "attack", 3),
				Defense = try IntOr(entry, "defense", 0), Range = try IntOr(entry, "range", role == "ranger" ? 5 : 4), Speed = try IntOr(entry, "speed", 60),
				Heal = try IntOr(entry, "heal", 0), Look = TextOr(entry, "look", key), Spells = try SpellIds(symbols, Section(entry, "spells"), "companion " + key)
			});
		}

		string charactersPath = Path.Combine(contentDirectory, "characters.yaml");

		if (File.Exists(charactersPath))
		{
			var characters = Section(try ReadYamlFile(charactersPath), "characters");

			for (var i = 0; i < characters.Count(); i += 1)
				content.Characters.Set(characters.KeyAt(i), ArrayOfStrings(ScalarsOf(characters.ItemAt(i))));
		}

		for (var i = 0; i < palettes.Count(); i += 1)
		{
			string file = ScalarText(palettes.ItemAt(i));
			var palette = try LoadPalette(Path.Combine(contentDirectory, file));

			content.Palettes.Set(try Id(symbols, SymbolKind.Palette, palettes.KeyAt(i)), palette);
		}

		// a map is "key: display name" or "key: { name: ..., palette: name, night: name, daylight: off }"
		for (var i = 0; i < maps.Count(); i += 1)
		{
			string key = maps.KeyAt(i);
			var entry = maps.ItemAt(i);

			content.MapIds.Set(key, try Id(symbols, SymbolKind.Map, key));
			content.Places.Set(key, entry.IsMapping() ? TextOr(entry, "name", key) : ScalarText(entry));

			var look = MapLookInfo { Palette = 0, Night = 0, Daylight = true };

			if (entry.IsMapping())
			{
				look.Palette = try PaletteId(symbols, TextOr(entry, "palette", ""), key);
				look.Night = try PaletteId(symbols, TextOr(entry, "night", ""), key);

				string daylight = TextOr(entry, "daylight", "on");

				if (daylight != "on" && daylight != "off")
					return error("tables.yaml: daylight of the map '" + key + "' is on or off, not '" + daylight + "'.", (int)ErrorKind.InvalidData);

				look.Daylight = daylight == "on";
			}

			content.MapLooks.Set(key, look);
		}

		foreach (var screen in screenNames)
			content.ScreenIds.Set(screen, try Id(symbols, SymbolKind.Screen, screen));

		return content;
	}
}

Error<string> SlotOf(YamlNode item, string key)
{
	string slot = TextOr(item, "slot", "");

	if (slot != "" && slot != "weapon" && slot != "armor")
		return error("tables.yaml: the item '" + key + "' has the slot '" + slot + "'; it is weapon or armor.", (int)ErrorKind.InvalidData);

	return slot;
}

/// The ID of a spell of tables.yaml, 0 for none ("").
Error<int> SpellId(SymbolTable symbols, string name, string user)
{
	if (name.Length == 0)
		return 0;

	if (symbols.TryResolve(SymbolKind.Spell, name) is uint16 id)
		return (int)id;

	return error("tables.yaml: the " + user + " names the spell '" + name + "', which is not in spells.", (int)ErrorKind.InvalidData);
}

Error<int[]> SpellIds(SymbolTable symbols, YamlNode list, string user)
{
	var ids = List<int>.Create();

	foreach (var name in ScalarsOf(list))
		ids.Add(try SpellId(symbols, name, user));

	return ArrayOf(ids);
}

/// The ID of a palette of tables.yaml, 0 for none ("").
Error<int> PaletteId(SymbolTable symbols, string name, string map)
{
	if (name.Length == 0)
		return 0;

	if (symbols.TryResolve(SymbolKind.Palette, name) is uint16 id)
		return (int)id;

	return error("tables.yaml: the map '" + map + "' uses the palette '" + name + "', which is not in palettes.", (int)ErrorKind.InvalidData);
}

Error<ScreenDefinition> DefinitionOf(ScreenLibrary library, string screen)
{
	if (library.Find(screen) is ScreenDefinition definition)
		return definition;

	return error("Screen '" + screen + "' is in tables.yaml but has no YAML definition.", (int)ErrorKind.InvalidData);
}

/// E012: the packs store texts as Latin-1 (spec section 11), so every character has to be one.
Error<void> RequireLatin1(string what, string text)
{
	int bad = FirstNonLatin1(text);

	if (bad >= 0)
		return error("E012: " + what + " contains '" + CodePointText(bad) + "' (U+" + Hex(bad, 4) + "), which is not a Latin-1 character.", (int)ErrorKind.InvalidData);

	return;
}

void DefineAll(SymbolTable symbols, SymbolKind kind, List<string> names)
{
	int id = 1;

	foreach (var name in names)
	{
		symbols.Define(kind, name, (uint16)id);
		id += 1;
	}
}

Error<int> Id(SymbolTable symbols, SymbolKind kind, string name)
{
	if (symbols.TryResolve(kind, name) is uint16 id)
		return (int)id;

	return error("The symbol " + SymbolKinds.Prefix(kind) + "." + name + " is not defined.", (int)ErrorKind.InvalidData);
}

Error<YamlNode> ReadYamlFile(string path)
{
	var parsed = ParseYaml(try ReadText(path));

	if (parsed is YamlNode document)
		return document;

	return error(path + ": " + parsed.Message, (int)ErrorKind.InvalidData);
}

/// The value of a key, or an empty mapping if it is missing or null (C#: the property initializers of the table classes).
YamlNode Section(YamlNode map, string key)
{
	if (map.IsMapping())
	{
		if (map.GetValue(key) is YamlNode value)
			return value;
	}

	return YamlNode.Mapping(0);
}

/// The keys of a mapping in their order.
List<string> KeysOf(YamlNode map)
{
	var keys = List<string>.Create();

	if (map.IsMapping())
	{
		for (var i = 0; i < map.Count(); i += 1)
			keys.Add(map.KeyAt(i));
	}

	return keys;
}

/// The items of a sequence (none for anything else).
List<YamlNode> ItemsOf(YamlNode sequence)
{
	var items = List<YamlNode>.Create();

	if (sequence.IsSequence())
	{
		for (var i = 0; i < sequence.Count(); i += 1)
			items.Add(sequence.ItemAt(i));
	}

	return items;
}

/// The scalar texts of a sequence.
List<string> ScalarsOf(YamlNode sequence)
{
	var texts = List<string>.Create();

	foreach (var item in ItemsOf(sequence))
		texts.Add(ScalarText(item));

	return texts;
}

string[] ArrayOfStrings(List<string> list)
{
	var result = new string[list.Count()];

	for (var i = 0; i < result.Length; i += 1)
		result[i] = list.Get(i);

	return result;
}

string ScalarText(YamlNode node)
{
	return node.IsScalar() ? node.Value : "";
}

string TextOr(YamlNode map, string key, string fallback)
{
	if (map.IsMapping())
	{
		string text = map.GetText(key);

		if (text != null)
			return text;
	}

	return fallback;
}

Error<int> NumberOf(YamlNode node, string what)
{
	if (node.IsScalar())
	{
		if (TryParseInt(node.Value) is int value)
			return value;
	}

	return error("tables.yaml: " + what + " is not a number (line " + node.Line + ").", (int)ErrorKind.InvalidData);
}

Error<int> IntOr(YamlNode map, string key, int fallback)
{
	if (map.IsMapping())
	{
		if (map.GetValue(key) is YamlNode value)
			return NumberOf(value, key);
	}

	return fallback;
}
