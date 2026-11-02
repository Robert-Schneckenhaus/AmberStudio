// Latin-1 (ISO 8859-1): the texts of packs and chunks are Latin-1 bytes, CShift strings are UTF-8. Every Latin-1 byte is the
// code point of the same value.

namespace Amber.Base;

using System;

/// The code point that starts at the byte offset of a UTF-8 string and the length of its encoding.
struct CodePoint
{
	int Value;
	int Length;
}

CodePoint DecodeUtf8(string text, int offset)
{
	int first = (int)text[offset];

	if (first < 0x80)
		return CodePoint { Value = first, Length = 1 };

	int length = first >= 0xF0 ? 4 : first >= 0xE0 ? 3 : first >= 0xC0 ? 2 : 1;

	if (length == 1 || offset + length > text.Length)
		return CodePoint { Value = 0xFFFD, Length = 1 };

	int value = first & (0x3F >> (length - 1));

	for (var i = 1; i < length; i += 1)
		value = (value << 6) | ((int)text[offset + i] & 0x3F);

	return CodePoint { Value = value, Length = length };
}

/// The first code point of the text above 0xFF (not Latin-1), or -1.
int FirstNonLatin1(string text)
{
	int offset = 0;

	while (offset < text.Length)
	{
		var point = DecodeUtf8(text, offset);

		if (point.Value > 0xFF)
			return point.Value;

		offset += point.Length;
	}

	return -1;
}

/// The code point as a string (UTF-8).
string CodePointText(int value)
{
	var bytes = List<uint8>.Create();

	if (value < 0x80)
	{
		bytes.Add((uint8)value);
	}
	else if (value < 0x800)
	{
		bytes.Add((uint8)(0xC0 | (value >> 6)));
		bytes.Add((uint8)(0x80 | (value & 0x3F)));
	}
	else if (value < 0x10000)
	{
		bytes.Add((uint8)(0xE0 | (value >> 12)));
		bytes.Add((uint8)(0x80 | ((value >> 6) & 0x3F)));
		bytes.Add((uint8)(0x80 | (value & 0x3F)));
	}
	else
	{
		bytes.Add((uint8)(0xF0 | (value >> 18)));
		bytes.Add((uint8)(0x80 | ((value >> 12) & 0x3F)));
		bytes.Add((uint8)(0x80 | ((value >> 6) & 0x3F)));
		bytes.Add((uint8)(0x80 | (value & 0x3F)));
	}

	return string.FromBytes(bytes.ToArray());
}

/// The Latin-1 bytes of the text; characters outside of Latin-1 become '?' (C#: Encoding.Latin1.GetBytes).
uint8[] Latin1Bytes(string text)
{
	var bytes = List<uint8>.Create();
	int offset = 0;

	while (offset < text.Length)
	{
		var point = DecodeUtf8(text, offset);

		bytes.Add(point.Value > 0xFF ? (uint8)'?' : (uint8)point.Value);
		offset += point.Length;
	}

	var result = bytes.ToArray();

	return result == null ? new uint8[0] : result;
}

/// The number of Latin-1 bytes of the text (C#: text.Length for a Latin-1 text).
int Latin1Length(string text)
{
	return CharCount(text);
}

/// The text of Latin-1 bytes (C#: Encoding.Latin1.GetString(data, start, count)).
string Latin1String(uint8[] data, int start, int count)
{
	var bytes = List<uint8>.Create();

	for (var i = 0; i < count; i += 1)
	{
		int value = (int)data[start + i];

		if (value < 0x80)
		{
			bytes.Add((uint8)value);
		}
		else
		{
			bytes.Add((uint8)(0xC0 | (value >> 6)));
			bytes.Add((uint8)(0x80 | (value & 0x3F)));
		}
	}

	if (bytes.Count() == 0)
		return "";

	return string.FromBytes(bytes.ToArray());
}

/// The bytes of an ASCII text (C#: Encoding.ASCII.GetBytes; other characters become '?').
uint8[] AsciiBytes(string text)
{
	var bytes = List<uint8>.Create();
	int offset = 0;

	while (offset < text.Length)
	{
		var point = DecodeUtf8(text, offset);

		bytes.Add(point.Value > 0x7F ? (uint8)'?' : (uint8)point.Value);
		offset += point.Length;
	}

	var result = bytes.ToArray();

	return result == null ? new uint8[0] : result;
}

/// The text of ASCII bytes (C#: Encoding.ASCII.GetString; bytes above 127 become '?').
string AsciiString(uint8[] data, int start, int count)
{
	var bytes = new uint8[count];

	for (var i = 0; i < count; i += 1)
		bytes[i] = data[start + i] > 0x7F ? (uint8)'?' : data[start + i];

	if (count == 0)
		return "";

	return string.FromBytes(bytes);
}
