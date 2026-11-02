// The checks of the tests (the xUnit Assert class). CShift has no exceptions: every check returns an Error<void>, and a test
// writes 'try Assert.Equal(1, value);' so the first failed check ends the test with its message, like the exception of a
// failed xUnit assertion. There is no caller information either, so a failure names the number of the check in the test.

namespace Amber.Tests.Assert;

using System;
using Amber.Base;

/// The number of the last check of the running test; the runner resets it before every test.
int CheckNumber = 0;

Error<void> Failure(string message)
{
	return error("check " + CheckNumber + ": " + message, -1);
}

Error<void> True(bool condition)
{
	return True(condition, "expected true");
}

Error<void> True(bool condition, string message)
{
	CheckNumber += 1;

	if (!condition)
		return Failure(message);

	return;
}

Error<void> False(bool condition)
{
	return True(!condition, "expected false");
}

Error<void> False(bool condition, string message)
{
	return True(!condition, message);
}

Error<void> Equal(int64 expected, int64 actual)
{
	return True(expected == actual, "expected " + expected + ", actual " + actual);
}

Error<void> Equal(bool expected, bool actual)
{
	return True(expected == actual, "expected " + expected + ", actual " + actual);
}

Error<void> Equal(string expected, string actual)
{
	return True(expected == actual, "expected " + Show(expected) + ", actual " + Show(actual));
}

Error<void> NotEqual(int64 expected, int64 actual)
{
	return True(expected != actual, "expected anything but " + expected);
}

Error<void> NotEqual(string expected, string actual)
{
	return True(expected != actual, "expected anything but " + Show(expected));
}

/// The value is null (C#: Assert.Null on a string).
Error<void> Null(string actual)
{
	return True(actual == null, "expected null, actual " + Show(actual));
}

Error<void> NotNull(string actual)
{
	return True(actual != null, "expected a value, actual null");
}

/// C#: Assert.Contains(expectedSubstring, actualString).
Error<void> Contains(string expectedSubstring, string actual)
{
	return True(actual != null && actual.Contains(expectedSubstring), Show(actual) + " does not contain " + Show(expectedSubstring));
}

Error<void> DoesNotContain(string unexpectedSubstring, string actual)
{
	return True(actual == null || !actual.Contains(unexpectedSubstring), Show(actual) + " contains " + Show(unexpectedSubstring));
}

/// One of the lines contains the text (C#: Assert.Contains(lines, line => line.Contains(text))).
Error<void> AnyContains(List<string> lines, string expectedSubstring)
{
	foreach (var line in lines)
	{
		if (line.Contains(expectedSubstring))
			return True(true);
	}

	return True(false, "no line contains " + Show(expectedSubstring) + " in " + ShowList(lines));
}

Error<void> Words(uint16[] expected, uint16[] actual)
{
	return True(SameWords(expected, actual), "expected " + ShowWords(expected) + ", actual " + ShowWords(actual));
}

Error<void> Bytes(uint8[] expected, uint8[] actual)
{
	return True(SameBytes(Or(expected), Or(actual)), "expected " + ShowBytes(expected) + ", actual " + ShowBytes(actual));
}

Error<void> Ints(int[] expected, int[] actual)
{
	bool same = Length(expected) == Length(actual);

	for (var i = 0; same && i < Length(expected); i += 1)
		same = expected[i] == actual[i];

	return True(same, "expected " + ShowInts(expected) + ", actual " + ShowInts(actual));
}

Error<void> Strings(string[] expected, string[] actual)
{
	bool same = StringCount(expected) == StringCount(actual);

	for (var i = 0; same && i < StringCount(expected); i += 1)
		same = expected[i] == actual[i];

	return True(same, "expected " + ShowStrings(expected) + ", actual " + ShowStrings(actual));
}

Error<void> Strings(string[] expected, List<string> actual)
{
	return Strings(expected, ArrayOf(actual));
}

