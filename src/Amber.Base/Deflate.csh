// Raw DEFLATE (RFC 1951) without a zlib or gzip header (C#: System.IO.Compression.DeflateStream). CShift's standard library
// has no compression, so both directions are written here:
//
//   InflateRaw: stored, fixed and dynamic Huffman blocks (reads every valid stream, also the ones .NET/zlib write).
//   DeflateRaw: LZ77 with hash chains and lazy matching, then one block with the cheapest of stored, fixed and dynamic
//   Huffman codes. The output is a valid stream but not byte-identical to zlib's.

namespace Amber.Base;

using System;

// ---------------------------------------------------------------------------------------------------------------------
// Tables of the format
// ---------------------------------------------------------------------------------------------------------------------

const ReadOnlySlice<int> DeflateLengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
const ReadOnlySlice<int> DeflateLengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
const ReadOnlySlice<int> DeflateDistanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
const ReadOnlySlice<int> DeflateDistanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
/// The order in which the code lengths of the code length alphabet are stored.
const ReadOnlySlice<int> DeflateCodeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

// ---------------------------------------------------------------------------------------------------------------------
// Inflate
// ---------------------------------------------------------------------------------------------------------------------

/// A canonical Huffman code for decoding: the number of codes of each length and the symbols in code order.
struct HuffmanDecoder
{
	int[] Counts;
	int[] Symbols;
}

Error<HuffmanDecoder> BuildDecoder(int[] lengths, int count)
{
	var counts = new int[16];
	var symbols = new int[count];

	for (var i = 0; i < count; i += 1)
		counts[lengths[i]] += 1;

	counts[0] = 0;

	// an over-subscribed code is invalid (an incomplete one is allowed, like in zlib's puff)
	int left = 1;

	for (var length = 1; length < 16; length += 1)
	{
		left = left * 2 - counts[length];

		if (left < 0)
			return error("over-subscribed Huffman code", (int)ErrorKind.InvalidData);
	}

	var offsets = new int[16];

	for (var length = 1; length < 15; length += 1)
		offsets[length + 1] = offsets[length] + counts[length];

	for (var i = 0; i < count; i += 1)
	{
		if (lengths[i] != 0)
		{
			symbols[offsets[lengths[i]]] = i;
			offsets[lengths[i]] += 1;
		}
	}

	return HuffmanDecoder { Counts = counts, Symbols = symbols };
}

struct BitReader
{
	uint8[] Data;
	int Position;
	int BitBuffer;
	int BitCount;

	Error<int> Bits(int count)
	{
		int value = BitBuffer;

		while (BitCount < count)
		{
			if (Position >= Data.Length)
				return error("the stream is truncated", (int)ErrorKind.InvalidData);

			value = value | ((int)Data[Position] << BitCount);
			Position += 1;
			BitCount += 8;
		}

		BitBuffer = value >> count;
		BitCount -= count;

		return value & ((1 << count) - 1);
	}

	Error<int> Decode(HuffmanDecoder decoder)
	{
		int code = 0;
		int first = 0;
		int index = 0;

		for (var length = 1; length < 16; length += 1)
		{
			code = code | try Bits(1);

			int count = decoder.Counts[length];

			if (code - count < first)
				return decoder.Symbols[index + (code - first)];

			index += count;
			first += count;
			first = first << 1;
			code = code << 1;
		}

		return error("bad Huffman code", (int)ErrorKind.InvalidData);
	}

	void AlignToByte()
	{
		BitBuffer = 0;
		BitCount = 0;
	}
}

