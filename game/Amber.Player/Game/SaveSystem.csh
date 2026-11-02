// Saves and loads the game (spec section 10.2): the global and map state of the scripts, the changes scripts made to the
// maps, the NPCs, the random generator and the clock in a SaveData, the party and the player in its party blob. The blob
// uses names (items, words, chests, the map), not IDs, so it does not depend on the numbering of the tables. The blob is
// written like the C# BinaryWriter (little endian numbers, strings with a 7 bit encoded length), so the savegames of the
// C# prototype load.

namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Pack;
using Amber.Runtime;
using Amber.Script.Common;
using Amber.Script.Compilation;
using Amber.Player.Content;
using Amber.Player.Platform;

/// 3: with the companions, 4: with their gear and spells (versions 2 and 3 are read too).
const uint8 PartyBlobVersion = 4;
const int HiddenFlag = 0x80;

string DefaultSavePath()
{
	return Path.Combine(RepositoryRoot, "game/saves/quick.amsv");
}

/// The game can be saved (and loaded) when nothing is open, no map change is running and no script waits.
bool CanSaveGame(GameSession session)
{
	return !session.Modals.Any() && !session.Fade.Active() && !session.Leaving() && SaveData.CanSave(session.Interpreter());
}

uint8[] CaptureGame(GameSession session)
{
	var interpreter = session.Interpreter();
	var global = StateSnapshot.From(interpreter.Global());
	var save = SaveData.Create(session.Content.LayoutHash, interpreter.RandomState(), (uint16)session.Clock.Day(), (uint16)session.Clock.MinuteOfDay(),
		(uint16)session.Clock.TickInMinute(), global);
	var maps = SortArray(ArrayOf(session.Maps), CompareMapIds);

	foreach (var runtime in maps)
	{
		var state = runtime.Same(session.Current()) ? session.StateOfMap(runtime.MapId) : runtime.SavedState();

		// a map the party has not visited has no state
		if (state is StateStore store)
		{
			var map = MapSave.Create(runtime.MapId, runtime.Name, StateSnapshot.From(store));

			foreach (var change in runtime.World.Map.NetChanges())
				map.TileChanges.Add(TileChange { Layer = change.Layer, X = change.X, Y = change.Y, Tile = change.Tile });

			foreach (var entity in runtime.Script.Entities)
				map.Entities.Add(EntityOf(runtime, entity));

			save.Maps.Add(map);
		}
	}

	save.Party = WriteParty(session);

	return save.Write();
}

int CompareMapIds(MapRuntime a, MapRuntime b)
{
	return CompareInt(a.MapId, b.MapId);
}

EntityState EntityOf(MapRuntime runtime, PackedEntity entity)
{
	int x = 0;
	int y = 0;
	int facing = 0;
	int routine = 0xFFFF;

	if (runtime.World.FindActor(entity.Name) is Actor actor)
	{
		x = actor.TileX();
		y = actor.TileY();
		facing = (int)actor.Facing() | (actor.Visible() ? 0 : HiddenFlag);

		if (runtime.BrainOf(actor) is NpcBrain brain)
			routine = brain.RoutineId() < 0 ? 0xFFFF : brain.RoutineId();
	}

	return EntityState { Id = entity.Id, X = x, Y = y, Facing = facing, Routine = routine };
}

