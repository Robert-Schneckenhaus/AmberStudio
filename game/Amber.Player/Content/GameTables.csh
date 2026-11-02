// The tables of the prototype in the pack (TABLE chunks from PackTableFirstGameTable on): what the spec leaves to the
// game. PackCook writes them, GameContent.FromPack reads them. All numbers are big endian words (signed where a value can
// be negative) or double words, texts are Latin-1 with a word for the length, padded to an even length (ChunkWriter).

namespace Amber.Player.Content;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Pack;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

/// String tables (StringTable): the speaker of every text, the keywords, the names and descriptions of the items, the
/// display names of the maps (by map ID) and the texts of the YAML files of the pack.
const int SpeakerTable = PackTableFirstGameTable;
const int KeywordTable = PackTableFirstGameTable + 1;
const int ItemNameTable = PackTableFirstGameTable + 2;
const int ItemDescriptionTable = PackTableFirstGameTable + 3;
const int PlaceTable = PackTableFirstGameTable + 4;
const int FileTextTable = PackTableFirstGameTable + 5;
/// Records: u16 count, per item u16 id, i16 price, heal, icon, attack, defense, speed, u16 slot (0 none, 1 weapon,
/// 2 armor), u16 spell it teaches (0 none).
const int ItemTable = PackTableFirstGameTable + 6;
/// u16 count, per delta u16 id, u16 tileCount, i16 unblock x, y, w, h, per tile u16 layer, u16 x, u16 y, u32 tile.
const int DeltaTable = PackTableFirstGameTable + 7;
/// u16 count, per chest u16 id, u32 gold, u16 itemCount, per item u16 item, u16 count (in the order of tables.yaml).
const int ChestTable = PackTableFirstGameTable + 8;
/// u16 count, per group u16 id, u16 monsterCount, per monster the key, the name, u16 hp, attack, defense.
const int MonsterGroupTable = PackTableFirstGameTable + 9;
/// u16 count, per character the name, u16 layerCount and the layers.
const int CharacterTable = PackTableFirstGameTable + 10;
/// u16 hero hp, attack, defense, then the icon sheet (relative to the assets folder, "" for none), then (optional, packs
/// before it have none) the start map ("" the first one) and the start cell + 1 (0: the middle of the map).
const int GameInfoTable = PackTableFirstGameTable + 11;
/// Names (NamedId): the groups of the global scope (kind 0, ID = group reference), the screens with a screen block
/// (kind 1, the name of the screen) and the groups of those screens (kind 2, "screen/group").
const int GroupNameTable = PackTableFirstGameTable + 12;
/// Names (NamedId): the YAML files of the pack (kind 0 screen or prefab, kind 1 theme); the ID is the entry of
/// FileTextTable.
const int FileNameTable = PackTableFirstGameTable + 13;
/// u16 count, per palette u16 id, u16 size, the name, then size * 3 bytes red, green, blue and size bytes 1 (used) or 0.
const int PaletteTable = PackTableFirstGameTable + 14;
/// u16 count, per map u16 map id, u16 palette (0 none), u16 night palette (0 none), u16 flags (bit0 daylight).
const int MapLookTable = PackTableFirstGameTable + 15;
/// u16 count, per companion u16 id, the key, the name, the role, the look, i16 hp, attack, defense, range, speed, heal,
/// u16 spellCount and the spell IDs.
const int CompanionTable = PackTableFirstGameTable + 16;
/// u16 count, per spell u16 id, the key, the name, the kind, the description, i16 power.
const int SpellTable = PackTableFirstGameTable + 17;

const uint8 GlobalGroupName = 0;
const uint8 ScriptedScreenName = 1;
const uint8 ScreenGroupName = 2;
const uint8 ScreenFileKind = 0;
const uint8 ThemeFile = 1;

void WriteText(ChunkWriter writer, string text)
{
	writer.Word(Latin1Length(text));
	writer.PaddedText(text);
}

Error<string> ReadText(ref ChunkReader reader)
{
	return reader.PaddedText(try reader.Word());
}

Error<int> ReadSigned(ref ChunkReader reader)
{
	return (int)(int16)(try reader.Word());
}

uint8[] WriteItems(Dictionary<int, ItemInfo> items)
{
	var writer = ChunkWriter.Create();

	writer.Word(items.Count());

	foreach (var item in items.Values())
	{
		writer.Word(item.Id);
		writer.Word(item.Price);
		writer.Word(item.Heal);
		writer.Word(item.Icon);
		writer.Word(item.Attack);
		writer.Word(item.Defense);
		writer.Word(item.Speed);
		writer.Word(item.Slot == "weapon" ? 1 : item.Slot == "armor" ? 2 : 0);
		writer.Word(item.Teaches);
	}

	return writer.ToArray();
}