/// The bytes of a raw deflate stream; stops after 'limit' bytes (to tell a too long stream from a correct one).
Error<uint8[]> InflateRaw(uint8[] data, int limit)
{
	var output = List<uint8>.Create();
	var reader = BitReader { Data = data, Position = 0, BitBuffer = 0, BitCount = 0 };
	bool last = false;

	while (!last && output.Count() < limit)
	{
		last = try reader.Bits(1) == 1;

		int type = try reader.Bits(2);

		if (type == 0)
		{
			reader.AlignToByte();

			if (reader.Position + 4 > data.Length)
				return error("the stream is truncated", (int)ErrorKind.InvalidData);

			int length = (int)data[reader.Position] | ((int)data[reader.Position + 1] << 8);
			int inverse = (int)data[reader.Position + 2] | ((int)data[reader.Position + 3] << 8);

			if (length != (~inverse & 0xFFFF))
				return error("a stored block has a wrong length", (int)ErrorKind.InvalidData);

			reader.Position += 4;

			if (reader.Position + length > data.Length)
				return error("the stream is truncated", (int)ErrorKind.InvalidData);

			for (var i = 0; i < length && output.Count() < limit; i += 1)
				output.Add(data[reader.Position + i]);

			reader.Position += length;
		}
		else if (type == 1)
		{
			try InflateBlock(ref reader, output, FixedLiteralDecoder, FixedDistanceDecoder, limit);
		}
		else if (type == 2)
		{
			int literalCount = try reader.Bits(5) + 257;
			int distanceCount = try reader.Bits(5) + 1;
			int codeLengthCount = try reader.Bits(4) + 4;

			if (literalCount > 286 || distanceCount > 30)
				return error("bad code counts", (int)ErrorKind.InvalidData);

			var codeLengthLengths = new int[19];

			for (var i = 0; i < codeLengthCount; i += 1)
				codeLengthLengths[DeflateCodeLengthOrder[i]] = try reader.Bits(3);

			var codeLengthDecoder = try BuildDecoder(codeLengthLengths, 19);
			var lengths = new int[literalCount + distanceCount];
			int index = 0;

			while (index < literalCount + distanceCount)
			{
				int symbol = try reader.Decode(codeLengthDecoder);

				if (symbol < 16)
				{
					lengths[index] = symbol;
					index += 1;
					continue;
				}

				int value = 0;
				int repeat;

				if (symbol == 16)
				{
					if (index == 0)
						return error("a repeat without a previous length", (int)ErrorKind.InvalidData);

					value = lengths[index - 1];
					repeat = 3 + try reader.Bits(2);
				}
				else if (symbol == 17)
				{
					repeat = 3 + try reader.Bits(3);
				}
				else
				{
					repeat = 11 + try reader.Bits(7);
				}

				if (index + repeat > literalCount + distanceCount)
					return error("too many code lengths", (int)ErrorKind.InvalidData);

				for (var i = 0; i < repeat; i += 1)
				{
					lengths[index] = value;
					index += 1;
				}
			}

			if (lengths[256] == 0)
				return error("no end of block code", (int)ErrorKind.InvalidData);

			var literalLengths = new int[literalCount];
			var distanceLengths = new int[distanceCount];

			Array.Copy(lengths, 0, literalLengths, 0, literalCount);
			Array.Copy(lengths, literalCount, distanceLengths, 0, distanceCount);

			var literalDecoder = try BuildDecoder(literalLengths, literalCount);
			var distanceDecoder = try BuildDecoder(distanceLengths, distanceCount);

			try InflateBlock(ref reader, output, literalDecoder, distanceDecoder, limit);
		}
		else
		{
			return error("bad block type", (int)ErrorKind.InvalidData);
		}
	}

	return ArrayOf(output);
}

Error<void> InflateBlock(ref BitReader reader, List<uint8> output, HuffmanDecoder literals, HuffmanDecoder distances, int limit)
{
	while (true)
	{
		int symbol = try reader.Decode(literals);

		if (symbol < 256)
		{
			output.Add((uint8)symbol);

			if (output.Count() >= limit)
				return;

			continue;
		}

		if (symbol == 256)
			return;

		symbol -= 257;

		if (symbol >= 29)
			return error("bad length code", (int)ErrorKind.InvalidData);

		int length = DeflateLengthBase[symbol] + try reader.Bits(DeflateLengthExtra[symbol]);
		int distanceSymbol = try reader.Decode(distances);

		if (distanceSymbol >= 30)
			return error("bad distance code", (int)ErrorKind.InvalidData);

		int distance = DeflateDistanceBase[distanceSymbol] + try reader.Bits(DeflateDistanceExtra[distanceSymbol]);

		if (distance > output.Count())
			return error("a distance too far back", (int)ErrorKind.InvalidData);

		int start = output.Count() - distance;

		for (var i = 0; i < length; i += 1)
		{
			output.Add(output.Get(start + i));

			if (output.Count() >= limit)
				return;
		}
	}

	return;
}

