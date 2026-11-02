namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Pack;
using Amber.Script;
using Amber.Script.Compilation;

// The pack container (spec section 9): format, alignment, compressions, readers, tables and the load check.

void RegisterPackTests(ref TestList tests)
{
	tests.Fact("Pack.Crc16MatchesTheCcittCheckValue", Crc16MatchesTheCcittCheckValue);

	foreach (var length in new string[] { "0", "1", "255", "256", "257", "5000" })
		tests.Theory("Pack.CompressionsRoundTrip", CompressionsRoundTrip, length);

	tests.Fact("Pack.Rle0CodesLongZeroRunsInBlocksOf256", Rle0CodesLongZeroRunsInBlocksOf256);
	tests.Fact("Pack.BestNeverGrowsAndZeroHeavyDataShrinks", BestNeverGrowsAndZeroHeavyDataShrinks);
	tests.Fact("Pack.DamagedCompressedDataIsRejected", DamagedCompressedDataIsRejected);
	tests.Fact("Pack.HeaderAndTableOfContentsRoundTrip", HeaderAndTableOfContentsRoundTrip);
	tests.Fact("Pack.EveryOffsetIsAligned", EveryOffsetIsAligned);
	tests.Fact("Pack.ChunksAreLoadableInAnyOrderFromAFile", ChunksAreLoadableInAnyOrderFromAFile);
	tests.Fact("Pack.ADamagedChunkFailsItsChecksum", ADamagedChunkFailsItsChecksum);
	tests.Fact("Pack.BrokenFilesAreRejected", BrokenPackFilesAreRejected);
	tests.Fact("Pack.TheWriterRefusesDoubleChunks", TheWriterRefusesDoubleChunks);
	tests.Fact("Pack.StringTablesRoundTripAndKeepGaps", StringTablesRoundTripAndKeepGaps);
	tests.Fact("Pack.NameTablesAndNativesRoundTrip", NameTablesAndNativesRoundTrip);
	tests.Fact("Pack.MissingNativesAreALoadError", MissingNativesAreALoadError);
	tests.Fact("Pack.LayoutTextParsesAndHashesLikeTheCompiler", LayoutTextParsesAndHashesLikeTheCompiler);
}

/// Data with about three quarters zeros (C#: new Random(seed); the exact bytes do not matter, only that they are the
/// same for the same seed).
uint8[] Sample(int length, int seed)
{
	uint32 state = (uint32)(seed * 7919 + 12345);
	var data = new uint8[length];

	for (var i = 0; i < length; i += 1)
	{
		state ^= state << 13;
		state ^= state >> 17;
		state ^= state << 5;

		if ((state & 3) == 0)
			data[i] = (uint8)(state >> 8);
	}

	return data;
}

Error<uint8[]> SamplePack()
{
	var writer = PackWriter.Create();

	writer.ProfileId = 1;
	writer.LayoutHash = 0xCAFEBABE;
	writer.GlobalFlags = 17;
	writer.GlobalVars = 3;
	writer.GlobalVars32 = 1;
	writer.NativeCount = 2;
	writer.Flags = PackHasSymbols;

	try writer.Add(PackChunkType.Scripts, 0, new uint8[] { 1, 2, 3, 4, 5 }, PackCompression.None);
	try writer.Add(PackChunkType.Map, 7, Sample(1000, 1), PackCompression.Rle0);
	try writer.Add(PackChunkType.Map, 2, Sample(3001, 2), PackCompression.Deflate);
	try writer.Add(PackChunkType.Text, 0, Utf8Bytes("hello"), PackCompression.None);
	try writer.AddBest(PackChunkType.Table, 0x0100, Sample(500, 3));

	return writer.ToArray();
}

Error<void> Crc16MatchesTheCcittCheckValue()
{
	// CRC-16/CCITT-FALSE of "123456789"
	return Assert.Equal(0x29B1, Crc16(Utf8Bytes("123456789")));
}

Error<void> CompressionsRoundTrip(string[] arguments)
{
	int length = 0;

	if (TryParseInt(arguments[0]) is int value)
		length = value;

	var data = Sample(length, 1);

	foreach (var compression in new PackCompression[] { PackCompression.None, PackCompression.Rle0, PackCompression.Deflate })
		try Assert.Bytes(data, try PackCompressor.Decompress(compression, try PackCompressor.Compress(compression, data), data.Length));

	return;
}

