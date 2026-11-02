// Keyboard and mouse input (C#: Silk.NET.Input's Key and MouseButton, InputState, InputScript). The key values are the
// GLFW key codes, the names the ones of Silk.NET (the input scripts and screen hotkeys use them).

namespace Amber.Player.Platform;

using System;
using Amber.Base;

enum Key : int32
{
	Unknown = 0,
	Space = 32,
	Apostrophe = 39,
	Comma = 44,
	Minus = 45,
	Period = 46,
	Slash = 47,
	Number0 = 48,
	Number1 = 49,
	Number2 = 50,
	Number3 = 51,
	Number4 = 52,
	Number5 = 53,
	Number6 = 54,
	Number7 = 55,
	Number8 = 56,
	Number9 = 57,
	Semicolon = 59,
	Equal = 61,
	A = 65,
	B = 66,
	C = 67,
	D = 68,
	E = 69,
	F = 70,
	G = 71,
	H = 72,
	I = 73,
	J = 74,
	K = 75,
	L = 76,
	M = 77,
	N = 78,
	O = 79,
	P = 80,
	Q = 81,
	R = 82,
	S = 83,
	T = 84,
	U = 85,
	V = 86,
	W = 87,
	X = 88,
	Y = 89,
	Z = 90,
	LeftBracket = 91,
	BackSlash = 92,
	RightBracket = 93,
	GraveAccent = 96,
	Escape = 256,
	Enter = 257,
	Tab = 258,
	Backspace = 259,
	Insert = 260,
	Delete = 261,
	Right = 262,
	Left = 263,
	Down = 264,
	Up = 265,
	PageUp = 266,
	PageDown = 267,
	Home = 268,
	End = 269,
	F1 = 290,
	F2 = 291,
	F3 = 292,
	F4 = 293,
	F5 = 294,
	F6 = 295,
	F7 = 296,
	F8 = 297,
	F9 = 298,
	F10 = 299,
	F11 = 300,
	F12 = 301,
	Keypad0 = 320,
	Keypad1 = 321,
	Keypad2 = 322,
	Keypad3 = 323,
	Keypad4 = 324,
	Keypad5 = 325,
	Keypad6 = 326,
	Keypad7 = 327,
	Keypad8 = 328,
	Keypad9 = 329,
	KeypadEnter = 335,
	ShiftLeft = 340,
	ControlLeft = 341,
	AltLeft = 342,
	ShiftRight = 344,
	ControlRight = 345,
	AltRight = 346
}

enum MouseButton : int32
{
	Left = 0,
	Right = 1,
	Middle = 2
}

struct KeyName
{
	string Name;
	Key Key;
}

KeyName Kn(string name, Key key)
{
	return KeyName { Name = name, Key = key };
}

KeyName[] KeyNames = new KeyName[]
{
	Kn("Space", Key.Space), Kn("Apostrophe", Key.Apostrophe), Kn("Comma", Key.Comma), Kn("Minus", Key.Minus), Kn("Period", Key.Period),
	Kn("Slash", Key.Slash), Kn("Number0", Key.Number0), Kn("Number1", Key.Number1), Kn("Number2", Key.Number2), Kn("Number3", Key.Number3),
	Kn("Number4", Key.Number4), Kn("Number5", Key.Number5), Kn("Number6", Key.Number6), Kn("Number7", Key.Number7), Kn("Number8", Key.Number8),
	Kn("Number9", Key.Number9), Kn("Semicolon", Key.Semicolon), Kn("Equal", Key.Equal), Kn("LeftBracket", Key.LeftBracket),
	Kn("BackSlash", Key.BackSlash), Kn("RightBracket", Key.RightBracket), Kn("GraveAccent", Key.GraveAccent), Kn("Escape", Key.Escape),
	Kn("Enter", Key.Enter), Kn("Tab", Key.Tab), Kn("Backspace", Key.Backspace), Kn("Insert", Key.Insert), Kn("Delete", Key.Delete),
	Kn("Right", Key.Right), Kn("Left", Key.Left), Kn("Down", Key.Down), Kn("Up", Key.Up), Kn("PageUp", Key.PageUp), Kn("PageDown", Key.PageDown),
	Kn("Home", Key.Home), Kn("End", Key.End), Kn("KeypadEnter", Key.KeypadEnter), Kn("ShiftLeft", Key.ShiftLeft), Kn("ControlLeft", Key.ControlLeft),
	Kn("AltLeft", Key.AltLeft), Kn("ShiftRight", Key.ShiftRight), Kn("ControlRight", Key.ControlRight), Kn("AltRight", Key.AltRight)
};