int[] FixedLiteralLengths()
{
	var lengths = new int[288];

	for (var i = 0; i < 288; i += 1)
		lengths[i] = i < 144 ? 8 : (i < 256 ? 9 : (i < 280 ? 7 : 8));

	return lengths;
}

int[] FixedDistanceLengths()
{
	var lengths = new int[30];

	for (var i = 0; i < 30; i += 1)
		lengths[i] = 5;

	return lengths;
}

HuffmanDecoder FixedLiteralDecoder = FixedDecoder(FixedLiteralLengths(), 288);
HuffmanDecoder FixedDistanceDecoder = FixedDecoder(FixedDistanceLengths(), 30);

HuffmanDecoder FixedDecoder(int[] lengths, int count)
{
	var result = BuildDecoder(lengths, count);

	if (result is HuffmanDecoder decoder)
		return decoder;

	return new HuffmanDecoder();
}

// ---------------------------------------------------------------------------------------------------------------------
// Deflate
// ---------------------------------------------------------------------------------------------------------------------

/// Writes bits least significant first, like the deflate format needs.
struct BitWriter
{
	List<uint8> Bytes;
	int BitBuffer;
	int BitCount;

	void Bits(int value, int count)
	{
		BitBuffer = BitBuffer | ((value & ((1 << count) - 1)) << BitCount);
		BitCount += count;

		while (BitCount >= 8)
		{
			Bytes.Add((uint8)(BitBuffer & 0xFF));
			BitBuffer = BitBuffer >> 8;
			BitCount -= 8;
		}
	}

	/// A Huffman code (written from its most significant bit on).
	void Code(int code, int length)
	{
		int reversed = 0;

		for (var i = 0; i < length; i += 1)
			reversed = reversed | (((code >> i) & 1) << (length - 1 - i));

		Bits(reversed, length);
	}

	void Flush()
	{
		if (BitCount > 0)
			Bytes.Add((uint8)(BitBuffer & 0xFF));

		BitBuffer = 0;
		BitCount = 0;
	}
}

/// One symbol of the LZ77 pass: a literal byte (Length 0) or a match.
struct LzToken
{
	int Literal;
	int Length;
	int Distance;
}

const int DeflateWindow = 32768;
const int DeflateMaxMatch = 258;
const int DeflateMinMatch = 3;
const int DeflateHashSize = 32768;
const int DeflateMaxChain = 256;

int DeflateHash(uint8[] data, int position)
{
	return (((int)data[position] << 10) ^ ((int)data[position + 1] << 5) ^ (int)data[position + 2]) & (DeflateHashSize - 1);
}

/// The raw deflate stream of the bytes.
uint8[] DeflateRaw(uint8[] data)
{
	var tokens = FindMatches(data);
	var literalFrequencies = new int[286];
	var distanceFrequencies = new int[30];

	foreach (var token in tokens)
	{
		if (token.Length == 0)
		{
			literalFrequencies[token.Literal] += 1;
		}
		else
		{
			literalFrequencies[257 + LengthSymbol(token.Length)] += 1;
			distanceFrequencies[DistanceSymbol(token.Distance)] += 1;
		}
	}

	literalFrequencies[256] = 1;

	var literalLengths = HuffmanLengths(literalFrequencies, 15);
	var distanceLengths = HuffmanLengths(distanceFrequencies, 15);

	// the format needs at least one distance code
	bool anyDistance = false;

	foreach (var length in distanceLengths)
	{
		if (length > 0)
			anyDistance = true;
	}

	if (!anyDistance)
		distanceLengths[0] = 1;

	var dynamicStream = WriteHuffmanBlock(tokens, literalLengths, distanceLengths, true);
	var fixedLiterals = FixedLiteralLengths();
	var fixedStream = WriteHuffmanBlock(tokens, fixedLiterals, FixedDistanceLengths(), false);
	var storedStream = WriteStored(data);
	var best = dynamicStream;

	if (fixedStream.Length < best.Length)
		best = fixedStream;

	if (storedStream.Length < best.Length)
		best = storedStream;

	return best;
}