/// Puts the game back to a saved state. Everything is checked before anything changes: a savegame of another version or
/// with unknown names is an InvalidSave error and leaves the game as it is.
Error<void> RestoreGame(GameSession session, uint8[] data)
{
	var save = try SaveData.Read(data);
	var content = session.Content;

	if (save.LayoutHash != content.LayoutHash)
		return error("The savegame is from another version of the scripts (the layout differs).", (int)ErrorKind.InvalidSave);

	var party = try ReadParty(session, save.Party);
	var globalSizes = session.Interpreter().Global().Sizes;

	if (save.Global.FlagCount != globalSizes.Flags || save.Global.Vars.Length != globalSizes.Vars || save.Global.Vars32.Length != globalSizes.Vars32)
		return error("The global state of the savegame has another size.", (int)ErrorKind.InvalidSave);

	foreach (var map in save.Maps)
	{
		if (session.MapById(map.MapId) is MapRuntime runtime)
		{
			if (runtime.Name != map.Name)
				return error("The savegame has the unknown map '" + map.Name + "'.", (int)ErrorKind.InvalidSave);

			if (!StateSizes.Of(map.State.FlagCount, map.State.Vars.Length, map.State.Vars32.Length).Same(runtime.Sizes()))
				return error("The state of the map '" + map.Name + "' has another size.", (int)ErrorKind.InvalidSave);
		}
		else
			return error("The savegame has the unknown map '" + map.Name + "'.", (int)ErrorKind.InvalidSave);
	}

	var targetMap = session.MapByName(party.Map);

	if (targetMap == null)
		return error("The savegame puts the party on the unknown map '" + party.Map + "'.", (int)ErrorKind.InvalidSave);

	var target = session.MapOrCurrent(MapIdOf(targetMap, session));

	try save.Global.RestoreTo(session.Interpreter().Global());
	session.Interpreter().SetRandomState(save.RngState);
	session.Clock.Restore((int)save.Day, (int)save.Minute, (int)save.Tick);

	foreach (var runtime in session.Maps)
	{
		bool restored = false;

		foreach (var map in save.Maps)
		{
			if (map.MapId == runtime.MapId && !restored)
			{
				try RestoreMap(session, runtime, true, map);
				restored = true;
			}
		}

		if (!restored)
			try RestoreMap(session, runtime, false, MapSave.Create(runtime.MapId, runtime.Name, StateSnapshot.Empty(0, 0, 0)));
	}

	session.RestoreChests(party.Chests);
	session.Party.Restore(party.Gold, party.Hp, party.Items, party.Words);

	if (!target.Same(session.Current()))
		try session.SwitchMap(target.MapId, party.X, party.Y, true, party.Facing, -1, false);
	else
	{
		session.Player.PlaceAt(party.X, party.Y);
		session.Player.SetFacing(party.Facing);

		foreach (var bubble in session.Bubbles)
			bubble.Stop();
	}

	// the companions of the savegame, next to the hero
	foreach (var member in ArrayOf(session.Squad.Members))
		session.Squad.Leave(session, member.Info.Id);

	for (var i = 0; i < party.Members.Count(); i += 1)
	{
		var member = party.Members.Get(i);
		var gear = party.Gear.Get(i);

		try session.Squad.Join(session, member.Key, Max(1, member.Value));
		session.Squad.Restore(member.Key, gear.Weapon, gear.Armor, gear.HasSpells, gear.Spells);
	}

	// the party is not arriving on the map, it is where it was: no map_enter, no fade
	session.SetMapEnterPending(false);
	session.View.InvalidateTiles();

	return;
}

Error<void> RestoreMap(GameSession session, MapRuntime runtime, bool hasSaved, MapSave saved)
{
	runtime.World.Map.ResetChanges();

	foreach (var entity in runtime.Script.Entities)
	{
		if (runtime.World.FindActor(entity.Name) is Actor actor)
		{
			actor.PlaceAt(entity.X, entity.Y);
			actor.SetFacing(Direction.Down);
			actor.SetVisible(true);

			if (runtime.BrainOf(actor) is NpcBrain brain)
				brain.SetRoutine(runtime.RoutineOfEntity(entity.Id));
		}
	}

	if (hasSaved)
	{
		foreach (var change in saved.TileChanges)
			runtime.World.Map.Apply(change.Layer, change.X, change.Y, change.Tile);

		foreach (var state in saved.Entities)
		{
			if (runtime.World.FindActorById(state.Id) is Actor actor)
			{
				actor.PlaceAt(state.X, state.Y);
				actor.SetFacing((Direction)(state.Facing & ~HiddenFlag));
				actor.SetVisible((state.Facing & HiddenFlag) == 0);

				if (runtime.BrainOf(actor) is NpcBrain brain)
				{
					if (state.Routine == 0xFFFF)
						brain.SetRoutine(null);
					else
						brain.SetRoutine(runtime.RoutineById(state.Routine));
				}
			}
		}
	}

	if (runtime.Same(session.Current()))
	{
		var sizes = runtime.Sizes();
		var snapshot = hasSaved ? saved.State : StateSnapshot.Empty(sizes.Flags, sizes.Vars, sizes.Vars32);

		if (session.StateOfMap(runtime.MapId) is StateStore store)
			try snapshot.RestoreTo(store);
	}
	else if (hasSaved)
		runtime.SetSavedState(saved.State.ToStore());
	else
		runtime.SetSavedState(null);

	return;
}

