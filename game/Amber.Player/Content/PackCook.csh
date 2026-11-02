// Cooks the content folder of the prototype into the pack the game runs from (scripts, maps with their baked routines,
// screens, natives, layout, symbols, texts and the tables of the game, see GameTables) and checks that the pack loads and
// matches the content. The Tiled maps and the pictures are still read from their files.

namespace Amber.Player.Content.PackCook;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Cook;
using Amber.Pack;
using Amber.Script.Common;
using Amber.Player.Content;
using Amber.Player.Game;

Error<uint8[]> Cook(ContentSource content)
{
	var builder = PackBuilder.Create(content.Compilation);
	var texts = Dictionary<int, string>.Create();
	var speakers = Dictionary<int, string>.Create();
	var names = Dictionary<int, string>.Create();
	var descriptions = Dictionary<int, string>.Create();

	builder.Screens = content.Screens;

	foreach (var pair in content.Texts.Entries())
	{
		texts.Set(pair.Key, pair.Value.Text);

		if (pair.Value.Speaker.Length > 0)
			speakers.Set(pair.Key, pair.Value.Speaker);
	}

	foreach (var pair in content.Items.Entries())
	{
		names.Set(pair.Key, pair.Value.Name);
		descriptions.Set(pair.Key, pair.Value.Description);
	}

	builder.AddTexts(0, texts);
	try builder.AddStringTable(SpeakerTable, speakers);
	try builder.AddStringTable(KeywordTable, content.Keywords);
	try builder.AddStringTable(ItemNameTable, names);
	try builder.AddStringTable(ItemDescriptionTable, descriptions);

	var places = Dictionary<int, string>.Create();

	foreach (var pair in content.Places.Entries())
		places.Set(content.MapIds.GetOrDefault(pair.Key, 0), pair.Value);

	try builder.AddStringTable(PlaceTable, places);

	// the YAML files: the screens and prefabs, the theme
	var fileTexts = Dictionary<int, string>.Create();
	var fileNames = List<NamedId>.Create();

	foreach (var file in content.Screens.Files)
	{
		fileTexts.Set(fileNames.Count(), file.Text);
		fileNames.Add(NamedId { Kind = ScreenFileKind, Id = (uint16)fileNames.Count(), Name = Path.GetFileName(file.Path).ToString() });
	}

	if (content.ThemeText != null)
	{
		fileTexts.Set(fileNames.Count(), content.ThemeText);
		fileNames.Add(NamedId { Kind = ThemeFile, Id = (uint16)fileNames.Count(), Name = "ui.yaml" });
	}

	try builder.AddStringTable(FileTextTable, fileTexts);

	var groupNames = List<NamedId>.Create();
	var result = content.Compilation;

	foreach (var pair in result.Global.GroupRefs.Entries())
		groupNames.Add(NamedId { Kind = GlobalGroupName, Id = pair.Value, Name = pair.Key });

	foreach (var screen in result.Screens)
	{
		groupNames.Add(NamedId { Kind = ScriptedScreenName, Id = 0, Name = screen.Name });

		foreach (var pair in screen.GroupRefs.Entries())
			groupNames.Add(NamedId { Kind = ScreenGroupName, Id = pair.Value, Name = screen.Name + "/" + pair.Key });
	}

	try builder.AddTable(GroupNameTable, NamedId.Write(groupNames));
	try builder.AddTable(FileNameTable, NamedId.Write(fileNames));
	try builder.AddTable(ItemTable, WriteItems(content.Items));
	try builder.AddTable(DeltaTable, WriteDeltas(content.Deltas));
	try builder.AddTable(ChestTable, WriteChests(content.Chests));
	try builder.AddTable(MonsterGroupTable, WriteMonsterGroups(content.Groups));
	try builder.AddTable(CharacterTable, WriteCharacters(content.Characters));
	try builder.AddTable(GameInfoTable, WriteGameInfo(content.Hero, content.IconSheet));
	try builder.AddTable(PaletteTable, WritePalettes(content.Palettes));
	try builder.AddTable(MapLookTable, WriteMapLooks(content.MapLooks, content.MapIds));
	try builder.AddTable(CompanionTable, WriteCompanions(content.Companions));
	try builder.AddTable(SpellTable, WriteSpells(content.Spells));

	var data = try builder.Build();

	foreach (var warning in builder.Warnings)
		Console.WriteErrorLine("pack: " + warning);

	return data;
}