Error<void> Rle0CodesLongZeroRunsInBlocksOf256()
{
	// 300 zeros: (0, 255) covers 256, (0, 43) the remaining 44
	try Assert.Bytes(new uint8[] { 0, 255, 0, 43 }, try PackCompressor.Compress(PackCompression.Rle0, new uint8[300]));
	try Assert.Bytes(new uint8[] { 7, 0, 2, 9 }, try PackCompressor.Compress(PackCompression.Rle0, new uint8[] { 7, 0, 0, 0, 9 }));

	return;
}

Error<void> BestNeverGrowsAndZeroHeavyDataShrinks()
{
	var zeros = PackCompressor.Best(new uint8[2000], true);

	try Assert.NotEqual((int)PackCompression.None, (int)zeros.Compression);
	try Assert.True(zeros.Data.Length < 100, "2000 zeros shrink below 100 bytes");

	var small = PackCompressor.Best(new uint8[] { 1, 2, 3 }, true);

	try Assert.Equal((int)PackCompression.None, (int)small.Compression);
	try Assert.Equal(3, small.Data.Length);

	return;
}

Error<void> DamagedCompressedDataIsRejected()
{
	try Assert.Fails(PackCompressor.Decompress(PackCompression.Rle0, new uint8[] { 5, 0 }, 2), ErrorKind.InvalidPack);
	try Assert.Fails(PackCompressor.Decompress(PackCompression.Rle0, new uint8[] { 0, 200 }, 10), ErrorKind.InvalidPack);
	try Assert.Fails(PackCompressor.Decompress(PackCompression.None, new uint8[] { 1, 2, 3 }, 4), ErrorKind.InvalidPack);
	try Assert.Fails(PackCompressor.Decompress(PackCompression.Deflate, new uint8[] { 1, 2, 3, 4 }, 4), ErrorKind.InvalidPack);

	return;
}

Error<void> HeaderAndTableOfContentsRoundTrip()
{
	var pack = try PackReader.FromMemory(try SamplePack());
	var header = pack.Header;

	try Assert.Equal(1, header.ProfileId);
	try Assert.Equal(0xCAFEBABE, header.LayoutHash);
	try Assert.Equal(17, header.GlobalFlags);
	try Assert.Equal(3, header.GlobalVars);
	try Assert.Equal(1, header.GlobalVars32);
	try Assert.Equal(2, header.NativeCount);
	try Assert.True(header.SymbolsIncluded());
	try Assert.Equal(5, header.TocCount);
	try Assert.Bytes(new uint8[] { 1, 2, 3, 4, 5 }, try pack.Get(PackChunkType.Scripts, 0));
	try Assert.Bytes(Sample(1000, 1), try pack.Get(PackChunkType.Map, 7));
	try Assert.Bytes(Sample(3001, 2), try pack.Get(PackChunkType.Map, 2));
	try Assert.Bytes(Utf8Bytes("hello"), try pack.Get(PackChunkType.Text, 0));
	try Assert.Bytes(Sample(500, 3), try pack.Get(PackChunkType.Table, 0x0100));

	return;
}

Error<void> EveryOffsetIsAligned()
{
	var data = try SamplePack();
	var pack = try PackReader.FromMemory(data);

	try Assert.Equal(0, pack.Header.TocOffset % 4);

	foreach (var entry in pack.Entries)
		try Assert.Equal(0, entry.Offset % 4);

	// the table of contents is sorted by type and ID
	for (var i = 1; i < pack.Entries.Length; i += 1)
	{
		var previous = pack.Entries[i - 1];
		var entry = pack.Entries[i];

		try Assert.True((int)previous.Type < (int)entry.Type || (previous.Type == entry.Type && previous.Id < entry.Id), "the entries are sorted");
	}

	// the table of contents is the last part of the file
	try Assert.Equal((int)pack.Header.TocOffset + (int)pack.Header.TocCount * PackEntrySize, data.Length);

	return;
}