int MapIdOf(Optional<MapRuntime> map, GameSession session)
{
	if (map is MapRuntime runtime)
		return runtime.MapId;

	return session.MapId();
}

/// The names of the symbols by kind and ID (C#: SymbolNames).
string SymbolName(GameSession session, SymbolKind kind, int id)
{
	foreach (var pair in session.Content.Symbols.Ids.Entries())
	{
		if (pair.Key.Kind == kind && (int)pair.Value == id)
			return pair.Key.Name;
	}

	return "";
}

uint8[] WriteParty(GameSession session)
{
	var content = session.Content;
	var player = session.Player;
	var writer = LittleEndianWriter.Create();
	var party = session.Party;

	writer.Byte((int)PartyBlobVersion);
	writer.Int(party.Gold());
	writer.Int(party.Hp());
	writer.UShort(party.Items().Count());

	foreach (var id in party.Items().Keys())
	{
		writer.Text(content.Items.GetOrDefault(id, new ItemInfo()).Key);
		writer.Int(party.Items().Get(id));
	}

	writer.UShort(party.KnownWords().Count());

	foreach (var word in party.KnownWords())
		writer.Text(SymbolName(session, SymbolKind.Keyword, word));

	writer.UShort(session.Chests.Count());

	foreach (var pair in session.Chests.Entries())
	{
		writer.Text(SymbolName(session, SymbolKind.Chest, pair.Key));
		writer.Int(pair.Value.Gold());
		writer.UShort(pair.Value.Items().Count());

		foreach (var item in pair.Value.Items().Keys())
		{
			writer.Text(content.Items.GetOrDefault(item, new ItemInfo()).Key);
			writer.Int(pair.Value.Items().Get(item));
		}
	}

	writer.Text(session.Current().Name);
	writer.Int(player.TileX());
	writer.Int(player.TileY());
	writer.Byte((int)player.Facing());
	writer.UShort(session.Squad.Members.Count());

	foreach (var member in session.Squad.Members)
	{
		writer.Text(member.Info.Key);
		writer.Int(member.Hp);
		writer.Text(member.Weapon > 0 ? content.Items.GetOrDefault(member.Weapon, new ItemInfo()).Key : "");
		writer.Text(member.Armor > 0 ? content.Items.GetOrDefault(member.Armor, new ItemInfo()).Key : "");
		writer.UShort(member.Spells.Count());

		foreach (var spell in member.Spells)
			writer.Text(SymbolName(session, SymbolKind.Spell, spell));
	}

	return writer.ToArray();
}

struct PartyState
{
	int Gold;
	int Hp;
	List<IntPair2> Items;
	List<int> Words;
	Dictionary<int, Chest> Chests;
	string Map;
	int X;
	int Y;
	Direction Facing;
	/// The companions (symbol ID and hit points) with their gear and spells.
	List<IntPair2> Members;
	List<SavedGear> Gear;
}

struct SavedGear
{
	int Weapon;
	int Armor;
	bool HasSpells;
	List<int> Spells;
}

/// An item of the savegame by its key, 0 for "" (none).
Error<int> SavedItem(GameSession session, string key)
{
	if (key.Length == 0)
		return 0;

	return ResolveSaved(session, SymbolKind.Item, key);
}

Error<int> ResolveSaved(GameSession session, SymbolKind kind, string name)
{
	if (session.Content.Symbols.TryResolve(kind, name) is uint16 id)
		return (int)id;

	return error("The savegame knows '" + name + "', which the game does not have any more.", (int)ErrorKind.InvalidSave);
}

