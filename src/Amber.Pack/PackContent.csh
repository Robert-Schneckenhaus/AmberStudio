namespace Amber.Pack;

using System;
using Amber.Base;
using Amber.Runtime;
using Amber.Screens;
using Amber.Script.Common;

/// An entity of a map chunk (an NPC or another actor with its start position).
struct PackedEntity
{
	int Id;
	string Name;
	int X;
	int Y;
	uint8 Kind;
}

/// A map chunk: the name, the sizes of the map state, the entities and the scripts (groups and bindings) of the map.
/// Layout: u16 nameLen, u16 flags, u16 vars, u16 vars32, u16 entityCount, u16 reserved, the name (padded to an even
/// length), the entities (u16 id, u16 x, u16 y, u8 kind, u8 nameLen, name padded to an even length), then u32 groupsLen,
/// the groups and u32 bindingsLen, the bindings, each padded to a multiple of 4, then the routines: u16 waypointCount with
/// the waypoint names (u16 len, name padded), u16 routineCount and per routine u16 id, u16 entity, u16 nameLen, name,
/// u16 entryCount; per entry u16 minute, u16 stepCount; per step u8 kind (0 walk_to, 1 stay, 2 sleep), u8 0, u16 waypoint
/// (0xFFFF none), u32 ticks.
struct PackedMap
{
	int Id;
	string Name;
	StateSizes Sizes;
	PackedEntity[] Entities;
	ScriptChunk Script;
	PackedRoutine[] Routines;

	static uint8[] Write(string name, StateSizes sizes, List<PackedEntity> entities, uint8[] groups, uint8[] bindings, List<PackedRoutine> routines)
	{
		var writer = ChunkWriter.Create();

		writer.Word(Latin1Length(name));
		writer.Word(sizes.Flags);
		writer.Word(sizes.Vars);
		writer.Word(sizes.Vars32);
		writer.Word(entities.Count());
		writer.Word(0);
		writer.PaddedText(name);

		foreach (var entity in entities)
		{
			writer.Word(entity.Id);
			writer.Word(entity.X);
			writer.Word(entity.Y);
			writer.Byte((int)entity.Kind);
			writer.Byte(Latin1Length(entity.Name));
			writer.PaddedText(entity.Name);
		}

		writer.Block(groups);
		writer.Block(bindings);
		WriteRoutines(writer, routines);

		return writer.ToArray();
	}

	static void WriteRoutines(ChunkWriter writer, List<PackedRoutine> routines)
	{
		var waypoints = List<string>.Create();

		foreach (var routine in routines)
		{
			foreach (var entry in routine.Entries)
			{
				foreach (var step in entry.Steps)
				{
					if (step.Target != null && !ContainsText(waypoints, step.Target))
						waypoints.Add(step.Target);
				}
			}
		}

		writer.Word(waypoints.Count());

		foreach (var waypoint in waypoints)
		{
			writer.Word(Latin1Length(waypoint));
			writer.PaddedText(waypoint);
		}

		writer.Word(routines.Count());

		foreach (var routine in routines)
		{
			writer.Word(routine.Id);
			writer.Word(routine.EntityId);
			writer.Word(Latin1Length(routine.Name));
			writer.PaddedText(routine.Name);
			writer.Word(routine.Entries.Length);

			foreach (var entry in routine.Entries)
			{
				writer.Word(entry.Minute);
				writer.Word(entry.Steps.Length);

				foreach (var step in entry.Steps)
				{
					writer.Byte((int)step.Kind);
					writer.Byte(0);
					writer.Word(step.Target == null ? 0xFFFF : IndexOfText(waypoints, step.Target));
					writer.Dword(step.Ticks);
				}
			}
		}
	}

