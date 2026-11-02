// Text helpers for what C# does with format strings and a few string methods CShift's standard library does not have
// (yet): hexadecimal and padded numbers, whitespace splitting, UTF-16 like character counts.

namespace Amber.Base;

using System;

/// Upper case hexadecimal digits of the lowest 'digits' nibbles, padded with zeros (C#: value.ToString("X4")). Longer values
/// keep all their digits.
string Hex(uint64 value, int digits)
{
	string result = "";
	uint64 rest = value;

	while (rest != 0 || result.Length < digits)
	{
		int nibble = (int)(rest & 15);

		result = HexDigit(nibble) + result;
		rest = rest >> 4;

		if (rest == 0 && result.Length >= digits)
			break;
	}

	return result;
}

string Hex(int value, int digits)
{
	return Hex((uint64)(uint32)value, digits);
}

string HexDigit(int nibble)
{
	return "0123456789ABCDEF".Substring(nibble, 1);
}

/// The number with at least 'digits' digits, zeros in front (C#: value.ToString("00")).
string ZeroPad(int64 value, int digits)
{
	if (value < 0)
		return "-" + ZeroPad(-value, digits);

	string text = value.ToString();

	while (text.Length < digits)
		text = "0" + text;

	return text;
}

/// C#: $"{text,width}" (right aligned).
string PadLeft(string text, int width)
{
	int length = CharCount(text);
	string result = text;

	for (var i = length; i < width; i += 1)
		result = " " + result;

	return result;
}

/// C#: $"{text,-width}" (left aligned).
string PadRight(string text, int width)
{
	int length = CharCount(text);
	string result = text;

	for (var i = length; i < width; i += 1)
		result += " ";

	return result;
}

/// C#: value.ToString("+#;-#;0").
string SignedText(int64 value)
{
	if (value > 0)
		return "+" + value.ToString();

	return value.ToString();
}

/// The number of characters (code points) of a UTF-8 string; for texts in the Basic Multilingual Plane this is the Length
/// of the same string in C#.
int CharCount(string text)
{
	int count = 0;

	for (var i = 0; i < text.Length; i += 1)
	{
		if (((int)text[i] & 0xC0) != 0x80)
			count += 1;
	}

	return count;
}

bool IsContinuationByte(char c)
{
	return ((int)c & 0xC0) == 0x80;
}

/// C#: text.TrimEnd().
string TrimEnd(string text)
{
	int end = text.Length;

	while (end > 0 && Char.IsWhiteSpace(text[end - 1]))
		end -= 1;

	return text.Substring(0, end);
}

/// C#: text.Split((char[])null, StringSplitOptions.RemoveEmptyEntries): the words between whitespace.
string[] SplitWhitespace(string text)
{
	var parts = List<string>.Create();
	int start = -1;

	for (var i = 0; i <= text.Length; i += 1)
	{
		bool space = i == text.Length || Char.IsWhiteSpace(text[i]);

		if (space)
		{
			if (start >= 0)
			{
				parts.Add(text.Substring(start, i - start));
				start = -1;
			}
		}
		else if (start < 0)
		{
			start = i;
		}
	}

	return parts.ToArray();
}

/// C#: text.Replace("\r\n", "\n").Split('\n', StringSplitOptions.RemoveEmptyEntries).
string[] NonEmptyLines(string text)
{
	var parts = List<string>.Create();

	foreach (var line in text.Replace("\r\n", "\n").Split('\n'))
	{
		if (line.Length > 0)
			parts.Add(line.ToString());
	}

	return parts.ToArray();
}

/// C#: string.Join(separator, parts) for a list.
string JoinList(string separator, List<string> parts)
{
	var builder = StringBuilder.Create();

	for (var i = 0; i < parts.Count(); i += 1)
	{
		if (i > 0)
			builder.Append(separator);

		builder.Append(parts.Get(i));
	}

	return builder.ToString();
}

/// C#: long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out value): optional whitespace around an
/// optional sign and decimal digits.
Optional<int64> TryParseLong(string text)
{
	string trimmed = text.Trim().ToString();

	if (trimmed.Length == 0)
		return null;

	if (trimmed.ParseInt64() is int64 value)
		return value;

	return null;
}

Optional<int> TryParseInt(string text)
{
	if (TryParseLong(text) is int64 value)
	{
		if (value >= int.MinValue && value <= int.MaxValue)
			return (int)value;
	}

	return null;
}

/// Hexadecimal digits without a prefix (C#: Convert.ToInt64(text, 16) / NumberStyles.HexNumber).
Optional<uint64> TryParseHex(string text)
{
	if (text.Length == 0 || text.Length > 16)
		return null;

	uint64 value = 0;

	for (var i = 0; i < text.Length; i += 1)
	{
		if (!Char.IsHexDigit(text[i]))
			return null;

		value = (value << 4) | (uint64)Char.HexValue(text[i]);
	}

	return value;
}

/// C#: bool.TryParse (case-insensitive "true" or "false", surrounding whitespace allowed).
Optional<bool> TryParseBool(string text)
{
	string value = text.Trim().ToLower();

	if (value == "true")
		return true;

	if (value == "false")
		return false;

	return null;
}

/// True if the list contains the text.
bool ContainsText(List<string> list, string text)
{
	for (var i = 0; i < list.Count(); i += 1)
	{
		if (list.Get(i) == text)
			return true;
	}

	return false;
}

/// True if the array (or constant slice) contains the text.
bool ContainsText(ReadOnlySlice<string> items, string text)
{
	foreach (var item in items)
	{
		if (item == text)
			return true;
	}

	return false;
}

/// The position of the text in the list, or -1.
int IndexOfText(List<string> list, string text)
{
	for (var i = 0; i < list.Count(); i += 1)
	{
		if (list.Get(i) == text)
			return i;
	}

	return -1;
}

/// The position of the text in the array (or constant slice), or -1.
int IndexOfText(ReadOnlySlice<string> items, string text)
{
	for (var i = 0; i < items.Length; i += 1)
	{
		if (items[i] == text)
			return i;
	}

	return -1;
}

/// C#: text.Split(separator).ToList(): the parts as strings (empty parts included).
List<string> SplitToList(string text, string separator)
{
	var list = List<string>.Create();

	foreach (var part in text.Split(separator))
		list.Add(part.ToString());

	return list;
}

List<string> ListOf(string[] items)
{
	var list = List<string>.Create();

	list.AddRange(items);

	return list;
}