uint8[] WriteStored(uint8[] data)
{
	var writer = ByteWriter.Create();
	int position = 0;

	while (true)
	{
		int length = Math.Min(65535, data.Length - position);
		bool last = position + length >= data.Length;

		writer.Byte(last ? 1 : 0);
		writer.Byte(length & 0xFF);
		writer.Byte(length >> 8);
		writer.Byte(~length & 0xFF);
		writer.Byte((~length >> 8) & 0xFF);
		writer.BytesRange(data, position, length);
		position += length;

		if (last)
			break;
	}

	return writer.ToArray();
}

List<LzToken> FindMatches(uint8[] data)
{
	var tokens = List<LzToken>.Create();
	var head = new int[DeflateHashSize];
	var previous = new int[DeflateWindow];

	for (var i = 0; i < head.Length; i += 1)
		head[i] = -1;

	int position = 0;

	while (position < data.Length)
	{
		var match = LongestMatch(data, position, head, previous);

		if (match.Length >= DeflateMinMatch && position + 1 < data.Length)
		{
			// lazy matching: a longer match at the next position wins, the current byte becomes a literal
			Insert(data, position, head, previous);

			var next = LongestMatch(data, position + 1, head, previous);

			if (next.Length > match.Length)
			{
				tokens.Add(LzToken { Literal = (int)data[position], Length = 0, Distance = 0 });
				position += 1;
				match = next;
			}
			else
			{
				tokens.Add(match);

				for (var i = 1; i < match.Length; i += 1)
					Insert(data, position + i, head, previous);

				position += match.Length;
				continue;
			}
		}

		if (match.Length >= DeflateMinMatch)
		{
			tokens.Add(match);

			for (var i = 0; i < match.Length; i += 1)
				Insert(data, position + i, head, previous);

			position += match.Length;
		}
		else
		{
			tokens.Add(LzToken { Literal = (int)data[position], Length = 0, Distance = 0 });
			Insert(data, position, head, previous);
			position += 1;
		}
	}

	return tokens;
}

void Insert(uint8[] data, int position, int[] head, int[] previous)
{
	if (position + 2 >= data.Length)
		return;

	int hash = DeflateHash(data, position);

	previous[position & (DeflateWindow - 1)] = head[hash];
	head[hash] = position;
}

LzToken LongestMatch(uint8[] data, int position, int[] head, int[] previous)
{
	var best = LzToken { Literal = 0, Length = 0, Distance = 0 };

	if (position + 2 >= data.Length)
		return best;

	int candidate = head[DeflateHash(data, position)];
	int chain = 0;
	int maxLength = Math.Min(DeflateMaxMatch, data.Length - position);

	while (candidate >= 0 && position - candidate <= DeflateWindow && chain < DeflateMaxChain)
	{
		if (candidate < position)
		{
			int length = 0;

			while (length < maxLength && data[candidate + length] == data[position + length])
				length += 1;

			if (length > best.Length)
			{
				best = LzToken { Literal = 0, Length = length, Distance = position - candidate };

				if (length == maxLength)
					break;
			}
		}

		int next = previous[candidate & (DeflateWindow - 1)];

		if (next >= candidate)
			break;

		candidate = next;
		chain += 1;
	}

	if (best.Length < DeflateMinMatch)
		best.Length = 0;

	return best;
}

int LengthSymbol(int length)
{
	for (var i = DeflateLengthBase.Length - 1; i >= 0; i -= 1)
	{
		if (length >= DeflateLengthBase[i])
			return i;
	}

	return 0;
}