/// The list is empty (C#: Assert.Empty).
Error<void> Empty<T>(List<T> items)
{
	return True(items.Count() == 0, "expected no items, actual " + items.Count());
}

Error<void> Empty<T>(T[] items)
{
	return True(items == null || items.Length == 0, "expected no items, actual " + items.Length);
}

Error<void> NotEmpty<T>(List<T> items)
{
	return True(items.Count() > 0, "expected items, the list is empty");
}

Error<void> NotEmpty<T>(T[] items)
{
	return True(items != null && items.Length > 0, "expected items, the array is empty");
}

/// The only item of the list (C#: Assert.Single).
Error<T> Single<T>(List<T> items)
{
	try True(items.Count() == 1, "expected one item, actual " + items.Count());

	return items.Get(0);
}

Error<T> Single<T>(T[] items)
{
	try True(items != null && items.Length == 1, "expected one item, actual " + (items == null ? 0 : items.Length));

	return items[0];
}

/// The result is an error of the given kind (C#: Assert.Throws with the exception type). Returns the message.
Error<string> Fails<T>(Error<T> result, ErrorKind kind)
{
	CheckNumber += 1;

	if (result is not error)
		return error("check " + CheckNumber + ": expected an error " + (int)kind + ", but it succeeded", -1);

	if (result.Code != (int)kind)
		return error("check " + CheckNumber + ": expected an error " + (int)kind + ", actual error " + result.Code + ": " + result.Message, -1);

	return result.Message;
}

/// A failed Error<void> (C#: Assert.Throws around a call without a result).
Error<string> FailsVoid(Error<void> result, ErrorKind kind)
{
	CheckNumber += 1;

	if (result is not error)
		return error("check " + CheckNumber + ": expected an error " + (int)kind + ", but it succeeded", -1);

	if (result.Code != (int)kind)
		return error("check " + CheckNumber + ": expected an error " + (int)kind + ", actual error " + result.Code + ": " + result.Message, -1);

	return result.Message;
}

string Show(string text)
{
	if (text == null)
		return "null";

	return "\"" + text + "\"";
}

string ShowList(List<string> lines)
{
	return "[" + JoinList(", ", lines) + "]";
}

string ShowWords(uint16[] words)
{
	var list = List<string>.Create();

	for (var i = 0; words != null && i < words.Length; i += 1)
		list.Add("0x" + Hex((int)words[i], 4));

	return "[" + JoinList(", ", list) + "]";
}

string ShowBytes(uint8[] bytes)
{
	var list = List<string>.Create();

	for (var i = 0; bytes != null && i < bytes.Length && i < 64; i += 1)
		list.Add("" + (int)bytes[i]);

	if (bytes != null && bytes.Length > 64)
		list.Add("... (" + bytes.Length + " bytes)");

	return "[" + JoinList(", ", list) + "]";
}

string ShowInts(int[] values)
{
	var list = List<string>.Create();

	for (var i = 0; i < Length(values); i += 1)
		list.Add("" + values[i]);

	return "[" + JoinList(", ", list) + "]";
}

string ShowStrings(string[] values)
{
	var list = List<string>.Create();

	for (var i = 0; i < StringCount(values); i += 1)
		list.Add(Show(values[i]));

	return "[" + JoinList(", ", list) + "]";
}

bool SameWords(uint16[] a, uint16[] b)
{
	int lengthA = a == null ? 0 : a.Length;
	int lengthB = b == null ? 0 : b.Length;

	if (lengthA != lengthB)
		return false;

	for (var i = 0; i < lengthA; i += 1)
	{
		if (a[i] != b[i])
			return false;
	}

	return true;
}

uint8[] Or(uint8[] bytes)
{
	if (bytes == null)
		return new uint8[0];

	return bytes;
}

int Length(int[] values)
{
	return values == null ? 0 : values.Length;
}

int StringCount(string[] values)
{
	return values == null ? 0 : values.Length;
}
