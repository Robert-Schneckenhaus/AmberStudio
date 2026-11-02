// The compressions of spec section 9.3.

namespace Amber.Pack.PackCompressor;

using System;
using Amber.Base;

Error<uint8[]> Compress(PackCompression compression, uint8[] data)
{
	switch (compression)
	{
		case PackCompression.None:
			return data.Clone();
		case PackCompression.Rle0:
			return CompressRle0(data);
		case PackCompression.Deflate:
			return DeflateRaw(data);
		default:
			return error("The compression " + (int)compression + " is not supported.", (int)ErrorKind.InvalidPack);
	}
}

Error<uint8[]> Decompress(PackCompression compression, uint8[] packed, int unpackedSize)
{
	uint8[] result;

	switch (compression)
	{
		case PackCompression.None:
			result = packed.Clone();
			break;
		case PackCompression.Rle0:
			result = try DecompressRle0(packed, unpackedSize);
			break;
		case PackCompression.Deflate:
			result = try DecompressDeflate(packed, unpackedSize);
			break;
		default:
			return error("The compression " + (int)compression + " is not supported.", (int)ErrorKind.InvalidPack);
	}

	if (result.Length != unpackedSize)
		return error("A chunk has " + result.Length + " bytes after unpacking instead of " + unpackedSize + ".", (int)ErrorKind.InvalidPack);

	return result;
}

struct Packed
{
	PackCompression Compression;
	uint8[] Data;
}

/// The smallest of all compressions (none if nothing is smaller).
Packed Best(uint8[] data, bool allowDeflate)
{
	var best = Packed { Compression = PackCompression.None, Data = data.Clone() };
	var rle = CompressRle0(data);

	if (rle.Length < best.Data.Length)
		best = Packed { Compression = PackCompression.Rle0, Data = rle };

	if (allowDeflate)
	{
		var deflated = DeflateRaw(data);

		if (deflated.Length < best.Data.Length)
			best = Packed { Compression = PackCompression.Deflate, Data = deflated };
	}

	return best;
}

/// A zero byte is followed by the number of further zeros (a run of n zeros is 0x00 n-1), all other bytes stay.
uint8[] CompressRle0(uint8[] data)
{
	var result = ByteWriter.Create();
	int zeros = 0;

	foreach (var value in data)
	{
		if (value == 0)
		{
			zeros += 1;
			continue;
		}

		FlushZeros(result, zeros);
		zeros = 0;
		result.Byte((int)value);
	}

	FlushZeros(result, zeros);

	return result.ToArray();
}

void FlushZeros(ByteWriter result, int zeros)
{
	int rest = zeros;

	while (rest > 0)
	{
		int run = Math.Min(rest, 256);

		result.Byte(0);
		result.Byte(run - 1);
		rest -= run;
	}
}

Error<uint8[]> DecompressRle0(uint8[] packed, int unpackedSize)
{
	var result = ByteWriter.Create();

	for (var i = 0; i < packed.Length; i += 1)
	{
		if (packed[i] != 0)
		{
			result.Byte((int)packed[i]);
			continue;
		}

		if (i + 1 >= packed.Length)
			return error("An RLE0 chunk ends inside a zero run.", (int)ErrorKind.InvalidPack);

		i += 1;

		int count = (int)packed[i] + 1;

		if (result.Length() + count > unpackedSize)
			return error("An RLE0 chunk is longer than its unpacked size.", (int)ErrorKind.InvalidPack);

		for (var z = 0; z < count; z += 1)
			result.Byte(0);
	}

	return result.ToArray();
}

Error<uint8[]> DecompressDeflate(uint8[] packed, int unpackedSize)
{
	var inflated = InflateRaw(packed, unpackedSize + 1);

	if (inflated is uint8[] data)
	{
		if (data.Length < unpackedSize)
			return error("A deflate chunk is shorter than its unpacked size.", (int)ErrorKind.InvalidPack);

		if (data.Length > unpackedSize)
			return error("A deflate chunk is longer than its unpacked size.", (int)ErrorKind.InvalidPack);

		return data;
	}

	return error("A deflate chunk is broken: " + inflated.Message, (int)ErrorKind.InvalidPack);
}