/// The items without key, name and description (they come from the symbols and the string tables).
Error<List<ItemInfo>> ReadItems(uint8[] data)
{
	var reader = ChunkReader.Of(data);
	var items = List<ItemInfo>.Create();
	int count = try reader.Word();

	for (var i = 0; i < count; i += 1)
	{
		items.Add(ItemInfo
		{
			Id = try reader.Word(), Key = "", Name = "", Description = "", Price = try ReadSigned(ref reader), Heal = try ReadSigned(ref reader),
			Icon = try ReadSigned(ref reader), Attack = try ReadSigned(ref reader), Defense = try ReadSigned(ref reader), Speed = try ReadSigned(ref reader), Slot = SlotName(try reader.Word()), Teaches = try reader.Word()
		});
	}

	return items;
}

uint8[] WriteDeltas(Dictionary<int, DeltaInfo> deltas)
{
	var writer = ChunkWriter.Create();

	writer.Word(deltas.Count());

	foreach (var pair in deltas.Entries())
	{
		var delta = pair.Value;

		writer.Word(pair.Key);
		writer.Word(delta.Tiles.Length);
		writer.Word(delta.UnblockX);
		writer.Word(delta.UnblockY);
		writer.Word(delta.UnblockWidth);
		writer.Word(delta.UnblockHeight);

		foreach (var tile in delta.Tiles)
		{
			writer.Word(tile.Layer);
			writer.Word(tile.X);
			writer.Word(tile.Y);
			writer.Dword((int64)tile.Tile);
		}
	}

	return writer.ToArray();
}

Error<Dictionary<int, DeltaInfo>> ReadDeltas(uint8[] data)
{
	var reader = ChunkReader.Of(data);
	var deltas = Dictionary<int, DeltaInfo>.Create();
	int count = try reader.Word();

	for (var i = 0; i < count; i += 1)
	{
		int id = try reader.Word();
		int tileCount = try reader.Word();
		var delta = DeltaInfo
		{
			Tiles = new DeltaTile[tileCount], UnblockX = try ReadSigned(ref reader), UnblockY = try ReadSigned(ref reader),
			UnblockWidth = try ReadSigned(ref reader), UnblockHeight = try ReadSigned(ref reader)
		};

		for (var j = 0; j < tileCount; j += 1)
			delta.Tiles[j] = DeltaTile { Layer = try ReadSigned(ref reader), X = try reader.Word(), Y = try reader.Word(), Tile = (uint32)(try reader.Dword()) };

		deltas.Set(id, delta);
	}

	return deltas;
}

uint8[] WriteChests(Dictionary<int, ChestInfo> chests)
{
	var writer = ChunkWriter.Create();

	writer.Word(chests.Count());

	foreach (var chest in chests.Values())
	{
		writer.Word(chest.Id);
		writer.Dword((int64)chest.Gold);
		writer.Word(chest.Items.Count());

		foreach (var pair in chest.Items.Entries())
		{
			writer.Word(pair.Key);
			writer.Word(pair.Value);
		}
	}

	return writer.ToArray();
}

Error<Dictionary<int, ChestInfo>> ReadChests(uint8[] data)
{
	var reader = ChunkReader.Of(data);
	var chests = Dictionary<int, ChestInfo>.Create();
	int count = try reader.Word();

	for (var i = 0; i < count; i += 1)
	{
		int id = try reader.Word();
		int gold = try reader.Dword();
		int itemCount = try reader.Word();
		var items = Dictionary<int, int>.Create();

		for (var j = 0; j < itemCount; j += 1)
		{
			int item = try reader.Word();

			items.Set(item, try reader.Word());
		}

		chests.Set(id, ChestInfo { Id = id, Gold = gold, Items = items });
	}

	return chests;
}

uint8[] WriteMonsterGroups(Dictionary<int, MonsterGroupInfo> groups)
{
	var writer = ChunkWriter.Create();

	writer.Word(groups.Count());

	foreach (var group in groups.Values())
	{
		writer.Word(group.Id);
		writer.Word(group.Monsters.Length);

		foreach (var monster in group.Monsters)
		{
			WriteText(writer, monster.Key);
			WriteText(writer, monster.Name);
			writer.Word(monster.Hp);
			writer.Word(monster.Attack);
			writer.Word(monster.Defense);
		}
	}

	return writer.ToArray();
}