int DistanceSymbol(int distance)
{
	for (var i = DeflateDistanceBase.Length - 1; i >= 0; i -= 1)
	{
		if (distance >= DeflateDistanceBase[i])
			return i;
	}

	return 0;
}

/// Canonical codes for the code lengths.
int[] CanonicalCodes(int[] lengths)
{
	var counts = new int[16];
	var next = new int[16];
	var codes = new int[lengths.Length];

	foreach (var length in lengths)
		counts[length] += 1;

	counts[0] = 0;

	int code = 0;

	for (var bits = 1; bits < 16; bits += 1)
	{
		code = (code + counts[bits - 1]) << 1;
		next[bits] = code;
	}

	for (var i = 0; i < lengths.Length; i += 1)
	{
		if (lengths[i] != 0)
		{
			codes[i] = next[lengths[i]];
			next[lengths[i]] += 1;
		}
	}

	return codes;
}

/// Code lengths of a Huffman code for the frequencies, at most 'maxBits' long (the frequencies are halved until the tree is
/// flat enough).
int[] HuffmanLengths(int[] frequencies, int maxBits)
{
	var weights = frequencies.Clone();

	while (true)
	{
		var lengths = HuffmanTreeLengths(weights);
		int longest = 0;

		foreach (var length in lengths)
			longest = Math.Max(longest, length);

		if (longest <= maxBits)
			return lengths;

		for (var i = 0; i < weights.Length; i += 1)
		{
			if (weights[i] > 0)
				weights[i] = Math.Max(1, weights[i] / 2);
		}
	}

	return new int[frequencies.Length];
}

/// The depths of the symbols in a Huffman tree (0 for unused symbols; a single used symbol gets length 1).
int[] HuffmanTreeLengths(int[] weights)
{
	int count = weights.Length;
	var lengths = new int[count];
	var nodeWeight = List<int64>.Create();
	var nodeParent = List<int>.Create();
	var active = List<int>.Create();

	for (var i = 0; i < count; i += 1)
	{
		nodeWeight.Add((int64)weights[i]);
		nodeParent.Add(-1);

		if (weights[i] > 0)
			active.Add(i);
	}

	if (active.Count() == 0)
		return lengths;

	if (active.Count() == 1)
	{
		lengths[active.Get(0)] = 1;

		return lengths;
	}

	while (active.Count() > 1)
	{
		int first = TakeLightest(active, nodeWeight);
		int second = TakeLightest(active, nodeWeight);
		int parent = nodeWeight.Count();

		nodeWeight.Add(nodeWeight.Get(first) + nodeWeight.Get(second));
		nodeParent.Add(-1);
		nodeParent.Set(first, parent);
		nodeParent.Set(second, parent);
		active.Add(parent);
	}

	for (var i = 0; i < count; i += 1)
	{
		if (weights[i] == 0)
			continue;

		int depth = 0;
		int node = i;

		while (nodeParent.Get(node) >= 0)
		{
			depth += 1;
			node = nodeParent.Get(node);
		}

		lengths[i] = depth;
	}

	return lengths;
}

int TakeLightest(List<int> active, List<int64> weights)
{
	int best = 0;

	for (var i = 1; i < active.Count(); i += 1)
	{
		if (weights.Get(active.Get(i)) < weights.Get(active.Get(best)))
			best = i;
	}

	int node = active.Get(best);

	active.RemoveAt(best);

	return node;
}