Error<void> ChunksAreLoadableInAnyOrderFromAFile()
{
	string path = Path.Combine(NewTempFolder("pack"), "test.pack");

	try File.WriteAllBytes(path, try SamplePack());

	var pack = try PackReader.FromFile(path);

	try Assert.Bytes(Sample(3001, 2), try pack.Get(PackChunkType.Map, 2));
	try Assert.Bytes(new uint8[] { 1, 2, 3, 4, 5 }, try pack.Get(PackChunkType.Scripts, 0));
	try Assert.Bytes(Sample(1000, 1), try pack.Get(PackChunkType.Map, 7));
	try Assert.True(pack.Contains(PackChunkType.Text, 0));
	try Assert.False(pack.Contains(PackChunkType.Text, 1));
	try Assert.Fails(pack.Get(PackChunkType.Text, 1), ErrorKind.PackChunkNotFound);

	return;
}

Error<void> ADamagedChunkFailsItsChecksum()
{
	var data = try SamplePack();
	int offset = -1;

	foreach (var entry in (try PackReader.FromMemory(data)).Entries)
	{
		if (entry.Type == PackChunkType.Scripts)
			offset = (int)entry.Offset;
	}

	data[offset + 2] = (uint8)((int)data[offset + 2] ^ 0xFF);

	var pack = try PackReader.FromMemory(data);

	try Assert.Fails(pack.Get(PackChunkType.Scripts, 0), ErrorKind.PackChecksum);
	try Assert.Bytes(Utf8Bytes("hello"), try pack.Get(PackChunkType.Text, 0));

	return;
}

/// A copy of the bytes (C#: [.. good]).
uint8[] CopyOf(uint8[] data)
{
	return Slice(data, 0, data.Length);
}

Error<void> BrokenPackFilesAreRejected()
{
	var good = try SamplePack();

	try Assert.Fails(PackReader.FromMemory(Slice(good, 0, 20)), ErrorKind.InvalidPack);
	try Assert.Fails(PackReader.FromMemory(Slice(good, 0, good.Length - 30)), ErrorKind.InvalidPack);

	var magic = CopyOf(good);

	magic[0] = (uint8)'X';
	try Assert.Fails(PackReader.FromMemory(magic), ErrorKind.InvalidPack);

	var version = CopyOf(good);

	version[5] = 9;
	try Assert.Fails(PackReader.FromMemory(version), ErrorKind.InvalidPack);

	var unaligned = CopyOf(good);

	WriteU32(unaligned, 12, (int64)ReadU32(good, 12) + 1);
	try Assert.Fails(PackReader.FromMemory(unaligned), ErrorKind.InvalidPack);

	// an entry which points behind the data area
	var outside = CopyOf(good);
	int firstEntry = (int)ReadU32(good, 12);

	WriteU32(outside, firstEntry + 8, 100000);
	try Assert.Fails(PackReader.FromMemory(outside), ErrorKind.InvalidPack);

	// the same chunk twice
	var twice = CopyOf(good);

	for (var i = 0; i < 4; i += 1)
		twice[firstEntry + PackEntrySize + i] = good[firstEntry + i];

	try Assert.Fails(PackReader.FromMemory(twice), ErrorKind.InvalidPack);

	return;
}

Error<void> TheWriterRefusesDoubleChunks()
{
	var writer = PackWriter.Create();

	try writer.Add(PackChunkType.Map, 1, new uint8[] { 1 }, PackCompression.None);

	try Assert.FailsVoid(writer.Add(PackChunkType.Map, 1, new uint8[] { 2 }, PackCompression.None), ErrorKind.InvalidPack);
	try Assert.FailsVoid(writer.Add(PackChunkType.Map, 70000, new uint8[] { 2 }, PackCompression.None), ErrorKind.InvalidPack);

	return;
}

Error<void> StringTablesRoundTripAndKeepGaps()
{
	var strings = Dictionary<int, string>.Create();

	strings.Set(1, "Hello");
	strings.Set(4, "Café");
	strings.Set(5, "");

	var read = try StringTable.Read(try StringTable.Write(strings));

	try Assert.Ints(strings.Keys(), read.Keys());

	foreach (var key in strings.Keys())
		try Assert.Equal(strings.GetOrDefault(key, null), read.GetOrDefault(key, null));

	try Assert.Equal(0, (try StringTable.Read(try StringTable.Write(Dictionary<int, string>.Create()))).Count());

	var chinese = Dictionary<int, string>.Create();

	chinese.Set(1, "中");

	try Assert.Fails(StringTable.Write(chinese), ErrorKind.InvalidData);
	try Assert.Fails(StringTable.Read(new uint8[] { 0, 5, 0, 0 }), ErrorKind.InvalidPack);

	return;
}