	static Error<PackedRoutine[]> ReadRoutines(ref ChunkReader reader)
	{
		int waypointCount = try reader.Word();
		var waypoints = List<string>.Create();

		for (var i = 0; i < waypointCount; i += 1)
			waypoints.Add(try reader.PaddedText(try reader.Word()));

		int routineCount = try reader.Word();
		var routines = List<PackedRoutine>.Create();

		for (var r = 0; r < routineCount; r += 1)
		{
			int id = try reader.Word();
			int entity = try reader.Word();
			string routineName = try reader.PaddedText(try reader.Word());
			int entryCount = try reader.Word();
			var entries = List<PackedRoutineEntry>.Create();

			for (var e = 0; e < entryCount; e += 1)
			{
				int minute = try reader.Word();
				int stepCount = try reader.Word();
				var steps = List<PackedRoutineStep>.Create();

				for (var s = 0; s < stepCount; s += 1)
				{
					int kind = (int)try reader.Byte();

					try reader.Byte();

					int target = try reader.Word();
					int64 ticks = (int64)(uint32)try reader.Dword();

					if (kind > (int)PackedRoutineStepKind.Sleep || (target != 0xFFFF && target >= waypoints.Count()))
						return error("The routine '" + routineName + "' has an invalid step.", (int)ErrorKind.InvalidPack);

					steps.Add(PackedRoutineStep { Kind = (PackedRoutineStepKind)kind, Target = target == 0xFFFF ? null : waypoints.Get(target), Ticks = ticks });
				}

				entries.Add(PackedRoutineEntry { Minute = minute, Steps = ArrayOf(steps) });
			}

			routines.Add(PackedRoutine { Id = id, Name = routineName, EntityId = entity, Entries = ArrayOf(entries) });
		}

		return ArrayOf(routines);
	}

	static Error<PackedMap> Read(int id, uint8[] data)
	{
		var reader = ChunkReader.Of(data);
		int nameLength = try reader.Word();
		int flags = try reader.Word();
		int vars = try reader.Word();
		int vars32 = try reader.Word();
		int entityCount = try reader.Word();

		try reader.Word();

		string name = try reader.PaddedText(nameLength);
		var entities = List<PackedEntity>.Create();

		for (var i = 0; i < entityCount; i += 1)
		{
			int entityId = try reader.Word();
			int x = try reader.Word();
			int y = try reader.Word();
			uint8 kind = try reader.Byte();
			string entityName = try reader.PaddedText((int)try reader.Byte());

			entities.Add(PackedEntity { Id = entityId, Name = entityName, X = x, Y = y, Kind = kind });
		}

		var groups = try reader.Block();
		var bindings = try reader.Block();
		var script = try ScriptChunk.Create(groups, bindings);

		return PackedMap { Id = id, Name = name, Sizes = StateSizes.Of(flags, vars, vars32), Entities = ArrayOf(entities), Script = script, Routines = try ReadRoutines(ref reader) };
	}

	/// The entity IDs by name.
	Dictionary<string, int> EntityIds()
	{
		var ids = Dictionary<string, int>.Create();

		foreach (var entity in Entities)
			ids.Set(entity.Name, entity.Id);

		return ids;
	}
}

/// A screen chunk: the definition of the screen (ScreenChunk), the sizes of its state and its scripts. Layout:
/// u32 definitionLen, u16 flags, u16 vars, u16 vars32, u16 reserved, the definition (padded to a multiple of 4), then
/// u32 groupsLen, the groups and u32 bindingsLen, the bindings, each padded to a multiple of 4.
struct PackedScreen
{
	int Id;
	ScreenChunk Definition;
	StateSizes Sizes;
	ScriptChunk Script;

	static uint8[] Write(uint8[] definition, StateSizes sizes, uint8[] groups, uint8[] bindings)
	{
		var writer = ChunkWriter.Create();

		writer.Dword((int64)definition.Length);
		writer.Word(sizes.Flags);
		writer.Word(sizes.Vars);
		writer.Word(sizes.Vars32);
		writer.Word(0);
		writer.Bytes(definition);
		writer.Pad();
		writer.Block(groups);
		writer.Block(bindings);

		return writer.ToArray();
	}

