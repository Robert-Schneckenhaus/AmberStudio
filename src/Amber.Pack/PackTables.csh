namespace Amber.Pack;

using System;
using Amber.Base;
using Amber.Script.Common;

/// The IDs of the TABLE chunks (type 6) which the cook writes itself. Tables of the game (speakers, item names ...) use IDs
/// from 0x0100.
const int PackTableUiGraphics = 1;
const int PackTableCursors = 2;
const int PackTableFirstGameTable = 0x0100;

/// A string of a string table (C#: the entries of IReadOnlyDictionary<int, string>).
struct IdText
{
	int Id;
	string Text;
}

int CompareIdText(IdText a, IdText b)
{
	return CompareInt(a.Id, b.Id);
}

/// A name with an ID and a kind, as used for the debug names (SYMBOLS chunk) and the name tables (UI graphics, cursors):
/// u16 count, then per entry u8 kind, u8 reserved, u16 id, u16 nameLen, name (Latin-1, padded to an even length).
struct NamedId
{
	uint8 Kind;
	uint16 Id;
	string Name;

	static uint8[] Write(List<NamedId> names)
	{
		var writer = ByteWriter.Create();

		writer.Word(names.Count());

		foreach (var name in names)
		{
			var bytes = Latin1Bytes(name.Name);

			writer.Byte((int)name.Kind);
			writer.Byte(0);
			writer.Word((int)name.Id);
			writer.Word(bytes.Length);
			writer.Bytes(bytes);

			if (bytes.Length % 2 != 0)
				writer.Byte(0);
		}

		return writer.ToArray();
	}

	static Error<List<NamedId>> Read(uint8[] data)
	{
		if (data.Length < 2)
			return error("A name table is shorter than its header.", (int)ErrorKind.InvalidPack);

		int count = (int)ReadU16(data, 0);
		int offset = 2;
		var result = List<NamedId>.Create();

		for (var i = 0; i < count; i += 1)
		{
			if (offset + 6 > data.Length)
				return error("A name table is truncated.", (int)ErrorKind.InvalidPack);

			int length = (int)ReadU16(data, offset + 4);
			int total = 6 + length + length % 2;

			if (offset + total > data.Length)
				return error("A name of a name table is truncated.", (int)ErrorKind.InvalidPack);

			result.Add(NamedId { Kind = data[offset], Id = ReadU16(data, offset + 2), Name = Latin1String(data, offset + 6, length) });
			offset += total;
		}

		return result;
	}
}

/// A native function or data source which the pack expects from the game (spec section 9.4).
struct NativeEntry
{
	uint16 Id;
	bool Blocking;
	bool DataSource;
	uint8 ArgumentCount;
	string Name;

	/// u16 count, then per entry u16 id, u16 flags (bit0 blocking, bit1 data source), u8 argc, u8 nameLen, name (ASCII,
	/// padded to an even length).
	static Error<uint8[]> Write(List<NativeEntry> natives)
	{
		var writer = ByteWriter.Create();

		writer.Word(natives.Count());

		foreach (var native in natives)
		{
			var name = AsciiBytes(native.Name);

			if (name.Length > 255)
				return error("The native name '" + native.Name + "' is longer than 255 characters.", (int)ErrorKind.InvalidPack);

			writer.Word((int)native.Id);
			writer.Word((native.Blocking ? 1 : 0) | (native.DataSource ? 2 : 0));
			writer.Byte((int)native.ArgumentCount);
			writer.Byte(name.Length);
			writer.Bytes(name);

			if (name.Length % 2 != 0)
				writer.Byte(0);
		}

		return writer.ToArray();
	}

	static Error<List<NativeEntry>> Read(uint8[] data)
	{
		if (data.Length < 2)
			return error("The natives table is shorter than its header.", (int)ErrorKind.InvalidPack);

		int count = (int)ReadU16(data, 0);
		int offset = 2;
		var result = List<NativeEntry>.Create();

		for (var i = 0; i < count; i += 1)
		{
			if (offset + 6 > data.Length)
				return error("The natives table is truncated.", (int)ErrorKind.InvalidPack);

			int length = (int)data[offset + 5];
			int total = 6 + length + length % 2;

			if (offset + total > data.Length)
				return error("A name of the natives table is truncated.", (int)ErrorKind.InvalidPack);

			int flags = (int)ReadU16(data, offset + 2);

			result.Add(NativeEntry
			{
				Id = ReadU16(data, offset),
				Blocking = (flags & 1) != 0,
				DataSource = (flags & 2) != 0,
				ArgumentCount = data[offset + 4],
				Name = AsciiString(data, offset + 6, length)
			});
			offset += total;
		}

		return result;
	}

	/// Load check of spec section 9.4: every native of the pack has to be implemented by the game (a MissingNative error
	/// names the missing ones).
	static Error<void> Require(List<NativeEntry> natives, string[] implemented)
	{
		var missing = List<string>.Create();

		foreach (var native in natives)
		{
			if (!ContainsText(implemented, native.Name))
				missing.Add(native.Name);
		}

		if (missing.Count() > 0)
			return error("The game does not implement these natives: " + JoinList(", ", missing) + ".", (int)ErrorKind.MissingNative);

		return;
	}