/// The key of a Silk.NET key name (case does not matter): "Space", "A", "F3", "ControlLeft" ...; Key.Unknown if there is
/// none.
Key ParseKey(string name)
{
	string lower = name.ToLower();

	if (lower.Length == 1 && lower[0] >= 'a' && lower[0] <= 'z')
		return (Key)(65 + (int)(lower[0] - 'a'));

	if (lower.Length >= 2 && lower[0] == 'f' && TryParseInt(lower.Substring(1)) is int function)
	{
		if (function >= 1 && function <= 12)
			return (Key)(289 + function);
	}

	if (lower.StartsWith("keypad") && lower.Length == 7 && lower[6] >= '0' && lower[6] <= '9')
		return (Key)(320 + (int)(lower[6] - '0'));

	foreach (var entry in KeyNames)
	{
		if (entry.Name.ToLower() == lower)
			return entry.Key;
	}

	return Key.Unknown;
}

MouseButton ParseMouseButton(string name)
{
	string lower = name.ToLower();

	return lower == "right" ? MouseButton.Right : lower == "middle" ? MouseButton.Middle : MouseButton.Left;
}

struct InputValues
{
	int MouseX;
	int MouseY;
	float QueuedWheel;
	float Wheel;
	string Typed;
	string QueuedText;
}

/// Keyboard and mouse state of the current tick. "Pressed" is true only in the tick in which the key or button went down,
/// "Released" only in the tick in which it went up. The mouse position is in virtual screen pixels. A handle.
struct InputState
{
	InputValues[] _s;
	List<Key> _down;
	List<Key> _pressed;
	List<Key> _queuedPressed;
	List<MouseButton> _mouseDown;
	List<MouseButton> _mousePressed;
	List<MouseButton> _mouseReleased;
	List<MouseButton> _queuedMousePressed;
	List<MouseButton> _queuedMouseReleased;

	static InputState Create()
	{
		var state = new InputValues[1];

		state[0].Typed = "";
		state[0].QueuedText = "";

		return InputState
		{
			_s = state, _down = List<Key>.Create(), _pressed = List<Key>.Create(), _queuedPressed = List<Key>.Create(), _mouseDown = List<MouseButton>.Create(),
			_mousePressed = List<MouseButton>.Create(), _mouseReleased = List<MouseButton>.Create(), _queuedMousePressed = List<MouseButton>.Create(),
			_queuedMouseReleased = List<MouseButton>.Create()
		};
	}

	int MouseX()
	{
		return _s[0].MouseX;
	}

	int MouseY()
	{
		return _s[0].MouseY;
	}

	/// Wheel movement in this tick (positive = away from the user).
	float Wheel()
	{
		return _s[0].Wheel;
	}

	/// The characters typed in this tick (for text input fields).
	string Typed()
	{
		return _s[0].Typed;
	}

	bool IsDown(Key key)
	{
		return _down.Contains(key);
	}

	bool Pressed(Key key)
	{
		return _pressed.Contains(key);
	}

	bool AnyPressed()
	{
		return _pressed.Count() > 0;
	}

	List<Key> PressedKeys()
	{
		return _pressed;
	}

	bool MouseIsDown(MouseButton button)
	{
		return _mouseDown.Contains(button);
	}

	bool MousePressed(MouseButton button)
	{
		return _mousePressed.Contains(button);
	}

	bool MouseReleased(MouseButton button)
	{
		return _mouseReleased.Contains(button);
	}

	void KeyDown(Key key)
	{
		if (!_down.Contains(key))
		{
			_down.Add(key);

			if (!_queuedPressed.Contains(key))
				_queuedPressed.Add(key);
		}
	}

	void KeyUp(Key key)
	{
		_down.Remove(key);
	}

	void MouseMoved(int x, int y)
	{
		_s[0].MouseX = x;
		_s[0].MouseY = y;
	}

	void MouseButtonDown(MouseButton button)
	{
		if (!_mouseDown.Contains(button))
		{
			_mouseDown.Add(button);

			if (!_queuedMousePressed.Contains(button))
				_queuedMousePressed.Add(button);
		}
	}

	void MouseButtonUp(MouseButton button)
	{
		if (_mouseDown.Remove(button) && !_queuedMouseReleased.Contains(button))
			_queuedMouseReleased.Add(button);
	}

	void MouseWheel(float delta)
	{
		_s[0].QueuedWheel += delta;
	}

	void CharTyped(string character)
	{
		_s[0].QueuedText = _s[0].QueuedText + character;
	}