	static Error<PackedScreen> Read(int id, uint8[] data)
	{
		var reader = ChunkReader.Of(data);
		int length = try reader.Dword();
		int flags = try reader.Word();
		int vars = try reader.Word();
		int vars32 = try reader.Word();

		try reader.Word();

		var definition = try ScreenChunk.Read(try reader.Bytes(length));

		try reader.Pad();

		var groups = try reader.Block();
		var bindings = try reader.Block();

		return PackedScreen { Id = id, Definition = definition, Sizes = StateSizes.Of(flags, vars, vars32), Script = try ScriptChunk.Create(groups, bindings) };
	}
}

/// Writes big endian words and length prefixed blocks; blocks and padding keep everything aligned to 4 bytes.
struct ChunkWriter
{
	ByteWriter _writer;

	static ChunkWriter Create()
	{
		return ChunkWriter { _writer = ByteWriter.Create() };
	}

	void Byte(int value)
	{
		_writer.Byte(value);
	}

	void Word(int value)
	{
		_writer.Word(value);
	}

	void Dword(int64 value)
	{
		_writer.Dword(value);
	}

	void Bytes(uint8[] data)
	{
		_writer.Bytes(data);
	}

	/// The Latin-1 bytes of the text, padded to an even length.
	void PaddedText(string text)
	{
		var bytes = Latin1Bytes(text);

		_writer.Bytes(bytes);

		if (bytes.Length % 2 != 0)
			_writer.Byte(0);
	}

	void Pad()
	{
		_writer.Align(4);
	}

	void Block(uint8[] data)
	{
		Dword((int64)data.Length);
		Bytes(data);
		Pad();
	}

	int Length()
	{
		return _writer.Length();
	}

	uint8[] ToArray()
	{
		return _writer.ToArray();
	}
}

/// The counterpart of ChunkWriter; every read is bounds checked (an InvalidPack error for a truncated chunk).
struct ChunkReader
{
	uint8[] _data;
	int _position;

	static ChunkReader Of(uint8[] data)
	{
		return ChunkReader { _data = data, _position = 0 };
	}

	/// The bytes that were not read yet (a chunk may have optional fields at its end).
	int Remaining()
	{
		return _data.Length - _position;
	}

	Error<void> Need(int count)
	{
		if (count < 0 || _position + count > _data.Length)
			return error("A chunk is truncated.", (int)ErrorKind.InvalidPack);

		return;
	}

	Error<uint8> Byte()
	{
		try Need(1);

		uint8 value = _data[_position];

		_position += 1;

		return value;
	}

	Error<int> Word()
	{
		try Need(2);

		_position += 2;

		return (int)ReadU16(_data, _position - 2);
	}

	/// The 32 bit value as int (C#: (int)BinaryPrimitives.ReadUInt32BigEndian).
	Error<int> Dword()
	{
		try Need(4);

		_position += 4;

		return (int)ReadU32(_data, _position - 4);
	}

	Error<uint8[]> Bytes(int count)
	{
		try Need(count);

		_position += count;

		return Slice(_data, _position - count, count);
	}

	Error<string> PaddedText(int length)
	{
		var bytes = try Bytes(length);
		string text = Latin1String(bytes, 0, bytes.Length);

		if (length % 2 != 0)
			try Bytes(1);

		return text;
	}

	Error<void> Pad()
	{
		while (_position % 4 != 0)
			try Bytes(1);

		return;
	}

	Error<uint8[]> Block()
	{
		var bytes = try Bytes(try Dword());

		try Pad();

		return bytes;
	}
}

/// The content of a pack as the game needs it: the scripts, maps and screens on demand, the natives, the layout, the texts
/// and tables.
struct PackContent
{
	PackReader Reader;

	static PackContent Of(PackReader reader)
	{
		return PackContent { Reader = reader };
	}

	PackHeader Header()
	{
		return Reader.Header;
	}

	StateSizes GlobalSizes()
	{
		return StateSizes.Of((int)Reader.Header.GlobalFlags, (int)Reader.Header.GlobalVars, (int)Reader.Header.GlobalVars32);
	}

	RuntimeLimits Limits()
	{
		return RuntimeLimits.Of((int)Reader.Header.MaxThreads, (int)Reader.Header.MaxChainSteps, (int)Reader.Header.MaxPendingEvents);
	}