/// Loads the pack like the game would (load check of the natives, layout, texts, maps, screens) and compares it with the
/// content. The first difference is the error.
Error<string> Verify(ContentSource content, uint8[] data)
{
	var reader = try PackReader.FromMemory(data);
	var pack = PackContent.Of(reader);
	var result = content.Compilation;

	try pack.RequireNativesWith(ImplementsNative);

	if ((try pack.Layout()).Hash() != pack.Header().LayoutHash || pack.Header().LayoutHash != result.LayoutHash)
		return error("The layout of the pack does not match the compiled scripts.", (int)ErrorKind.InvalidData);

	var texts = Dictionary<int, string>.Create();

	foreach (var pair in content.Texts.Entries())
		texts.Set(pair.Key, pair.Value.Text);

	if (!SameStrings(try pack.Texts(0), texts))
		return error("The texts of the pack differ from the content.", (int)ErrorKind.InvalidData);

	if (!SameStrings(try pack.Strings(KeywordTable), content.Keywords))
		return error("The keywords of the pack differ from the content.", (int)ErrorKind.InvalidData);

	foreach (var map in result.Maps)
	{
		var packed = try pack.LoadMap(content.MapIds.GetOrDefault(map.Name, -1));

		if (packed.Name != map.Name || !SameBytes(packed.Script.Groups, map.GroupsChunk.Get()) || !SameBytes(packed.Script.Bindings, map.BindingsChunk.Get()))
			return error("The map '" + map.Name + "' of the pack differs from the compiled script.", (int)ErrorKind.InvalidData);

		if (!SameRoutines(packed.Routines, try RoutineBaker.Bake(map)))
			return error("The routines of the map '" + map.Name + "' in the pack differ from the ones the game runs.", (int)ErrorKind.InvalidData);
	}

	foreach (var screen in content.Screens.Screens.Keys())
	{
		if (!reader.Contains(PackChunkType.Screen, content.ScreenId(screen)))
			return error("The screen '" + screen + "' is not in the pack.", (int)ErrorKind.InvalidData);
	}

	// the game reads the pack with GameContent.FromPack: what it gets has to be the content
	try SameAsSource(content, try GameContent.FromPack(data, ""));

	return "" + data.Length + " bytes, " + reader.Header.TocCount + " chunks (" + result.Maps.Count() + " maps, " + pack.ScreenIds().Count()
		+ " screens), " + (try pack.Natives()).Count() + " natives, layout hash 0x" + Hex((uint64)pack.Header().LayoutHash, 8);
}

/// The same entries in the same order (C#: SequenceEqual of two dictionaries).
bool SameStrings(Dictionary<int, string> a, Dictionary<int, string> b)
{
	var first = a.Entries();
	var second = b.Entries();

	if (first.Length != second.Length)
		return false;

	for (var i = 0; i < first.Length; i += 1)
	{
		if (first[i].Key != second[i].Key || first[i].Value != second[i].Value)
			return false;
	}

	return true;
}