Error<PartyState> ReadParty(GameSession session, uint8[] blob)
{
	var reader = LittleEndianReader.Of(blob);

	int version = (int)(try reader.Byte());

	if (version < 2 || version > (int)PartyBlobVersion)
		return error("The party data of the savegame has an unknown version.", (int)ErrorKind.InvalidSave);

	var party = PartyState { Items = List<IntPair2>.Create(), Words = List<int>.Create(), Chests = Dictionary<int, Chest>.Create(), Members = List<IntPair2>.Create(), Gear = List<SavedGear>.Create() };

	party.Gold = try reader.Int();
	party.Hp = try reader.Int();

	for (var i = try reader.UShort(); i > 0; i -= 1)
		party.Items.Add(IntPair2 { Key = try ResolveSaved(session, SymbolKind.Item, try reader.Text()), Value = try reader.Int() });

	for (var i = try reader.UShort(); i > 0; i -= 1)
		party.Words.Add(try ResolveSaved(session, SymbolKind.Keyword, try reader.Text()));

	for (var i = try reader.UShort(); i > 0; i -= 1)
	{
		int chestId = try ResolveSaved(session, SymbolKind.Chest, try reader.Text());
		int chestGold = try reader.Int();
		var chestItems = List<IntPair2>.Create();

		for (var n = try reader.UShort(); n > 0; n -= 1)
			chestItems.Add(IntPair2 { Key = try ResolveSaved(session, SymbolKind.Item, try reader.Text()), Value = try reader.Int() });

		party.Chests.Set(chestId, Chest.Create(chestGold, chestItems));
	}

	party.Map = try reader.Text();
	party.X = try reader.Int();
	party.Y = try reader.Int();

	int facing = try reader.Byte();

	if (facing > (int)Direction.Left)
		return error("The savegame has an invalid facing.", (int)ErrorKind.InvalidSave);

	party.Facing = (Direction)facing;

	if (version >= 3)
	{
		for (var i = try reader.UShort(); i > 0; i -= 1)
		{
			party.Members.Add(IntPair2 { Key = try ResolveSaved(session, SymbolKind.Character, try reader.Text()), Value = try reader.Int() });

			var gear = SavedGear { Weapon = 0, Armor = 0, HasSpells = version >= 4, Spells = List<int>.Create() };

			if (version >= 4)
			{
				gear.Weapon = try SavedItem(session, try reader.Text());
				gear.Armor = try SavedItem(session, try reader.Text());

				for (var n = try reader.UShort(); n > 0; n -= 1)
					gear.Spells.Add(try ResolveSaved(session, SymbolKind.Spell, try reader.Text()));
			}

			party.Gear.Add(gear);
		}
	}

	return party;
}

/// C#: BinaryWriter (little endian, 7 bit encoded string lengths).
struct LittleEndianWriter
{
	ByteWriter _bytes;

	static LittleEndianWriter Create()
	{
		return LittleEndianWriter { _bytes = ByteWriter.Create() };
	}

	void Byte(int value)
	{
		_bytes.Byte(value);
	}

	void UShort(int value)
	{
		_bytes.Byte(value);
		_bytes.Byte(value >> 8);
	}

	void Int(int value)
	{
		_bytes.Byte(value);
		_bytes.Byte(value >> 8);
		_bytes.Byte(value >> 16);
		_bytes.Byte(value >> 24);
	}

	void Text(string text)
	{
		var bytes = Utf8Bytes(text);
		int length = bytes.Length;

		while (length >= 0x80)
		{
			_bytes.Byte((length & 0x7F) | 0x80);
			length = length >> 7;
		}

		_bytes.Byte(length);
		_bytes.Bytes(bytes);
	}

	uint8[] ToArray()
	{
		return _bytes.ToArray();
	}
}

/// C#: BinaryReader; reading past the end is an InvalidSave error ("truncated").
struct LittleEndianReader
{
	uint8[] _data;
	int[] _position;

	static LittleEndianReader Of(uint8[] data)
	{
		return LittleEndianReader { _data = data, _position = new int[1] };
	}

	Error<void> Need(int count)
	{
		if (_data == null || _position[0] + count > _data.Length)
			return error("The party data of the savegame is truncated.", (int)ErrorKind.InvalidSave);

		return;
	}

	Error<int> Byte()
	{
		try Need(1);

		int value = (int)_data[_position[0]];

		_position[0] += 1;

		return value;
	}

	Error<int> UShort()
	{
		try Need(2);

		int value = (int)_data[_position[0]] | ((int)_data[_position[0] + 1] << 8);

		_position[0] += 2;

		return value;
	}

	Error<int> Int()
	{
		try Need(4);

		int at = _position[0];
		int value = (int)_data[at] | ((int)_data[at + 1] << 8) | ((int)_data[at + 2] << 16) | ((int)_data[at + 3] << 24);

		_position[0] += 4;

		return value;
	}

	Error<string> Text()
	{
		int length = 0;
		int shift = 0;

		while (true)
		{
			int part = try Byte();

			length = length | ((part & 0x7F) << shift);
			shift += 7;

			if ((part & 0x80) == 0)
				break;
		}

		try Need(length);

		string text = Utf8String(Slice(_data, _position[0], length));

		_position[0] += length;

		return text;
	}
}
