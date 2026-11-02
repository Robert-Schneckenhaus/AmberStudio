// Big endian bytes (C#: BinaryPrimitives, MemoryStream): a growable byte buffer with word/dword writers, and bounds checked
// readers.

namespace Amber.Base;

using System;

/// A growable byte buffer (a handle to shared storage like List<T>).
struct ByteWriter
{
	List<uint8> _bytes;

	static ByteWriter Create()
	{
		return ByteWriter { _bytes = List<uint8>.Create() };
	}

	int Length()
	{
		return _bytes.Count();
	}

	void Byte(int value)
	{
		_bytes.Add((uint8)(value & 0xFF));
	}

	/// 16 bit big endian (the lowest 16 bits of the value).
	void Word(int value)
	{
		_bytes.Add((uint8)((value >> 8) & 0xFF));
		_bytes.Add((uint8)(value & 0xFF));
	}

	/// 32 bit big endian (the lowest 32 bits of the value).
	void Dword(int64 value)
	{
		_bytes.Add((uint8)((value >> 24) & 0xFF));
		_bytes.Add((uint8)((value >> 16) & 0xFF));
		_bytes.Add((uint8)((value >> 8) & 0xFF));
		_bytes.Add((uint8)(value & 0xFF));
	}

	void Bytes(uint8[] data)
	{
		if (data == null)
			return;

		for (var i = 0; i < data.Length; i += 1)
			_bytes.Add(data[i]);
	}

	void BytesRange(uint8[] data, int start, int count)
	{
		for (var i = 0; i < count; i += 1)
			_bytes.Add(data[start + i]);
	}

	/// Zero bytes up to the next multiple of 'alignment'.
	void Align(int alignment)
	{
		while (_bytes.Count() % alignment != 0)
			_bytes.Add(0);
	}

	/// Overwrites a word at a byte offset that was already written.
	void SetWord(int offset, int value)
	{
		_bytes.Set(offset, (uint8)((value >> 8) & 0xFF));
		_bytes.Set(offset + 1, (uint8)(value & 0xFF));
	}

	void SetDword(int offset, int64 value)
	{
		_bytes.Set(offset, (uint8)((value >> 24) & 0xFF));
		_bytes.Set(offset + 1, (uint8)((value >> 16) & 0xFF));
		_bytes.Set(offset + 2, (uint8)((value >> 8) & 0xFF));
		_bytes.Set(offset + 3, (uint8)(value & 0xFF));
	}

	uint8[] ToArray()
	{
		var result = _bytes.ToArray();

		if (result == null)
			return new uint8[0];

		return result;
	}
}

/// The unsigned 16 bit big endian value at the byte offset (no bounds check beyond the array's own).
uint16 ReadU16(uint8[] data, int offset)
{
	return (uint16)(((int)data[offset] << 8) | (int)data[offset + 1]);
}

uint32 ReadU32(uint8[] data, int offset)
{
	return ((uint32)data[offset] << 24) | ((uint32)data[offset + 1] << 16) | ((uint32)data[offset + 2] << 8) | (uint32)data[offset + 3];
}

void WriteU16(uint8[] data, int offset, int value)
{
	data[offset] = (uint8)((value >> 8) & 0xFF);
	data[offset + 1] = (uint8)(value & 0xFF);
}

void WriteU32(uint8[] data, int offset, int64 value)
{
	data[offset] = (uint8)((value >> 24) & 0xFF);
	data[offset + 1] = (uint8)((value >> 16) & 0xFF);
	data[offset + 2] = (uint8)((value >> 8) & 0xFF);
	data[offset + 3] = (uint8)(value & 0xFF);
}

/// A copy of a part of an array (C#: data[start..(start + count)]).
uint8[] Slice(uint8[] data, int start, int count)
{
	var result = new uint8[count];

	if (count > 0)
		Array.Copy(data, start, result, 0, count);

	return result;
}

/// Both arrays have the same bytes (null counts as empty).
bool SameBytes(uint8[] a, uint8[] b)
{
	int la = a == null ? 0 : a.Length;
	int lb = b == null ? 0 : b.Length;

	if (la != lb)
		return false;

	for (var i = 0; i < la; i += 1)
	{
		if (a[i] != b[i])
			return false;
	}

	return true;
}

/// The array starts with the bytes of the (ASCII) text.
bool StartsWithAscii(uint8[] data, string prefix)
{
	if (data == null || data.Length < prefix.Length)
		return false;

	for (var i = 0; i < prefix.Length; i += 1)
	{
		if (data[i] != prefix[i])
			return false;
	}

	return true;
}

uint8[] Concat(uint8[] a, uint8[] b)
{
	var result = new uint8[a.Length + b.Length];

	Array.Copy(a, 0, result, 0, a.Length);
	Array.Copy(b, 0, result, a.Length, b.Length);

	return result;
}

/// The bytes of a UTF-8 string.
uint8[] Utf8Bytes(string text)
{
	return Encoding.UTF8().GetBytes(text);
}

/// A string from UTF-8 bytes (invalid sequences are not checked).
string Utf8String(uint8[] data)
{
	if (data == null || data.Length == 0)
		return "";

	return string.FromBytes(data);
}