	/// The most recently pressed of the given keys which is still held down, or Key.Unknown. Used for movement: the key
	/// pressed last wins, and when it is released the one pressed before it takes over again.
	Key LatestDown(Key[] keys)
	{
		for (var i = _down.Count() - 1; i >= 0; i -= 1)
		{
			var key = _down.Get(i);

			foreach (var candidate in keys)
			{
				if (candidate == key)
					return key;
			}
		}

		return Key.Unknown;
	}

	/// Called once per game tick before Update: makes the queued key presses and mouse events visible.
	void BeginTick()
	{
		_pressed.Clear();

		foreach (var key in _queuedPressed)
			_pressed.Add(key);

		_queuedPressed.Clear();
		_mousePressed.Clear();
		_mouseReleased.Clear();

		foreach (var button in _queuedMousePressed)
			_mousePressed.Add(button);

		foreach (var button in _queuedMouseReleased)
			_mouseReleased.Add(button);

		_queuedMousePressed.Clear();
		_queuedMouseReleased.Clear();
		_s[0].Wheel = _s[0].QueuedWheel;
		_s[0].QueuedWheel = 0.0f;
		_s[0].Typed = _s[0].QueuedText;
		_s[0].QueuedText = "";
	}
}

enum CommandKind : int32
{
	Wait,
	Press,
	Down,
	Up,
	Mouse,
	MouseDown,
	MouseUp,
	Click,
	Wheel,
	Hold,
	Shot,
	Debug,
	Type,
	Quit
}

struct ScriptCommand
{
	CommandKind Kind;
	Key Key;
	int Count;
	string Path;
	int X;
	int Y;
}

struct ScriptValues
{
	int Index;
	int Remaining;
	Key HeldKey;
}

/// A simple input script for automatic runs, one command per line (see game/tests/*.txt): wait n, press Key, type text,
/// hold Key n, repeat Key count interval, mouse x y, click [Left|Right], mousedown, mouseup, wheel n, down Key, up Key,
/// shot file.png, the debug commands (warp, map, time, hp, expect, and the editor's select, tool, layer, camera, terrain)
/// and quit. Comments start with # or //.
struct InputScript
{
	ScriptValues[] _s;
	List<ScriptCommand> _commands;

	static Error<InputScript> Load(string path)
	{
		var text = try File.ReadAllText(path);
		var commands = List<ScriptCommand>.Create();

		foreach (var raw in text.Replace("\r", "").Split("\n"))
		{
			string line = raw.ToString();
			int comment = line.IndexOf('#');

			if (comment >= 0)
				line = line.Substring(0, comment);

			int slashes = line.IndexOf("//");

			if (slashes >= 0)
				line = line.Substring(0, slashes);

			var parts = SplitWhitespace(line);

			if (parts.Length == 0)
				continue;

			string name = parts[0].ToLower();

			if (name == "wait")
				commands.Add(ScriptCommand { Kind = CommandKind.Wait, Count = try ScriptNumber(parts, 1) });
			else if (name == "repeat")
			{
				var key = try ScriptKey(parts, 1);
				int count = try ScriptNumber(parts, 2);
				int interval = try ScriptNumber(parts, 3);

				for (var i = 0; i < count; i += 1)
				{
					commands.Add(ScriptCommand { Kind = CommandKind.Press, Key = key, Count = 1 });
					commands.Add(ScriptCommand { Kind = CommandKind.Wait, Count = interval });
				}
			}
			else if (name == "mouse")
				commands.Add(ScriptCommand { Kind = CommandKind.Mouse, X = try ScriptNumber(parts, 1), Y = try ScriptNumber(parts, 2) });
			else if (name == "mousedown" || name == "mouseup" || name == "click")
			{
				var button = ParseMouseButton(parts.Length > 1 ? parts[1] : "Left");
				var kind = name == "mousedown" ? CommandKind.MouseDown : name == "mouseup" ? CommandKind.MouseUp : CommandKind.Click;

				commands.Add(ScriptCommand { Kind = kind, Count = (int)button });
			}
			else if (name == "wheel")
				commands.Add(ScriptCommand { Kind = CommandKind.Wheel, Count = try ScriptNumber(parts, 1) });
			else if (name == "down")
				commands.Add(ScriptCommand { Kind = CommandKind.Down, Key = try ScriptKey(parts, 1), Count = 1 });
			else if (name == "up")
				commands.Add(ScriptCommand { Kind = CommandKind.Up, Key = try ScriptKey(parts, 1), Count = 1 });
			else if (name == "press")
				commands.Add(ScriptCommand { Kind = CommandKind.Press, Key = try ScriptKey(parts, 1), Count = 1 });
			else if (name == "hold")
				commands.Add(ScriptCommand { Kind = CommandKind.Hold, Key = try ScriptKey(parts, 1), Count = try ScriptNumber(parts, 2) });
			else if (name == "expect" || name == "select" || name == "tool" || name == "layer" || name == "camera" || name == "terrain" || name == "map"
				|| name == "warp" || name == "hp" || name == "time" || name == "member")
				commands.Add(ScriptCommand { Kind = CommandKind.Debug, Path = line.Trim().ToString() });
			else if (name == "shot")
				commands.Add(ScriptCommand { Kind = CommandKind.Shot, Path = parts.Length > 1 ? parts[1] : "shot.png" });
			else if (name == "type")
				commands.Add(ScriptCommand { Kind = CommandKind.Type, Path = line.Trim().Substring(4).Trim().ToString() });
			else if (name == "quit")
				commands.Add(ScriptCommand { Kind = CommandKind.Quit });
			else
				return error("Unknown script command '" + parts[0] + "'.", (int)ErrorKind.InvalidData);
		}

		var state = new ScriptValues[1];

		state[0].HeldKey = Key.Unknown;

		return InputScript { _s = state, _commands = commands };
	}

