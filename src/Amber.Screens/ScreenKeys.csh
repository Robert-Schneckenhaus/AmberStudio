// Key codes of the hotkey of a button in a screen chunk: upper case letters and digits as ASCII, esc 27, enter 13, tab 9,
// space 32, num0..num9 0x100+n, f1..f12 0x110+n, arrows 0x120..0x123 (up, down, left, right).

namespace Amber.Screens.ScreenKeys;

using System;
using Amber.Base;

Error<uint16> Parse(string name)
{
	string key = name.Trim().ToLower();

	if (key.Length == 1 && Char.IsLetterOrDigit(key[0]))
		return (uint16)Char.ToUpper(key[0]);

	if (key.StartsWith("num"))
	{
		if (TryParseInt(key.Substring(3)) is int digit)
		{
			if (digit >= 0 && digit <= 9)
				return (uint16)(0x100 + digit);
		}
	}

	if (key.StartsWith("f"))
	{
		if (TryParseInt(key.Substring(1)) is int function)
		{
			if (function >= 1 && function <= 12)
				return (uint16)(0x110 + function);
		}
	}

	switch (key)
	{
		case "esc":
		case "escape":
			return 27;
		case "enter":
		case "return":
			return 13;
		case "tab":
			return 9;
		case "space":
			return 32;
		case "up":
			return 0x120;
		case "down":
			return 0x121;
		case "left":
			return 0x122;
		case "right":
			return 0x123;
		default:
			return error("Unknown hotkey '" + name + "'.", (int)ErrorKind.InvalidData);
	}
}
