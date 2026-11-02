namespace Amber.Pack;

using System;
using Amber.Base;

/// The key of a chunk in the table of contents (type and ID).
struct PackKey : IEquatable<PackKey>, IHashable
{
	int Type;
	int Id;

	bool Equals(PackKey other)
	{
		return Type == other.Type && Id == other.Id;
	}

	int GetHashCode()
	{
		return Type * 65536 + Id;
	}
}

/// Random access to the chunks of a pack (spec section 9.5), from memory or from a file (C#: IPackReader with
/// MemoryPackReader and FilePackReader). Opening reads the header and the table of contents and checks them; a file pack
/// reads every chunk on demand.
struct PackReader
{
	bool _isFile;
	uint8[] _data;
	string _path;
	int64 _length;
	PackHeader Header;
	/// The table of contents, sorted by type and ID.
	PackEntry[] Entries;
	Dictionary<PackKey, PackEntry> _byKey;

	/// A pack in memory.
	static Error<PackReader> FromMemory(uint8[] data)
	{
		var reader = PackReader { _isFile = false, _data = data, _path = null, _length = (int64)data.Length, _byKey = Dictionary<PackKey, PackEntry>.Create() };

		try reader.Open();

		return reader;
	}

	/// A pack file: only the header and the table of contents are read when it is opened, every chunk is read on demand.
	static Error<PackReader> FromFile(string path)
	{
		var reader = PackReader { _isFile = true, _data = null, _path = path, _length = try FileLength(path), _byKey = Dictionary<PackKey, PackEntry>.Create() };

		try reader.Open();

		return reader;
	}

	bool Contains(PackChunkType type, int id)
	{
		return id >= 0 && id <= 0xFFFF && _byKey.ContainsKey(PackKey { Type = (int)type, Id = id });
	}

	/// The unpacked bytes of a chunk: a PackChunkNotFound error if there is none and a PackChecksum error if the stored
	/// checksum does not match.
	Error<uint8[]> Get(PackChunkType type, int id)
	{
		if (!Contains(type, id))
			return error("The pack has no chunk of type " + PackChunkTypeName(type) + " with the ID " + id + ".", (int)ErrorKind.PackChunkNotFound);

		var entry = _byKey.GetOrDefault(PackKey { Type = (int)type, Id = id }, new PackEntry());
		var packed = try Read((int64)entry.Offset, (int)entry.PackedSize);

		if (Crc16(packed) != entry.Crc16)
			return error("The chunk " + PackChunkTypeName(type) + ":" + id + " is damaged (checksum mismatch).", (int)ErrorKind.PackChecksum);

		return PackCompressor.Decompress(entry.Compression, packed, (int)entry.UnpackedSize);
	}

	/// Reads exactly 'length' bytes at the offset.
	Error<uint8[]> Read(int64 offset, int length)
	{
		if (_isFile)
			return ReadFileRange(_path, offset, length);

		if (offset < 0 || offset + (int64)length > (int64)_data.Length)
			return error("A read outside of the pack.", (int)ErrorKind.InvalidPack);

		return Slice(_data, (int)offset, length);
	}

	Error<void> Open()
	{
		if (_length < (int64)PackHeaderSize)
			return error("The file is shorter than the pack header.", (int)ErrorKind.InvalidPack);

		Header = try PackHeader.Read(try Read(0, PackHeaderSize));

		int64 tocEnd = (int64)Header.TocOffset + (int64)Header.TocCount * PackEntrySize;

		if ((int64)Header.TocOffset < (int64)PackHeaderSize || tocEnd > _length)
			return error("The table of contents lies outside of the file.", (int)ErrorKind.InvalidPack);

		var toc = try Read((int64)Header.TocOffset, (int)Header.TocCount * PackEntrySize);
		var entries = List<PackEntry>.Create();

		for (var i = 0; i < (int)Header.TocCount; i += 1)
		{
			var entry = PackEntry.Read(toc, i * PackEntrySize);

			if (entry.Offset % 4 != 0)
				return error("The chunk " + entry.TypeText() + ":" + entry.Id + " is not aligned to 4 bytes.", (int)ErrorKind.InvalidPack);

			if (entry.Offset < (uint32)PackHeaderSize || (int64)entry.Offset + (int64)entry.PackedSize > (int64)Header.TocOffset)
				return error("The chunk " + entry.TypeText() + ":" + entry.Id + " lies outside of the data area.", (int)ErrorKind.InvalidPack);

			var key = PackKey { Type = (int)entry.Type, Id = (int)entry.Id };

			if (_byKey.ContainsKey(key))
				return error("The chunk " + entry.TypeText() + ":" + entry.Id + " is listed twice.", (int)ErrorKind.InvalidPack);

			_byKey.Set(key, entry);
			entries.Add(entry);
		}

		Entries = ArrayOf(entries);

		return;
	}
}