Error<Dictionary<int, MonsterGroupInfo>> ReadMonsterGroups(uint8[] data, SymbolTable symbols)
{
	var reader = ChunkReader.Of(data);
	var groups = Dictionary<int, MonsterGroupInfo>.Create();
	int count = try reader.Word();

	for (var i = 0; i < count; i += 1)
	{
		int id = try reader.Word();
		var monsters = new MonsterInfo[try reader.Word()];

		for (var j = 0; j < monsters.Length; j += 1)
		{
			monsters[j] = MonsterInfo
			{
				Key = try ReadText(ref reader), Name = try ReadText(ref reader), Hp = try ReadSigned(ref reader), Attack = try ReadSigned(ref reader),
				Defense = try ReadSigned(ref reader)
			};
		}

		string key = SymbolName(symbols, SymbolKind.MonsterGroup, id);

		groups.Set(id, MonsterGroupInfo { Id = id, Key = key != null ? key : "" + id, Monsters = monsters });
	}

	return groups;
}

uint8[] WriteCharacters(Dictionary<string, string[]> characters)
{
	var writer = ChunkWriter.Create();

	writer.Word(characters.Count());

	foreach (var pair in characters.Entries())
	{
		WriteText(writer, pair.Key);
		writer.Word(pair.Value.Length);

		foreach (var layer in pair.Value)
			WriteText(writer, layer);
	}

	return writer.ToArray();
}

Error<Dictionary<string, string[]>> ReadCharacters(uint8[] data)
{
	var reader = ChunkReader.Of(data);
	var characters = Dictionary<string, string[]>.Create();
	int count = try reader.Word();

	for (var i = 0; i < count; i += 1)
	{
		string name = try ReadText(ref reader);
		var layers = new string[try reader.Word()];

		for (var j = 0; j < layers.Length; j += 1)
			layers[j] = try ReadText(ref reader);

		characters.Set(name, layers);
	}

	return characters;
}

/// The rest of tables.yaml: the hero and the icon sheet.
struct GameInfo
{
	HeroInfo Hero;
	string IconSheet;
}

uint8[] WriteGameInfo(HeroInfo hero, string iconSheet)
{
	var writer = ChunkWriter.Create();

	writer.Word(hero.Hp);
	writer.Word(hero.Attack);
	writer.Word(hero.Defense);
	WriteText(writer, iconSheet);
	WriteText(writer, hero.StartMap);
	writer.Word(hero.StartX + 1);
	writer.Word(hero.StartY + 1);

	return writer.ToArray();
}

Error<GameInfo> ReadGameInfo(uint8[] data)
{
	var reader = ChunkReader.Of(data);
	var hero = HeroInfo { Hp = try ReadSigned(ref reader), Attack = try ReadSigned(ref reader), Defense = try ReadSigned(ref reader), StartMap = "", StartX = -1, StartY = -1 };
	string iconSheet = try ReadText(ref reader);

	if (reader.Remaining() > 0)
	{
		hero.StartMap = try ReadText(ref reader);
		hero.StartX = (try reader.Word()) - 1;
		hero.StartY = (try reader.Word()) - 1;
	}

	return GameInfo { Hero = hero, IconSheet = iconSheet };
}

uint8[] WritePalettes(Dictionary<int, Palette> palettes)
{
	var writer = ChunkWriter.Create();

	writer.Word(palettes.Count());

	foreach (var pair in palettes.Entries())
	{
		var palette = pair.Value;

		writer.Word(pair.Key);
		writer.Word(palette.Size);
		WriteText(writer, palette.Name);
		writer.Bytes(palette.Rgb);

		for (var i = 0; i < palette.Size; i += 1)
			writer.Byte(palette.Used[i] ? 1 : 0);

		writer.Pad();
	}

	return writer.ToArray();
}

Error<Dictionary<int, Palette>> ReadPalettes(uint8[] data)
{
	var reader = ChunkReader.Of(data);
	var palettes = Dictionary<int, Palette>.Create();
	int count = try reader.Word();

	for (var i = 0; i < count; i += 1)
	{
		int id = try reader.Word();
		int size = try reader.Word();

		if (!IsPaletteSize(size))
			return error("A palette of the pack has " + size + " entries.", (int)ErrorKind.InvalidPack);

		var palette = Palette.Create(size, try ReadText(ref reader));
		var rgb = try reader.Bytes(size * 3);

		for (var j = 0; j < size * 3; j += 1)
			palette.Rgb[j] = rgb[j];

		var used = try reader.Bytes(size);

		for (var j = 0; j < size; j += 1)
			palette.Used[j] = used[j] != 0 || j == 0;

		try reader.Pad();
		palettes.Set(id, palette);
	}

	return palettes;
}

