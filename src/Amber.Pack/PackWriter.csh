namespace Amber.Pack;

using System;
using Amber.Base;

struct PackChunk
{
	PackChunkType Type;
	uint16 Id;
	uint8[] Packed;
	int UnpackedSize;
	PackCompression Compression;
}

/// Writes a pack (spec section 9): header, the chunks (each starting at an offset divisible by 4) and the table of contents
/// (sorted by type and ID, also divisible by 4) at the end. The header fields are set directly; the chunks are shared by
/// copies of the writer.
struct PackWriter
{
	List<PackChunk> _chunks;
	uint16 ProfileId;
	uint16 Flags;
	uint32 LayoutHash;
	uint16 MaxThreads;
	uint16 MaxChainSteps;
	uint16 MaxScreenDepth;
	uint16 MaxPendingEvents;
	uint16 GlobalFlags;
	uint16 GlobalVars;
	uint16 GlobalVars32;
	uint16 NativeCount;
	/// False for profiles which cannot unpack deflate (the Amiga profile): AddBest then only picks none or RLE0.
	bool AllowDeflate;

	static PackWriter Create()
	{
		return PackWriter
		{
			_chunks = List<PackChunk>.Create(),
			MaxThreads = 16,
			MaxChainSteps = 64,
			MaxScreenDepth = 8,
			MaxPendingEvents = 32,
			AllowDeflate = true
		};
	}

	int Count()
	{
		return _chunks.Count();
	}

	bool Contains(PackChunkType type, int id)
	{
		foreach (var chunk in _chunks)
		{
			if (chunk.Type == type && (int)chunk.Id == id)
				return true;
		}

		return false;
	}

	/// Adds a chunk with the given compression.
	Error<void> Add(PackChunkType type, int id, uint8[] data, PackCompression compression)
	{
		if (id < 0 || id > 0xFFFF)
			return error("The chunk ID " + id + " does not fit into 16 bits.", (int)ErrorKind.InvalidPack);

		if (Contains(type, id))
			return error("The pack already has a chunk of type " + PackChunkTypeName(type) + " with the ID " + id + ".", (int)ErrorKind.InvalidPack);

		_chunks.Add(PackChunk { Type = type, Id = (uint16)id, Packed = try PackCompressor.Compress(compression, data), UnpackedSize = data.Length, Compression = compression });

		return;
	}

	/// Adds a chunk with the compression which gives the smallest result.
	Error<void> AddBest(PackChunkType type, int id, uint8[] data)
	{
		var best = PackCompressor.Best(data, AllowDeflate);

		if (id < 0 || id > 0xFFFF)
			return error("The chunk ID " + id + " does not fit into 16 bits.", (int)ErrorKind.InvalidPack);

		if (Contains(type, id))
			return error("The pack already has a chunk of type " + PackChunkTypeName(type) + " with the ID " + id + ".", (int)ErrorKind.InvalidPack);

		// keep the already packed bytes instead of packing twice
		_chunks.Add(PackChunk { Type = type, Id = (uint16)id, Packed = best.Data, UnpackedSize = data.Length, Compression = best.Compression });

		return;
	}

	uint8[] ToArray()
	{
		var writer = ByteWriter.Create();
		var entries = List<PackEntry>.Create();

		writer.Bytes(new uint8[PackHeaderSize]);

		foreach (var chunk in SortArray(ArrayOf(_chunks), CompareChunks))
		{
			writer.Align(4);
			entries.Add(PackEntry
			{
				Type = chunk.Type,
				Id = chunk.Id,
				Offset = (uint32)writer.Length(),
				PackedSize = (uint32)chunk.Packed.Length,
				UnpackedSize = (uint32)chunk.UnpackedSize,
				Compression = chunk.Compression,
				Crc16 = Crc16(chunk.Packed)
			});
			writer.Bytes(chunk.Packed);
		}

		writer.Align(4);

		int tocOffset = writer.Length();
		var entryBytes = new uint8[PackEntrySize];

		foreach (var entry in entries)
		{
			entry.Write(entryBytes, 0);
			writer.Bytes(entryBytes);
		}

		var result = writer.ToArray();
		var header = PackHeader
		{
			FormatVersion = 0, ProfileId = ProfileId, Flags = Flags, TocCount = (uint16)entries.Count(), TocOffset = (uint32)tocOffset,
			LayoutHash = LayoutHash, MaxThreads = MaxThreads, MaxChainSteps = MaxChainSteps, MaxScreenDepth = MaxScreenDepth,
			MaxPendingEvents = MaxPendingEvents, GlobalFlags = GlobalFlags, GlobalVars = GlobalVars, GlobalVars32 = GlobalVars32,
			NativeCount = NativeCount
		};

		header.Write(result);

		return result;
	}

	Error<void> Save(string path)
	{
		return File.WriteAllBytes(path, ToArray());
	}
}

/// By type, then by ID (C#: OrderBy(Type).ThenBy(Id)).
int CompareChunks(PackChunk a, PackChunk b)
{
	if (a.Type != b.Type)
		return (int)a.Type < (int)b.Type ? -1 : 1;

	return CompareInt((int)a.Id, (int)b.Id);
}
