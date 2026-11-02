namespace Amber.Screens;

using System;
using Amber.Base;

/// A rectangle in logical screen pixels (320x200 grid).
struct ScreenRect
{
	int X;
	int Y;
	int Width;
	int Height;

	static ScreenRect Of(int x, int y, int width, int height)
	{
		return ScreenRect { X = x, Y = y, Width = width, Height = height };
	}

	bool Contains(int x, int y)
	{
		return x >= X && y >= Y && x < X + Width && y < Y + Height;
	}

	bool Same(ScreenRect other)
	{
		return X == other.X && Y == other.Y && Width == other.Width && Height == other.Height;
	}

	/// C#: the record's ToString().
	string Text()
	{
		return "ScreenRect { X = " + X + ", Y = " + Y + ", Width = " + Width + ", Height = " + Height + " }";
	}
}

/// Two numbers of a property like [8, 16] (C#: the tuple of GetPair).
struct IntPair
{
	int First;
	int Second;
}

/// One node of a screen (spec section 8.3): a widget with position, size and kind specific properties. Children exist for
/// windows and containers; coordinates are relative to the parent.
struct NodeDefinition
{
	string Kind;
	/// Screen-local name of the node or null. Nodes with a name can be addressed by scripts (set_node ...).
	string Id;
	int X;
	int Y;
	int Width;
	int Height;
	int Layer;
	bool Visible;
	bool Enabled;
	/// The group names of the handlers, or null.
	string OnClick;
	string OnHover;
	/// The properties of the kind ("text", "source", "cols", "size_tiles" ...) as read from the YAML (a mapping).
	YamlNode Properties;
	NodeDefinition[] Children;

	/// The scalar text of a property, or null.
	string GetString(string name)
	{
		if (Properties.Kind != YamlKind.Mapping)
			return null;

		return Properties.GetText(name);
	}

	int GetInt(string name, int fallback)
	{
		string text = GetString(name);

		if (text != null)
		{
			if (TryParseInt(text) is int number)
				return number;
		}

		return fallback;
	}

	bool GetBool(string name, bool fallback)
	{
		string text = GetString(name);

		if (text != null)
		{
			if (TryParseBool(text) is bool flag)
				return flag;
		}

		return fallback;
	}

	Optional<IntPair> GetPair(string name)
	{
		if (Properties.Kind != YamlKind.Mapping)
			return null;

		if (Properties.Get(name) is YamlNode value)
		{
			if (value.IsSequence() && value.Count() == 2 && value.ItemAt(0).IsScalar() && value.ItemAt(1).IsScalar())
			{
				if (TryParseInt(value.ItemAt(0).Value) is int first)
				{
					if (TryParseInt(value.ItemAt(1).Value) is int second)
						return IntPair { First = first, Second = second };
				}
			}
		}

		return null;
	}
}

/// A screen after prefab and extends resolution: what the runtime needs to open it (spec section 8).
struct ScreenDefinition
{
	string Name;
	/// The screen captures all input; screens below do not react.
	bool Modal;
	/// The screens below stay visible. Without it they are hidden while this screen is open.
	bool Transparent;
	/// "none", "in", "out" or "both".
	string Fade;
	bool AllowCharacterSelect;
	bool AllowInventory;
	/// The cursor name or null.
	string Cursor;
	/// "escape", "right_click", "space": inputs which close the screen with the result 0.
	string[] CloseOn;
	int RegionX;
	int RegionY;
	int RegionWidth;
	int RegionHeight;
	/// Regions in which the input goes to the screen below.
	ScreenRect[] Passthrough;
	/// Names of the arguments of push_screen (screen variables 0..n-1).
	string[] Args;
	string OnOpen;
	string OnClose;
	string OnResume;
	NodeDefinition[] Nodes;
	/// The names of all nodes in depth first order, "" for nodes without a name. The position in this list is the node
	/// index used by set_node, show_node ... and by the node table of the chunk.
	string[] NodeIds;

	/// A screen without a definition file (the defaults of the C# class).
	static ScreenDefinition Empty(string name)
	{
		return ScreenDefinition
		{
			Name = name, Modal = false, Transparent = false, Fade = "both", AllowCharacterSelect = true, AllowInventory = true, Cursor = null,
			CloseOn = new string[0], Passthrough = new ScreenRect[0], Args = new string[0], Nodes = new NodeDefinition[0], NodeIds = new string[0]
		};
	}

	bool ClosesOn(string input)
	{
		return ContainsText(CloseOn, input);
	}

	/// True if the input at the point belongs to the screen below (inside a passthrough region).
	bool PassesThrough(int x, int y)
	{
		foreach (var rect in Passthrough)
		{
			if (rect.Contains(x, y))
				return true;
		}

		return false;
	}

	/// The names of all groups the definition refers to (on_click, on_open ...).
	List<string> Handlers()
	{
		var handlers = List<string>.Create();

		if (OnOpen != null)
			handlers.Add(OnOpen);

		if (OnClose != null)
			handlers.Add(OnClose);

		if (OnResume != null)
			handlers.Add(OnResume);

		foreach (var node in Flatten(Nodes))
		{
			var names = new string[] { node.OnClick, node.OnHover, node.GetString("on_select"), node.GetString("on_submit"), node.GetString("on_drop") };

			foreach (var name in names)
			{
				if (name != null)
					handlers.Add(name);
			}
		}

		return handlers;
	}

	/// The index of the node id in NodeIds, or -1.
	int NodeIndex(string id)
	{
		for (var i = 0; i < NodeIds.Length; i += 1)
		{
			if (NodeIds[i] == id)
				return i;
		}

		return -1;
	}

	/// The index of the argument, or -1.
	int ArgIndex(string name)
	{
		for (var i = 0; i < Args.Length; i += 1)
		{
			if (Args[i] == name)
				return i;
		}

		return -1;
	}

	/// The nodes and all their children, depth first.
	static List<NodeDefinition> Flatten(NodeDefinition[] nodes)
	{
		var result = List<NodeDefinition>.Create();

		AddFlattened(result, nodes);

		return result;
	}

	static void AddFlattened(List<NodeDefinition> result, NodeDefinition[] nodes)
	{
		foreach (var node in nodes)
		{
			result.Add(node);
			AddFlattened(result, node.Children);
		}
	}
}