uint8[] WriteMapLooks(Dictionary<string, MapLookInfo> looks, Dictionary<string, int> mapIds)
{
	var writer = ChunkWriter.Create();

	writer.Word(looks.Count());

	foreach (var pair in looks.Entries())
	{
		writer.Word(mapIds.GetOrDefault(pair.Key, 0));
		writer.Word(pair.Value.Palette);
		writer.Word(pair.Value.Night);
		writer.Word(pair.Value.Daylight ? 1 : 0);
	}

	return writer.ToArray();
}

/// The looks of the maps by map ID.
Error<Dictionary<int, MapLookInfo>> ReadMapLooks(uint8[] data)
{
	var reader = ChunkReader.Of(data);
	var looks = Dictionary<int, MapLookInfo>.Create();
	int count = try reader.Word();

	for (var i = 0; i < count; i += 1)
	{
		int map = try reader.Word();
		int palette = try reader.Word();
		int night = try reader.Word();
		int flags = try reader.Word();

		looks.Set(map, MapLookInfo { Palette = palette, Night = night, Daylight = (flags & 1) != 0 });
	}

	return looks;
}

uint8[] WriteCompanions(Dictionary<int, CompanionInfo> companions)
{
	var writer = ChunkWriter.Create();

	writer.Word(companions.Count());

	foreach (var companion in companions.Values())
	{
		writer.Word(companion.Id);
		WriteText(writer, companion.Key);
		WriteText(writer, companion.Name);
		WriteText(writer, companion.Role);
		WriteText(writer, companion.Look);
		writer.Word(companion.Hp);
		writer.Word(companion.Attack);
		writer.Word(companion.Defense);
		writer.Word(companion.Range);
		writer.Word(companion.Speed);
		writer.Word(companion.Heal);
		writer.Word(companion.Spells.Length);

		foreach (var spell in companion.Spells)
			writer.Word(spell);
	}

	return writer.ToArray();
}

Error<Dictionary<int, CompanionInfo>> ReadCompanions(uint8[] data)
{
	var reader = ChunkReader.Of(data);
	var companions = Dictionary<int, CompanionInfo>.Create();
	int count = try reader.Word();

	for (var i = 0; i < count; i += 1)
	{
		var companion = CompanionInfo
		{
			Id = try reader.Word(), Key = try ReadText(ref reader), Name = try ReadText(ref reader), Role = try ReadText(ref reader), Look = try ReadText(ref reader),
			Hp = try ReadSigned(ref reader), Attack = try ReadSigned(ref reader), Defense = try ReadSigned(ref reader), Range = try ReadSigned(ref reader),
			Speed = try ReadSigned(ref reader), Heal = try ReadSigned(ref reader), Spells = new int[0]
		};

		companion.Spells = new int[try reader.Word()];

		for (var j = 0; j < companion.Spells.Length; j += 1)
			companion.Spells[j] = try reader.Word();

		companions.Set(companion.Id, companion);
	}

	return companions;
}

string SlotName(int code)
{
	return code == 1 ? "weapon" : code == 2 ? "armor" : "";
}

uint8[] WriteSpells(Dictionary<int, SpellInfo> spells)
{
	var writer = ChunkWriter.Create();

	writer.Word(spells.Count());

	foreach (var spell in spells.Values())
	{
		writer.Word(spell.Id);
		WriteText(writer, spell.Key);
		WriteText(writer, spell.Name);
		WriteText(writer, spell.Kind);
		WriteText(writer, spell.Description);
		writer.Word(spell.Power);
	}

	return writer.ToArray();
}

Error<Dictionary<int, SpellInfo>> ReadSpells(uint8[] data)
{
	var reader = ChunkReader.Of(data);
	var spells = Dictionary<int, SpellInfo>.Create();
	int count = try reader.Word();

	for (var i = 0; i < count; i += 1)
	{
		var spell = SpellInfo
		{
			Id = try reader.Word(), Key = try ReadText(ref reader), Name = try ReadText(ref reader), Kind = try ReadText(ref reader),
			Description = try ReadText(ref reader), Power = try ReadSigned(ref reader)
		};

		spells.Set(spell.Id, spell);
	}

	return spells;
}