	bool Finished()
	{
		return _s[0].Index >= _commands.Count() && _s[0].Remaining == 0;
	}

	/// Advances the script by one tick and drives the input. Returns a screenshot path if the script asks for one in this
	/// tick, "debug:..." for a debug command, "quit" to end the run, or null.
	string Step(InputState input)
	{
		if (_s[0].HeldKey != Key.Unknown && _s[0].Remaining == 0)
		{
			input.KeyUp(_s[0].HeldKey);
			_s[0].HeldKey = Key.Unknown;
		}

		if (_s[0].Remaining > 0)
		{
			_s[0].Remaining -= 1;

			if (_s[0].Remaining == 0 && _s[0].HeldKey != Key.Unknown)
			{
				input.KeyUp(_s[0].HeldKey);
				_s[0].HeldKey = Key.Unknown;
			}

			return null;
		}

		while (_s[0].Index < _commands.Count())
		{
			var command = _commands.Get(_s[0].Index);

			_s[0].Index += 1;

			if (command.Kind == CommandKind.Wait)
			{
				_s[0].Remaining = command.Count;

				return null;
			}

			if (command.Kind == CommandKind.Mouse)
				input.MouseMoved(command.X, command.Y);
			else if (command.Kind == CommandKind.MouseDown)
				input.MouseButtonDown((MouseButton)command.Count);
			else if (command.Kind == CommandKind.MouseUp)
				input.MouseButtonUp((MouseButton)command.Count);
			else if (command.Kind == CommandKind.Click)
			{
				input.MouseButtonDown((MouseButton)command.Count);
				input.MouseButtonUp((MouseButton)command.Count);
			}
			else if (command.Kind == CommandKind.Wheel)
				input.MouseWheel((float)command.Count);
			else if (command.Kind == CommandKind.Down)
				input.KeyDown(command.Key);
			else if (command.Kind == CommandKind.Up)
				input.KeyUp(command.Key);
			else if (command.Kind == CommandKind.Press)
			{
				input.KeyDown(command.Key);
				input.KeyUp(command.Key);

				return null;
			}
			else if (command.Kind == CommandKind.Hold)
			{
				input.KeyDown(command.Key);
				_s[0].HeldKey = command.Key;
				_s[0].Remaining = command.Count;

				return null;
			}
			else if (command.Kind == CommandKind.Type)
			{
				input.CharTyped(command.Path);

				return null;
			}
			else if (command.Kind == CommandKind.Debug)
				return "debug:" + command.Path;
			else if (command.Kind == CommandKind.Shot)
				return command.Path;
			else if (command.Kind == CommandKind.Quit)
				return "quit";
		}

		return "quit";
	}
}

Error<int> ScriptNumber(string[] parts, int index)
{
	if (index < parts.Length && TryParseInt(parts[index]) is int value)
		return value;

	return error("The script line '" + JoinList(" ", ListOf(parts)) + "' needs a number as argument " + index + ".", (int)ErrorKind.InvalidData);
}

Error<Key> ScriptKey(string[] parts, int index)
{
	if (index < parts.Length)
	{
		var key = ParseKey(parts[index]);

		if (key != Key.Unknown)
			return key;
	}

	return error("The script line '" + JoinList(" ", ListOf(parts)) + "' needs a key name as argument " + index + ".", (int)ErrorKind.InvalidData);
}
