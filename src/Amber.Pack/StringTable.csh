// String table of the TEXT chunk (spec section 11) and of string tables of the game: u16 count, u16 reserved,
// u32 offset[count], then zero terminated Latin-1 strings. The index is the ID; an offset of 0 means that the ID has no
// string.

namespace Amber.Pack.StringTable;

using System;
using Amber.Base;

Error<uint8[]> Write(Dictionary<int, string> strings)
{
	int count = 0;

	foreach (var id in strings.Keys())
		count = Math.Max(count, id + 1);

	int start = 4 + count * 4;
	var body = ByteWriter.Create();
	var offsets = new uint32[count];
	var sorted = List<IdText>.Create();

	foreach (var entry in strings.Entries())
		sorted.Add(IdText { Id = entry.Key, Text = entry.Value });

	SortList(sorted, CompareIdText);

	foreach (var pair in sorted)
	{
		if (pair.Id < 0 || pair.Id > 0xFFFF)
			return error("The string ID " + pair.Id + " does not fit into 16 bits.", (int)ErrorKind.InvalidPack);

		int bad = FirstNonLatin1(pair.Text);

		if (bad >= 0)
			return error("E012: the string " + pair.Id + " contains '" + CodePointText(bad) + "' (U+" + Hex(bad, 4) + "), which is not a Latin-1 character.", (int)ErrorKind.InvalidData);

		offsets[pair.Id] = (uint32)(start + body.Length());
		body.Bytes(Latin1Bytes(pair.Text));
		body.Byte(0);
	}

	var bodyBytes = body.ToArray();
	var result = new uint8[start + bodyBytes.Length];

	WriteU16(result, 0, count);

	for (var i = 0; i < count; i += 1)
		WriteU32(result, 4 + i * 4, (int64)offsets[i]);

	Array.Copy(bodyBytes, 0, result, start, bodyBytes.Length);

	return result;
}

Error<Dictionary<int, string>> Read(uint8[] data)
{
	if (data.Length < 4)
		return error("A string table is shorter than its header.", (int)ErrorKind.InvalidPack);

	int count = (int)ReadU16(data, 0);

	if (data.Length < 4 + count * 4)
		return error("A string table is shorter than its offset list.", (int)ErrorKind.InvalidPack);

	var result = Dictionary<int, string>.Create();

	for (var i = 0; i < count; i += 1)
	{
		uint32 offset = ReadU32(data, 4 + i * 4);

		if (offset == 0)
			continue;

		if (offset < (uint32)(4 + count * 4) || offset >= (uint32)data.Length)
			return error("The string " + i + " lies outside of its table.", (int)ErrorKind.InvalidPack);

		int end = -1;

		for (var position = (int)offset; position < data.Length; position += 1)
		{
			if (data[position] == 0)
			{
				end = position;
				break;
			}
		}

		if (end < 0)
			return error("The string " + i + " is not terminated.", (int)ErrorKind.InvalidPack);

		result.Set(i, Latin1String(data, (int)offset, end - (int)offset));
	}

	return result;
}
