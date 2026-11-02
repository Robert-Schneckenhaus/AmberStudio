// The pack file (spec section 9): header, table of contents, chunk types and compressions. The C# exception types become
// error kinds: InvalidPack, PackChecksum, PackChunkNotFound and MissingNative (see Amber.Base.ErrorKind).

namespace Amber.Pack;

using System;
using Amber.Base;
using Amber.Script.Common;

/// Chunk types of the table of contents (spec section 9.2). Presentation data uses types from 0x0100.
enum PackChunkType : uint16
{
	Scripts = 0x0001,
	Bindings = 0x0002,
	Screen = 0x0003,
	Map = 0x0004,
	TilesetLogic = 0x0005,
	Table = 0x0006,
	Text = 0x0007,
	Natives = 0x0008,
	Symbols = 0x0009,
	Layout = 0x000A,
	Words = 0x000B
}

EnumEntry[] PackChunkTypeNames = new EnumEntry[]
{
	En("Scripts", 1), En("Bindings", 2), En("Screen", 3), En("Map", 4), En("TilesetLogic", 5), En("Table", 6), En("Text", 7),
	En("Natives", 8), En("Symbols", 9), En("Layout", 10), En("Words", 11)
};

string PackChunkTypeName(PackChunkType type)
{
	return EnumName(PackChunkTypeNames, (int)type);
}

/// Compression of a chunk (spec section 9.3). RLE0 is the zero run length coding of the Amber game data (identifier 0xC001
/// there), Deflate is the raw deflate stream (0xDEF0 there).
enum PackCompression : uint16
{
	None = 0,
	Rle0 = 1,
	Deflate = 2
}

EnumEntry[] PackCompressionNames = new EnumEntry[] { En("None", 0), En("Rle0", 1), En("Deflate", 2) };

string PackCompressionName(PackCompression compression)
{
	return EnumName(PackCompressionNames, (int)compression);
}

const int PackHeaderSize = 40;
const uint16 PackHasSymbols = 1;
const string PackMagic = "AMBP";

/// The pack header (spec section 9.1, 40 bytes, big endian).
struct PackHeader
{
	uint16 FormatVersion;
	uint16 ProfileId;
	uint16 Flags;
	uint16 TocCount;
	uint32 TocOffset;
	uint32 LayoutHash;
	uint16 MaxThreads;
	uint16 MaxChainSteps;
	uint16 MaxScreenDepth;
	uint16 MaxPendingEvents;
	uint16 GlobalFlags;
	uint16 GlobalVars;
	uint16 GlobalVars32;
	uint16 NativeCount;

	bool SymbolsIncluded()
	{
		return ((int)Flags & (int)PackHasSymbols) != 0;
	}

	void Write(uint8[] destination)
	{
		for (var i = 0; i < PackHeaderSize; i += 1)
			destination[i] = 0;

		for (var i = 0; i < 4; i += 1)
			destination[i] = PackMagic[i];

		WriteU16(destination, 4, (int)FormatVersion);
		WriteU16(destination, 6, (int)ProfileId);
		WriteU16(destination, 8, (int)Flags);
		WriteU16(destination, 10, (int)TocCount);
		WriteU32(destination, 12, (int64)TocOffset);
		WriteU32(destination, 16, (int64)LayoutHash);
		WriteU16(destination, 20, (int)MaxThreads);
		WriteU16(destination, 22, (int)MaxChainSteps);
		WriteU16(destination, 24, (int)MaxScreenDepth);
		WriteU16(destination, 26, (int)MaxPendingEvents);
		WriteU16(destination, 28, (int)GlobalFlags);
		WriteU16(destination, 30, (int)GlobalVars);
		WriteU16(destination, 32, (int)GlobalVars32);
		WriteU16(destination, 34, (int)NativeCount);
	}

	static Error<PackHeader> Read(uint8[] source)
	{
		if (source.Length < PackHeaderSize)
			return error("The file is shorter than the pack header.", (int)ErrorKind.InvalidPack);

		if (!StartsWithAscii(source, PackMagic))
			return error("The file is not a pack (wrong magic).", (int)ErrorKind.InvalidPack);

		var header = PackHeader
		{
			FormatVersion = ReadU16(source, 4),
			ProfileId = ReadU16(source, 6),
			Flags = ReadU16(source, 8),
			TocCount = ReadU16(source, 10),
			TocOffset = ReadU32(source, 12),
			LayoutHash = ReadU32(source, 16),
			MaxThreads = ReadU16(source, 20),
			MaxChainSteps = ReadU16(source, 22),
			MaxScreenDepth = ReadU16(source, 24),
			MaxPendingEvents = ReadU16(source, 26),
			GlobalFlags = ReadU16(source, 28),
			GlobalVars = ReadU16(source, 30),
			GlobalVars32 = ReadU16(source, 32),
			NativeCount = ReadU16(source, 34)
		};

		if (header.FormatVersion != 0)
			return error("The pack format version " + header.FormatVersion + " is not supported.", (int)ErrorKind.InvalidPack);

		if (header.TocOffset % 4 != 0)
			return error("The table of contents is not aligned to 4 bytes.", (int)ErrorKind.InvalidPack);

		return header;
	}
}

const int PackEntrySize = 20;

/// One entry of the table of contents (spec section 9.2, 20 bytes).
struct PackEntry
{
	PackChunkType Type;
	uint16 Id;
	uint32 Offset;
	uint32 PackedSize;
	uint32 UnpackedSize;
	PackCompression Compression;
	uint16 Crc16;

	void Write(uint8[] destination, int at)
	{
		WriteU16(destination, at, (int)Type);
		WriteU16(destination, at + 2, (int)Id);
		WriteU32(destination, at + 4, (int64)Offset);
		WriteU32(destination, at + 8, (int64)PackedSize);
		WriteU32(destination, at + 12, (int64)UnpackedSize);
		WriteU16(destination, at + 16, (int)Compression);
		WriteU16(destination, at + 18, (int)Crc16);
	}

	static PackEntry Read(uint8[] source, int at)
	{
		return PackEntry
		{
			Type = (PackChunkType)ReadU16(source, at),
			Id = ReadU16(source, at + 2),
			Offset = ReadU32(source, at + 4),
			PackedSize = ReadU32(source, at + 8),
			UnpackedSize = ReadU32(source, at + 12),
			Compression = (PackCompression)ReadU16(source, at + 16),
			Crc16 = ReadU16(source, at + 18)
		};
	}

	/// C#: the type in messages ("Map" or the number of an unknown type).
	string TypeText()
	{
		return PackChunkTypeName(Type);
	}
}

uint16[] Crc16Table = BuildCrc16Table();

uint16[] BuildCrc16Table()
{
	var result = new uint16[256];

	for (var i = 0; i < 256; i += 1)
	{
		int value = i << 8;

		for (var bit = 0; bit < 8; bit += 1)
			value = (value & 0x8000) != 0 ? ((value << 1) ^ 0x1021) & 0xFFFF : (value << 1) & 0xFFFF;

		result[i] = (uint16)value;
	}

	return result;
}

/// CRC-16/CCITT-FALSE (polynomial 0x1021, start value 0xFFFF, no reflection, no final xor) over the packed bytes of a chunk.
uint16 Crc16(uint8[] data)
{
	int crc = 0xFFFF;

	foreach (var value in data)
		crc = ((crc << 8) ^ (int)Crc16Table[(crc >> 8) ^ (int)value]) & 0xFFFF;

	return (uint16)crc;
}