/// One block (the last one) with Huffman codes: dynamic (with the code tables) or fixed.
uint8[] WriteHuffmanBlock(List<LzToken> tokens, int[] literalLengths, int[] distanceLengths, bool dynamic)
{
	var writer = BitWriter { Bytes = List<uint8>.Create(), BitBuffer = 0, BitCount = 0 };

	writer.Bits(1, 1);
	writer.Bits(dynamic ? 2 : 1, 2);

	if (dynamic)
		WriteCodeTables(ref writer, literalLengths, distanceLengths);

	var literalCodes = CanonicalCodes(literalLengths);
	var distanceCodes = CanonicalCodes(distanceLengths);

	foreach (var token in tokens)
	{
		if (token.Length == 0)
		{
			writer.Code(literalCodes[token.Literal], literalLengths[token.Literal]);
			continue;
		}

		int lengthSymbol = LengthSymbol(token.Length);
		int distanceSymbol = DistanceSymbol(token.Distance);

		writer.Code(literalCodes[257 + lengthSymbol], literalLengths[257 + lengthSymbol]);
		writer.Bits(token.Length - DeflateLengthBase[lengthSymbol], DeflateLengthExtra[lengthSymbol]);
		writer.Code(distanceCodes[distanceSymbol], distanceLengths[distanceSymbol]);
		writer.Bits(token.Distance - DeflateDistanceBase[distanceSymbol], DeflateDistanceExtra[distanceSymbol]);
	}

	writer.Code(literalCodes[256], literalLengths[256]);
	writer.Flush();

	return ArrayOf(writer.Bytes);
}

void WriteCodeTables(ref BitWriter writer, int[] literalLengths, int[] distanceLengths)
{
	int literalCount = 286;

	while (literalCount > 257 && literalLengths[literalCount - 1] == 0)
		literalCount -= 1;

	int distanceCount = 30;

	while (distanceCount > 1 && distanceLengths[distanceCount - 1] == 0)
		distanceCount -= 1;

	var all = new int[literalCount + distanceCount];

	Array.Copy(literalLengths, 0, all, 0, literalCount);
	Array.Copy(distanceLengths, 0, all, literalCount, distanceCount);

	// run length coding of the code lengths with the symbols 16 (repeat previous), 17 and 18 (zeros)
	var symbols = List<int>.Create();
	var extras = List<int>.Create();
	int i = 0;

	while (i < all.Length)
	{
		int value = all[i];
		int run = 1;

		while (i + run < all.Length && all[i + run] == value)
			run += 1;

		if (value == 0 && run >= 3)
		{
			int length = Math.Min(run, 138);

			if (length >= 11)
			{
				symbols.Add(18);
				extras.Add(length - 11);
			}
			else
			{
				symbols.Add(17);
				extras.Add(length - 3);
			}

			i += length;
			continue;
		}

		if (value != 0 && run >= 4)
		{
			symbols.Add(value);
			extras.Add(0);

			int length = Math.Min(run - 1, 6);

			symbols.Add(16);
			extras.Add(length - 3);
			i += 1 + length;
			continue;
		}

		symbols.Add(value);
		extras.Add(0);
		i += 1;
	}

	var codeFrequencies = new int[19];

	foreach (var symbol in symbols)
		codeFrequencies[symbol] += 1;

	var codeLengths = HuffmanLengths(codeFrequencies, 7);

	// zlib rejects an incomplete code length code: a single used symbol gets a second, unused one of the same length
	int usedCodes = 0;

	foreach (var length in codeLengths)
	{
		if (length > 0)
			usedCodes += 1;
	}

	if (usedCodes == 1)
	{
		for (var k = 0; k < 19; k += 1)
		{
			if (codeLengths[k] == 0)
			{
				codeLengths[k] = 1;
				break;
			}
		}
	}
	var codeCodes = CanonicalCodes(codeLengths);
	int codeLengthCount = 19;

	while (codeLengthCount > 4 && codeLengths[DeflateCodeLengthOrder[codeLengthCount - 1]] == 0)
		codeLengthCount -= 1;

	writer.Bits(literalCount - 257, 5);
	writer.Bits(distanceCount - 1, 5);
	writer.Bits(codeLengthCount - 4, 4);

	for (var k = 0; k < codeLengthCount; k += 1)
		writer.Bits(codeLengths[DeflateCodeLengthOrder[k]], 3);

	for (var k = 0; k < symbols.Count(); k += 1)
	{
		int symbol = symbols.Get(k);

		writer.Code(codeCodes[symbol], codeLengths[symbol]);

		if (symbol == 16)
			writer.Bits(extras.Get(k), 2);
		else if (symbol == 17)
			writer.Bits(extras.Get(k), 3);
		else if (symbol == 18)
			writer.Bits(extras.Get(k), 7);
	}
}