Error<void> NameTablesAndNativesRoundTrip()
{
	var names = List<NamedId>.Create();

	names.Add(NamedId { Kind = 1, Id = 4, Name = "abc" });
	names.Add(NamedId { Kind = 2, Id = 9, Name = "even" });
	names.Add(NamedId { Kind = 0, Id = 65535, Name = "" });

	var readNames = try NamedId.Read(NamedId.Write(names));

	try Assert.Equal(names.Count(), readNames.Count());

	for (var i = 0; i < names.Count(); i += 1)
	{
		try Assert.Equal((int)names.Get(i).Kind, (int)readNames.Get(i).Kind);
		try Assert.Equal(names.Get(i).Id, readNames.Get(i).Id);
		try Assert.Equal(names.Get(i).Name, readNames.Get(i).Name);
	}

	var natives = SampleNatives();
	var written = try NativeEntry.Write(natives);
	var readNatives = try NativeEntry.Read(written);

	try Assert.Equal(natives.Count(), readNatives.Count());

	for (var i = 0; i < natives.Count(); i += 1)
	{
		var expected = natives.Get(i);
		var actual = readNatives.Get(i);

		try Assert.Equal(expected.Id, actual.Id);
		try Assert.Equal(expected.Blocking, actual.Blocking);
		try Assert.Equal(expected.DataSource, actual.DataSource);
		try Assert.Equal((int)expected.ArgumentCount, (int)actual.ArgumentCount);
		try Assert.Equal(expected.Name, actual.Name);
	}

	try Assert.Fails(NativeEntry.Read(Slice(written, 0, written.Length - 3)), ErrorKind.InvalidPack);

	return;
}

List<NativeEntry> SampleNatives()
{
	var natives = List<NativeEntry>.Create();

	natives.Add(NativeEntry { Id = 1, Blocking = false, DataSource = false, ArgumentCount = 0, Name = "pop_arg" });
	natives.Add(NativeEntry { Id = 2, Blocking = true, DataSource = false, ArgumentCount = 2, Name = "ask" });
	natives.Add(NativeEntry { Id = 3, Blocking = false, DataSource = true, ArgumentCount = 0, Name = "party.gold" });

	return natives;
}

Error<void> MissingNativesAreALoadError()
{
	var natives = List<NativeEntry>.Create();

	natives.Add(NativeEntry { Id = 1, Blocking = false, DataSource = false, ArgumentCount = 0, Name = "pop_arg" });
	natives.Add(NativeEntry { Id = 2, Blocking = false, DataSource = true, ArgumentCount = 0, Name = "party.gold" });
	natives.Add(NativeEntry { Id = 3, Blocking = false, DataSource = false, ArgumentCount = 0, Name = "chest_take" });

	try NativeEntry.Require(natives, new string[] { "pop_arg", "party.gold", "chest_take", "more" });

	string message = try Assert.FailsVoid(NativeEntry.Require(natives, new string[] { "pop_arg" }), ErrorKind.MissingNative);

	return Assert.Strings(new string[] { "party.gold", "chest_take" }, MissingNativeNames(message));
}

Error<void> LayoutTextParsesAndHashesLikeTheCompiler()
{
	var result = ScriptCompiler.CompileText("flag a; var v;\nmap m { flag b; var32 w; }\ngroup g { do { set_flag(a); } }\non hour(1) -> g;", "test.ams", CompileOptions { LenientSymbols = true });
	var layout = try LayoutTable.Parse(result.LayoutText);

	try Assert.Equal(result.LayoutHash, layout.Hash());
	try Assert.Equal(4, layout.Slots.Length);
	try Assert.True(layout.Find("Map", "m", "Flag", "b") is LayoutSlot, "the flag b of the map m");

	if (layout.Find("Map", "m", "Flag", "b") is LayoutSlot slot)
		try Assert.Equal("Map m Map.Flag[0] b", slot.ScopeKind + " " + slot.ScopeName + " " + slot.Namespace + "." + slot.Kind + "[" + slot.Index + "] " + slot.Name);

	try Assert.Equal(1, layout.Count("Global", "global", "Var"));
	try Assert.False(layout.Find("Map", "m", "Flag", "a") is LayoutSlot, "no flag a in the map m");
	try Assert.Fails(LayoutTable.Parse("nonsense"), ErrorKind.InvalidPack);

	return;
}