	/// The same check with a predicate, for games which implement whole families of natives.
	static Error<void> RequireWith(List<NativeEntry> natives, Func<string, bool> isImplemented)
	{
		var missing = List<string>.Create();

		foreach (var native in natives)
		{
			if (!isImplemented(native.Name))
				missing.Add(native.Name);
		}

		if (missing.Count() > 0)
			return error("The game does not implement these natives: " + JoinList(", ", missing) + ".", (int)ErrorKind.MissingNative);

		return;
	}
}

/// The names of the missing natives from the message of a MissingNative error (C#: MissingNativeException.Names).
List<string> MissingNativeNames(string message)
{
	var names = List<string>.Create();
	string prefix = "The game does not implement these natives: ";

	if (!message.StartsWith(prefix))
		return names;

	string list = message.Substring(prefix.Length);

	if (list.EndsWith("."))
		list = list.Substring(0, list.Length - 1);

	foreach (var name in list.Split(", "))
		names.Add(name.ToString());

	return names;
}

/// One slot of the state layout (spec section 10.1): <ScopeKind> <scope name> <Namespace>.<Kind>[<index>] <name>.
struct LayoutSlot
{
	string ScopeKind;
	string ScopeName;
	string Namespace;
	string Kind;
	int Index;
	string Name;

	/// C#: ToString().
	string Text()
	{
		return ScopeKind + " " + ScopeName + " " + Namespace + "." + Kind + "[" + Index + "] " + Name;
	}

	static Error<LayoutSlot> Parse(string line)
	{
		// C#: line.Split(' ', 4)
		var parts = List<string>.Create();
		int start = 0;

		for (var i = 0; i < line.Length && parts.Count() < 3; i += 1)
		{
			if (line[i] == ' ')
			{
				parts.Add(line.Substring(start, i - start));
				start = i + 1;
			}
		}

		if (parts.Count() != 3)
			return error("'" + line + "' is not a layout line.", (int)ErrorKind.InvalidPack);

		parts.Add(line.Substring(start));

		string slot = parts.Get(2);
		int dot = slot.IndexOf('.');
		int open = slot.IndexOf('[');

		if (dot <= 0 || open < dot || !slot.EndsWith("]"))
			return error("'" + line + "' is not a layout line.", (int)ErrorKind.InvalidPack);

		if (TryParseInt(slot.Substring(open + 1, slot.Length - open - 2)) is int index)
			return LayoutSlot { ScopeKind = parts.Get(0), ScopeName = parts.Get(1), Namespace = slot.Substring(0, dot), Kind = slot.Substring(dot + 1, open - dot - 1), Index = index, Name = parts.Get(3) };

		return error("'" + line + "' is not a layout line.", (int)ErrorKind.InvalidPack);
	}

	/// The identity of a slot across layouts: scope kind, scope name, kind and name (C#: LayoutDiff.Key).
	string Key()
	{
		return ScopeKind + "\n" + ScopeName + "\n" + Kind + "\n" + Name;
	}
}

/// The state layout of a release: which name has which slot in which scope. The LAYOUT chunk holds it as text, one slot per
/// line, in the order of the declaration; the hash is the CRC-32 of that text.
struct LayoutTable
{
	LayoutSlot[] Slots;

	static LayoutTable Of(LayoutSlot[] slots)
	{
		return LayoutTable { Slots = slots };
	}

	string Text()
	{
		var lines = new string[Slots.Length];

		for (var i = 0; i < Slots.Length; i += 1)
			lines[i] = Slots[i].Text();

		return string.Join("\n", lines);
	}

	uint32 Hash()
	{
		return Crc32Of(Utf8Bytes(Text()));
	}

	static Error<LayoutTable> Parse(string text)
	{
		var slots = List<LayoutSlot>.Create();

		foreach (var line in NonEmptyLines(text))
		{
			if (line.StartsWith("#"))
				continue;

			slots.Add(try LayoutSlot.Parse(line));
		}

		return LayoutTable { Slots = ArrayOf(slots) };
	}

	/// The slot of a name in a scope, or no value.
	Optional<LayoutSlot> Find(string scopeKind, string scopeName, string kind, string name)
	{
		foreach (var slot in Slots)
		{
			if (slot.ScopeKind == scopeKind && slot.ScopeName == scopeName && slot.Kind == kind && slot.Name == name)
				return slot;
		}

		return null;
	}

	/// Number of slots of a kind in a scope (the size of the array).
	int Count(string scopeKind, string scopeName, string kind)
	{
		int count = 0;

		foreach (var slot in Slots)
		{
			if (slot.ScopeKind == scopeKind && slot.ScopeName == scopeName && slot.Kind == kind)
				count += 1;
		}

		return count;
	}
}