bool SameRoutines(PackedRoutine[] packed, List<PackedRoutine> baked)
{
	if (packed.Length != baked.Count())
		return false;

	for (var i = 0; i < packed.Length; i += 1)
	{
		var first = packed[i];
		var second = baked.Get(i);

		if (first.Name != second.Name || first.EntityId != second.EntityId || first.Entries.Length != second.Entries.Length)
			return false;

		for (var j = 0; j < first.Entries.Length; j += 1)
		{
			var a = first.Entries[j];
			var b = second.Entries[j];

			if (a.Minute != b.Minute || a.Steps.Length != b.Steps.Length)
				return false;

			for (var k = 0; k < a.Steps.Length; k += 1)
			{
				if (a.Steps[k].Kind != b.Steps[k].Kind || a.Steps[k].Target != b.Steps[k].Target || a.Steps[k].Ticks != b.Steps[k].Ticks)
					return false;
			}
		}
	}

	return true;
}

/// The tables the game reads from the pack are the ones of the content folder; the first difference is the error.
Error<void> SameAsSource(ContentSource source, GameContent game)
{
	if (game.Items.Count() != source.Items.Count() || game.Deltas.Count() != source.Deltas.Count() || game.Chests.Count() != source.Chests.Count()
		|| game.Groups.Count() != source.Groups.Count() || game.Characters.Count() != source.Characters.Count() || game.Places.Count() != source.Places.Count()
		|| game.Texts.Count() != source.Texts.Count() || game.Maps.Count() != source.Compilation.Maps.Count())
		return Difference("the number of entries of a table");

	foreach (var item in source.Items.Values())
	{
		var read = game.Items.GetOrDefault(item.Id, new ItemInfo());

		if (read.Key != item.Key || read.Name != item.Name || read.Description != item.Description || read.Price != item.Price || read.Heal != item.Heal
			|| read.Icon != item.Icon || read.Attack != item.Attack || read.Defense != item.Defense || read.Speed != item.Speed || read.Slot != item.Slot || read.Teaches != item.Teaches)
			return Difference("the item " + item.Key);
	}

	foreach (var pair in source.Texts.Entries())
	{
		var read = game.Texts.GetOrDefault(pair.Key, new TextInfo());

		if (read.Text != pair.Value.Text || read.Speaker != pair.Value.Speaker)
			return Difference("the text " + pair.Key);
	}

	foreach (var pair in source.Deltas.Entries())
	{
		var delta = pair.Value;
		var read = game.Deltas.GetOrDefault(pair.Key, new DeltaInfo());

		if (read.Tiles == null || read.Tiles.Length != delta.Tiles.Length || read.UnblockX != delta.UnblockX || read.UnblockY != delta.UnblockY
			|| read.UnblockWidth != delta.UnblockWidth || read.UnblockHeight != delta.UnblockHeight)
			return Difference("the delta " + pair.Key);

		for (var i = 0; i < delta.Tiles.Length; i += 1)
		{
			var a = delta.Tiles[i];
			var b = read.Tiles[i];

			if (a.Layer != b.Layer || a.X != b.X || a.Y != b.Y || a.Tile != b.Tile)
				return Difference("a tile of the delta " + pair.Key);
		}
	}

	foreach (var chest in source.Chests.Values())
	{
		if (game.Chests.TryGet(chest.Id) is not ChestInfo read)
			return Difference("the chest " + chest.Id);

		var items = chest.Items.Entries();

		if (read.Gold != chest.Gold || read.Items.Count() != items.Length)
			return Difference("the chest " + chest.Id);

		var readItems = read.Items.Entries();

		for (var i = 0; i < items.Length; i += 1)
		{
			if (readItems[i].Key != items[i].Key || readItems[i].Value != items[i].Value)
				return Difference("the items of the chest " + chest.Id);
		}
	}

	foreach (var group in source.Groups.Values())
	{
		var read = game.Groups.GetOrDefault(group.Id, new MonsterGroupInfo());

		if (read.Monsters == null || read.Key != group.Key || read.Monsters.Length != group.Monsters.Length)
			return Difference("the monster group " + group.Key);

		for (var i = 0; i < group.Monsters.Length; i += 1)
		{
			var a = group.Monsters[i];
			var b = read.Monsters[i];

			if (a.Key != b.Key || a.Name != b.Name || a.Hp != b.Hp || a.Attack != b.Attack || a.Defense != b.Defense)
				return Difference("a monster of the group " + group.Key);
		}
	}

	foreach (var pair in source.Characters.Entries())
	{
		var read = game.Characters.GetOrDefault(pair.Key, new string[0]);

		if (read.Length != pair.Value.Length)
			return Difference("the character " + pair.Key);

		for (var i = 0; i < read.Length; i += 1)
		{
			if (read[i] != pair.Value[i])
				return Difference("a layer of the character " + pair.Key);
		}
	}

	foreach (var pair in source.Places.Entries())
	{
		if (game.Places.GetOrDefault(pair.Key, "") != pair.Value || game.MapIds.GetOrDefault(pair.Key, -1) != source.MapIds.GetOrDefault(pair.Key, -2))
			return Difference("the map " + pair.Key);
	}

	foreach (var pair in source.MapLooks.Entries())
	{
		var look = game.MapLooks.GetOrDefault(pair.Key, MapLookInfo { Palette = -1 });

		if (look.Palette != pair.Value.Palette || look.Night != pair.Value.Night || look.Daylight != pair.Value.Daylight)
			return Difference("the look of the map " + pair.Key);
	}

	foreach (var pair in source.Palettes.Entries())
	{
		if (game.Palettes.TryGet(pair.Key) is not Palette read)
			return Difference("the palette " + pair.Value.Name);

		if (PaletteToGpl(read) != PaletteToGpl(pair.Value))
			return Difference("the palette " + pair.Value.Name);
	}

	foreach (var companion in source.Companions.Values())
	{
		if (game.Companions.TryGet(companion.Id) is not CompanionInfo read)
			return Difference("the companion " + companion.Key);

		if (read.Key != companion.Key || read.Name != companion.Name || read.Role != companion.Role || read.Look != companion.Look || read.Hp != companion.Hp
			|| read.Attack != companion.Attack || read.Defense != companion.Defense || read.Range != companion.Range || read.Speed != companion.Speed
			|| read.Heal != companion.Heal || read.Spells.Length != companion.Spells.Length)
			return Difference("the companion " + companion.Key);

		for (var i = 0; i < companion.Spells.Length; i += 1)
		{
			if (read.Spells[i] != companion.Spells[i])
				return Difference("the spells of the companion " + companion.Key);
		}
	}

	foreach (var spell in source.Spells.Values())
	{
		if (game.Spells.TryGet(spell.Id) is not SpellInfo read)
			return Difference("the spell " + spell.Key);

		if (read.Key != spell.Key || read.Name != spell.Name || read.Kind != spell.Kind || read.Power != spell.Power || read.Description != spell.Description)
			return Difference("the spell " + spell.Key);
	}

	if (game.Hero.Hp != source.Hero.Hp || game.Hero.Attack != source.Hero.Attack || game.Hero.Defense != source.Hero.Defense
		|| game.Hero.StartMap != source.Hero.StartMap || game.Hero.StartX != source.Hero.StartX || game.Hero.StartY != source.Hero.StartY)
		return Difference("the hero");

	foreach (var screen in source.Screens.Screens.Keys())
	{
		if (game.Screens.Find(screen) == null || game.ScreenId(screen) != source.ScreenId(screen))
			return Difference("the screen " + screen);
	}

	if (game.Screens.Screens.Count() != source.Screens.Screens.Count() || game.ScreenScripts.Count() != source.Compilation.Screens.Count()
		|| game.GlobalGroups.Count() != source.Compilation.Global.GroupRefs.Count() || (source.ThemeText != null) != (game.Theme.Looks.Count() > 0 || game.Theme.Sprites.Count() > 0))
		return Difference("the screens, their scripts or the theme");

	return;
}

Error<void> Difference(string what)
{
	return error("The pack differs from the content: " + what + ".", (int)ErrorKind.InvalidData);
}
