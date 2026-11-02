namespace Amber.Pack;

using System;
using Amber.Base;
using Amber.Runtime;
using Amber.Script.Common;

/// The values of one state namespace instance (global or one map): the flags as bytes, the variables and the 32 bit
/// variables. A handle: copies share the arrays.
struct StateSnapshot
{
	int FlagCount;
	uint8[] FlagBytes;
	int16[] Vars;
	int32[] Vars32;

	static StateSnapshot Empty(int flags, int vars, int vars32)
	{
		return StateSnapshot { FlagCount = flags, FlagBytes = new uint8[(flags + 7) / 8], Vars = new int16[vars], Vars32 = new int32[vars32] };
	}

	static StateSnapshot From(StateStore store)
	{
		var snapshot = Empty(store.Sizes.Flags, store.Sizes.Vars, store.Sizes.Vars32);

		for (var i = 0; i < store.Sizes.Flags; i += 1)
			snapshot.SetFlag(i, store.GetFlag(i));

		for (var i = 0; i < store.Sizes.Vars; i += 1)
			snapshot.Vars[i] = store.GetVar(i);

		for (var i = 0; i < store.Sizes.Vars32; i += 1)
			snapshot.Vars32[i] = store.GetVar32(i);

		return snapshot;
	}

	bool GetFlag(int index)
	{
		return ((int)FlagBytes[index >> 3] & (1 << (index & 7))) != 0;
	}

	void SetFlag(int index, bool value)
	{
		if (value)
			FlagBytes[index >> 3] = (uint8)((int)FlagBytes[index >> 3] | (1 << (index & 7)));
		else
			FlagBytes[index >> 3] = (uint8)((int)FlagBytes[index >> 3] & ~(1 << (index & 7)));
	}

	/// Puts the values into a state store of the same size (a loaded map, the global state). No flag_changed events are
	/// raised: the state is restored, not changed.
	Error<void> RestoreTo(StateStore store)
	{
		if (!store.Sizes.Same(StateSizes.Of(FlagCount, Vars.Length, Vars32.Length)))
			return error("The saved state does not have the size of the state it is restored to.", (int)ErrorKind.InvalidSave);

		for (var i = 0; i < FlagCount; i += 1)
			store.SetFlag(i, GetFlag(i));

		for (var i = 0; i < Vars.Length; i += 1)
			store.SetVar(i, Vars[i]);

		for (var i = 0; i < Vars32.Length; i += 1)
			store.SetVar32(i, Vars32[i]);

		return;
	}

	StateStore ToStore()
	{
		var store = StateStore.Create(StateSizes.Of(FlagCount, Vars.Length, Vars32.Length));

		RestoreTo(store);

		return store;
	}
}

/// A tile which a script changed (set_tile, apply_delta): the change is saved, not the whole map.
struct TileChange
{
	int Layer;
	int X;
	int Y;
	uint32 Tile;
}

/// Where an entity (NPC) is and what it does.
struct EntityState
{
	int Id;
	int X;
	int Y;
	int Facing;
	int Routine;
}

/// The saved state of one visited map. The name identifies it across releases, the ID is the one of the pack it was saved
/// with.
struct MapSave
{
	int MapId;
	string Name;
	StateSnapshot State;
	List<TileChange> TileChanges;
	List<EntityState> Entities;

	static MapSave Create(int mapId, string name, StateSnapshot state)
	{
		return MapSave { MapId = mapId, Name = name, State = state, TileChanges = List<TileChange>.Create(), Entities = List<EntityState>.Create() };
	}
}

const uint16 SaveCurrentVersion = 0;
const string SaveMagic = "AMSV";

/// The content of a savegame (spec section 10.2). No thread state is saved: the game saves when no script waits (CanSave)
/// or at the end of a chain (autosave).
struct SaveData
{
	uint16 Version;
	/// The layout hash of the pack the game was saved with.
	uint32 LayoutHash;
	uint32 RngState;
	uint16 Day;
	uint16 Minute;
	uint16 Tick;
	StateSnapshot Global;
	List<MapSave> Maps;
	/// The party, written by the game (characters, inventories, gold, rations).
	uint8[] Party;

	static SaveData Create(uint32 layoutHash, uint32 rngState, uint16 day, uint16 minute, uint16 tick, StateSnapshot global)
	{
		return SaveData
		{
			Version = SaveCurrentVersion, LayoutHash = layoutHash, RngState = rngState, Day = day, Minute = minute, Tick = tick, Global = global,
			Maps = List<MapSave>.Create(), Party = new uint8[0]
		};
	}

	/// True if no script thread is running or waiting, so the game may be saved.
	static bool CanSave(Interpreter interpreter)
	{
		return interpreter.ActiveThreadCount() == 0;
	}