	/// The global groups and bindings (empty if the pack has none).
	Error<ScriptChunk> GlobalScript()
	{
		return ScriptChunk.Create(try OptionalChunk(PackChunkType.Scripts), try OptionalChunk(PackChunkType.Bindings));
	}

	List<int> MapIds()
	{
		return Ids(PackChunkType.Map);
	}

	List<int> ScreenIds()
	{
		return Ids(PackChunkType.Screen);
	}

	Error<List<NativeEntry>> Natives()
	{
		if (!Reader.Contains(PackChunkType.Natives, 0))
			return List<NativeEntry>.Create();

		return NativeEntry.Read(try Reader.Get(PackChunkType.Natives, 0));
	}

	Error<LayoutTable> Layout()
	{
		if (!Reader.Contains(PackChunkType.Layout, 0))
			return LayoutTable.Of(new LayoutSlot[0]);

		return LayoutTable.Parse(Utf8String(try Reader.Get(PackChunkType.Layout, 0)));
	}

	/// The debug names (empty if the pack was cooked without them).
	Error<List<NamedId>> Symbols()
	{
		if (!Reader.Contains(PackChunkType.Symbols, 0))
			return List<NamedId>.Create();

		return NamedId.Read(try Reader.Get(PackChunkType.Symbols, 0));
	}

	Error<PackedMap> LoadMap(int id)
	{
		return PackedMap.Read(id, try Reader.Get(PackChunkType.Map, id));
	}

	Error<PackedScreen> LoadScreen(int id)
	{
		return PackedScreen.Read(id, try Reader.Get(PackChunkType.Screen, id));
	}

	/// The texts of a language (spec section 11).
	Error<Dictionary<int, string>> Texts(int language)
	{
		if (!Reader.Contains(PackChunkType.Text, language))
			return Dictionary<int, string>.Create();

		return StringTable.Read(try Reader.Get(PackChunkType.Text, language));
	}

	Error<Dictionary<int, string>> Strings(int tableId)
	{
		return StringTable.Read(try Reader.Get(PackChunkType.Table, tableId));
	}

	Error<List<NamedId>> Names(int tableId)
	{
		return NamedId.Read(try Reader.Get(PackChunkType.Table, tableId));
	}

	/// Load check (spec section 9.4): a MissingNative error if the pack expects natives which the game does not implement.
	Error<void> RequireNatives(string[] implemented)
	{
		return NativeEntry.Require(try Natives(), implemented);
	}

	Error<void> RequireNativesWith(Func<string, bool> isImplemented)
	{
		return NativeEntry.RequireWith(try Natives(), isImplemented);
	}

	/// Creates the interpreter with the limits and the global state sizes of the pack. The layout of the pack has to match
	/// the hash of its header.
	Error<Interpreter> CreateInterpreter()
	{
		try CheckLayout();

		return Interpreter.Create(try GlobalScript(), GlobalSizes(), Limits());
	}

	/// The same with a trace (spec section 12.3).
	Error<Interpreter> CreateTracedInterpreter(List<string> trace)
	{
		try CheckLayout();

		return Interpreter.CreateTraced(try GlobalScript(), GlobalSizes(), Limits(), trace);
	}

	Error<void> CheckLayout()
	{
		if (Reader.Contains(PackChunkType.Layout, 0))
		{
			var layout = try Layout();

			if (layout.Hash() != Reader.Header.LayoutHash)
				return error("The layout of the pack does not match the layout hash of its header.", (int)ErrorKind.InvalidPack);
		}

		return;
	}

	Error<uint8[]> OptionalChunk(PackChunkType type)
	{
		if (Reader.Contains(type, 0))
			return Reader.Get(type, 0);

		return new uint8[0];
	}

	List<int> Ids(PackChunkType type)
	{
		var ids = List<int>.Create();

		foreach (var entry in Reader.Entries)
		{
			if (entry.Type == type)
				ids.Add((int)entry.Id);
		}

		return ids;
	}
}