	/// "AMSV", u16 version, u16 reserved, u32 layoutHash, u32 rngState, u16 day, u16 minute, u16 tick, the global snapshot,
	/// u16 mapCount and the maps, u32 partyLen with the party bytes, and at the end the CRC-32 of everything before. A
	/// snapshot is u16 flags, u16 vars, u16 vars32, the flag bytes (padded to an even count), the variables (i16) and the 32
	/// bit variables (i32). A map is u16 id, u16 nameLen, the name (padded), the snapshot, u32 tileChangeCount with u8 layer,
	/// u8 reserved, u16 x, u16 y, u32 tile each, and u16 entityCount with u16 id, u16 x, u16 y, u8 facing, u8 reserved,
	/// u16 routine each. All numbers are big endian.
	uint8[] Write()
	{
		var writer = ChunkWriter.Create();

		writer.Bytes(AsciiBytes(SaveMagic));
		writer.Word((int)Version);
		writer.Word(0);
		writer.Dword((int64)LayoutHash);
		writer.Dword((int64)RngState);
		writer.Word((int)Day);
		writer.Word((int)Minute);
		writer.Word((int)Tick);
		WriteSnapshot(writer, Global);
		writer.Word(Maps.Count());

		foreach (var map in Maps)
		{
			writer.Word(map.MapId);
			writer.Word(Latin1Length(map.Name));
			writer.PaddedText(map.Name);
			WriteSnapshot(writer, map.State);
			writer.Dword((int64)map.TileChanges.Count());

			foreach (var change in map.TileChanges)
			{
				writer.Byte(change.Layer);
				writer.Byte(0);
				writer.Word(change.X);
				writer.Word(change.Y);
				writer.Dword((int64)change.Tile);
			}

			writer.Word(map.Entities.Count());

			foreach (var entity in map.Entities)
			{
				writer.Word(entity.Id);
				writer.Word(entity.X);
				writer.Word(entity.Y);
				writer.Byte(entity.Facing);
				writer.Byte(0);
				writer.Word(entity.Routine);
			}
		}

		writer.Dword((int64)Party.Length);
		writer.Bytes(Party);

		var body = writer.ToArray();
		var result = new uint8[body.Length + 4];

		Array.Copy(body, 0, result, 0, body.Length);
		WriteU32(result, body.Length, (int64)Crc32Of(body));

		return result;
	}

	static Error<SaveData> Read(uint8[] data)
	{
		if (data.Length < 8 + 4 || !StartsWithAscii(data, SaveMagic))
			return error("The file is not a savegame.", (int)ErrorKind.InvalidSave);

		var body = Slice(data, 0, data.Length - 4);

		if (Crc32Of(body) != ReadU32(data, data.Length - 4))
			return error("The savegame is damaged (checksum mismatch).", (int)ErrorKind.InvalidSave);

		var result = ReadBody(body);

		if (result is SaveData save)
			return save;

		if (result.Code == (int)ErrorKind.InvalidSave)
			return error(result.Message, result.Code);

		return error("The savegame is truncated: " + result.Message, (int)ErrorKind.InvalidSave);
	}

	static Error<SaveData> ReadBody(uint8[] body)
	{
		var reader = ChunkReader.Of(body);

		try reader.Bytes(4);

		uint16 version = (uint16)try reader.Word();

		if (version != SaveCurrentVersion)
			return error("The savegame version " + version + " is not supported.", (int)ErrorKind.InvalidSave);

		try reader.Word();

		uint32 layoutHash = (uint32)try reader.Dword();
		uint32 rng = (uint32)try reader.Dword();
		uint16 day = (uint16)try reader.Word();
		uint16 minute = (uint16)try reader.Word();
		uint16 tick = (uint16)try reader.Word();
		var global = try ReadSnapshot(ref reader);
		int mapCount = try reader.Word();
		var maps = List<MapSave>.Create();

		for (var i = 0; i < mapCount; i += 1)
		{
			int id = try reader.Word();
			string name = try reader.PaddedText(try reader.Word());
			var map = MapSave.Create(id, name, try ReadSnapshot(ref reader));
			int changes = try reader.Dword();

			for (var c = 0; c < changes; c += 1)
			{
				int layer = (int)try reader.Byte();

				try reader.Byte();

				int x = try reader.Word();
				int y = try reader.Word();

				map.TileChanges.Add(TileChange { Layer = layer, X = x, Y = y, Tile = (uint32)try reader.Dword() });
			}

			int entityCount = try reader.Word();

			for (var e = 0; e < entityCount; e += 1)
			{
				int entityId = try reader.Word();
				int x = try reader.Word();
				int y = try reader.Word();
				int facing = (int)try reader.Byte();

				try reader.Byte();
				map.Entities.Add(EntityState { Id = entityId, X = x, Y = y, Facing = facing, Routine = try reader.Word() });
			}

			maps.Add(map);
		}

		var party = try reader.Bytes(try reader.Dword());
		var save = Create(layoutHash, rng, day, minute, tick, global);

		save.Version = version;
		save.Maps = maps;
		save.Party = party;

		return save;
	}

	static void WriteSnapshot(ChunkWriter writer, StateSnapshot snapshot)
	{
		writer.Word(snapshot.FlagCount);
		writer.Word(snapshot.Vars.Length);
		writer.Word(snapshot.Vars32.Length);
		writer.Bytes(snapshot.FlagBytes);

		if (snapshot.FlagBytes.Length % 2 != 0)
			writer.Byte(0);

		foreach (var value in snapshot.Vars)
			writer.Word((int)value);

		foreach (var value in snapshot.Vars32)
			writer.Dword((int64)value);
	}

	static Error<StateSnapshot> ReadSnapshot(ref ChunkReader reader)
	{
		int flags = try reader.Word();
		int vars = try reader.Word();
		int vars32 = try reader.Word();
		var snapshot = StateSnapshot.Empty(flags, vars, vars32);
		var flagBytes = try reader.Bytes(snapshot.FlagBytes.Length);

		Array.Copy(flagBytes, 0, snapshot.FlagBytes, 0, flagBytes.Length);

		if (snapshot.FlagBytes.Length % 2 != 0)
			try reader.Bytes(1);

		for (var i = 0; i < vars; i += 1)
			snapshot.Vars[i] = (int16)try reader.Word();

		for (var i = 0; i < vars32; i += 1)
			snapshot.Vars32[i] = try reader.Dword();

		return snapshot;
	}
}
