namespace Amber.Screens;

using System;
using Amber.Base;
using Amber.Script.Common;

/// The IDs a screen chunk needs from the tables of the game (texts, graphics, data sources ...). The cook of a pack
/// implements it with the real tables. A lookup can fail (unknown symbol).
interface IScreenSymbols
{
	/// ID of a screen (S.name).
	Error<int> Screen(string name);

	/// ID of a table text (T.name, without the prefix).
	Error<int> Text(string name);

	/// ID of a graphic or icon of the UI graphics table (gfx, icon).
	Error<int> Graphic(string name);

	/// ID of a native data source (bind, source), for example "chest.gold".
	Error<int> Source(string name);

	/// The group reference (GroupRef16) of a handler group of the screen, or Wire.None.
	Error<int> Group(string screen, string group);

	/// ID of a cursor of the cursor table.
	Error<int> Cursor(string name);
}

enum ScreenFlags : uint16
{
	None = 0,
	Modal = 1,
	Transparent = 2,
	FadeIn = 4,
	FadeOut = 8,
	CloseOnEscape = 16,
	CloseOnRightClick = 32,
	CloseOnSpace = 64,
	AllowCharacterSelect = 128,
	AllowInventory = 256
}

bool HasScreenFlag(ScreenFlags flags, ScreenFlags flag)
{
	return ((int)flags & (int)flag) == (int)flag;
}

enum NodeType : uint8
{
	Container,
	Image,
	Label,
	Button,
	Input,
	List,
	ItemGrid,
	Portrait,
	Bar,
	Window,
	TextView,
	Viewport,
	Picture
}

EnumEntry[] NodeTypeNames = new EnumEntry[]
{
	En("Container", 0), En("Image", 1), En("Label", 2), En("Button", 3), En("Input", 4), En("List", 5), En("ItemGrid", 6),
	En("Portrait", 7), En("Bar", 8), En("Window", 9), En("TextView", 10), En("Viewport", 11), En("Picture", 12)
};

string NodeTypeName(NodeType type)
{
	return EnumName(NodeTypeNames, (int)type);
}

enum NodeFlags : uint8
{
	None = 0,
	Visible = 1,
	Enabled = 2,
	/// The text field holds the ID of a data source (bind, source) instead of a text.
	Bound = 4
}

/// C#: the [Flags] enum ToString ("Visible, Enabled", "None").
string NodeFlagsText(NodeFlags flags)
{
	int value = (int)flags;

	if (value == 0)
		return "None";

	var parts = List<string>.Create();

	if ((value & 1) != 0)
		parts.Add("Visible");

	if ((value & 2) != 0)
		parts.Add("Enabled");

	if ((value & 4) != 0)
		parts.Add("Bound");

	if ((value & ~7) != 0)
		return value.ToString();

	return JoinList(", ", parts);
}

/// C#: the [Flags] enum ToString of ScreenFlags.
string ScreenFlagsText(ScreenFlags flags)
{
	int value = (int)flags;

	if (value == 0)
		return "None";

	var names = new string[] { "Modal", "Transparent", "FadeIn", "FadeOut", "CloseOnEscape", "CloseOnRightClick", "CloseOnSpace", "AllowCharacterSelect", "AllowInventory" };
	var parts = List<string>.Create();

	for (var i = 0; i < names.Length; i += 1)
	{
		if ((value & (1 << i)) != 0)
			parts.Add(names[i]);
	}

	if ((value & ~0x1FF) != 0)
		return value.ToString();

	return JoinList(", ", parts);
}

const uint16 LiteralText = 0x8000;
const uint16 ArgumentText = 0xC000;

/// Bound nodes: 0x8000 | node index means the detail text (description) of the selected row of that list or item grid node
/// of the screen, 0xC000 | node index (LocalName) its text (name); smaller values are IDs of native data sources.
const uint16 LocalSource = 0x8000;
const uint16 LocalName = 0x4000;

/// One node record (spec section 8.3): 16 words. The last three words depend on the type, see ScreenChunk.
struct NodeRecord
{
	NodeType Type;
	NodeFlags Flags;
	uint16 Id;
	uint16 Parent;
	int16 X;
	int16 Y;
	int16 Width;
	int16 Height;
	uint16 Layer;
	uint16 Graphic;
	uint16 Text;
	uint16 BindArgument;
	uint16 OnClick;
	uint16 OnHover;
	uint16 Extra0;
	uint16 Extra1;
	uint16 Extra2;

	bool IsBound()
	{
		return ((int)Flags & (int)NodeFlags.Bound) != 0;
	}

	/// The text field is the ID of a table text.
	bool IsTableText()
	{
		return !IsBound() && Text > 0 && Text < LiteralText;
	}

	/// The text field is the index of a literal text of the chunk.
	bool IsLiteralText()
	{
		return !IsBound() && ((int)Text & 0xC000) == (int)LiteralText;
	}

	/// The text field is the index of a screen argument (the ID of the text is in this variable).
	bool IsArgumentText()
	{
		return !IsBound() && ((int)Text & 0xC000) == (int)ArgumentText;
	}

	bool IsLocalSource()
	{
		return IsBound() && ((int)Text & (int)LocalSource) != 0;
	}

	int LocalSourceNode()
	{
		return (int)Text & 0x3FFF;
	}

	/// True if a local source is the text of the selected row ("nodeid.name"), false for its detail ("nodeid.detail").
	bool IsLocalName()
	{
		return IsLocalSource() && ((int)Text & (int)LocalName) != 0;
	}
}

const int NodeRecordWords = 16;

/// A screen as binary chunk (spec sections 8.2 and 8.3), all words big endian: header of 16 words, the passthrough
/// rectangles (4 words each), the node table (16 words per node in depth-first order, the position is the node index) and
/// the table of literal texts (length in bytes, Latin-1 bytes, padded to a whole word).
struct ScreenChunk
{
	uint16 ScreenId;
	ScreenFlags Flags;
	ScreenRect Region;
	int ArgumentCount;
	ScreenRect[] Passthrough;
	uint16 OnOpen;
	uint16 OnClose;
	uint16 OnResume;
	uint16 Cursor;
	NodeRecord[] Nodes;
	string[] Literals;

	/// Encodes a screen. Texts of the form T.name become table IDs, $name a reference to the screen argument, everything
	/// else a literal text of the chunk.
	static Error<uint8[]> Write<TSymbols>(ScreenDefinition screen, ref TSymbols symbols)
		where TSymbols : IScreenSymbols
	{
		var literals = List<string>.Create();
		var nodes = List<NodeRecord>.Create();

		foreach (var node in screen.Nodes)
			try AddNode(screen, node, Wire.None, ref symbols, literals, nodes);

		int flags = (int)ScreenFlags.None;

		if (screen.Modal)
			flags = flags | (int)ScreenFlags.Modal;

		if (screen.Transparent)
			flags = flags | (int)ScreenFlags.Transparent;

		if (screen.Fade == "in" || screen.Fade == "both")
			flags = flags | (int)ScreenFlags.FadeIn;

		if (screen.Fade == "out" || screen.Fade == "both")
			flags = flags | (int)ScreenFlags.FadeOut;

		if (screen.ClosesOn("escape"))
			flags = flags | (int)ScreenFlags.CloseOnEscape;

		if (screen.ClosesOn("right_click"))
			flags = flags | (int)ScreenFlags.CloseOnRightClick;

		if (screen.ClosesOn("space"))
			flags = flags | (int)ScreenFlags.CloseOnSpace;

		if (screen.AllowCharacterSelect)
			flags = flags | (int)ScreenFlags.AllowCharacterSelect;

		if (screen.AllowInventory)
			flags = flags | (int)ScreenFlags.AllowInventory;

		int nodeTable = ScreenChunkHeaderWords + screen.Passthrough.Length * 4;
		int literalTable = nodeTable + nodes.Count() * NodeRecordWords;
		var words = List<uint16>.Create();

		words.Add(try CheckedWord(try symbols.Screen(screen.Name), "screen ID"));
		words.Add((uint16)flags);
		words.Add((uint16)screen.RegionX);
		words.Add((uint16)screen.RegionY);
		words.Add((uint16)screen.RegionWidth);
		words.Add((uint16)screen.RegionHeight);
		words.Add((uint16)screen.Args.Length);
		words.Add((uint16)nodes.Count());
		words.Add((uint16)literals.Count());
		words.Add((uint16)screen.Passthrough.Length);
		words.Add(try Handler(screen, screen.OnOpen, ref symbols));
		words.Add(try Handler(screen, screen.OnClose, ref symbols));
		words.Add(try Handler(screen, screen.OnResume, ref symbols));
		words.Add(screen.Cursor == null ? (uint16)0 : try CheckedWord(try symbols.Cursor(screen.Cursor), "cursor ID"));
		words.Add((uint16)nodeTable);
		words.Add((uint16)literalTable);

		foreach (var rect in screen.Passthrough)
		{
			words.Add((uint16)rect.X);
			words.Add((uint16)rect.Y);
			words.Add((uint16)rect.Width);
			words.Add((uint16)rect.Height);
		}

		foreach (var node in nodes)
		{
			words.Add((uint16)(((int)node.Type << 8) | (int)node.Flags));
			words.Add(node.Id);
			words.Add(node.Parent);
			words.Add((uint16)node.X);
			words.Add((uint16)node.Y);
			words.Add((uint16)node.Width);
			words.Add((uint16)node.Height);
			words.Add(node.Layer);
			words.Add(node.Graphic);
			words.Add(node.Text);
			words.Add(node.BindArgument);
			words.Add(node.OnClick);
			words.Add(node.OnHover);
			words.Add(node.Extra0);
			words.Add(node.Extra1);
			words.Add(node.Extra2);
		}

		var writer = ByteWriter.Create();

		foreach (var value in words)
			writer.Word((int)value);

		foreach (var literal in literals)
		{
			if (FirstNonLatin1(literal) >= 0)
				return error("E012: the literal text '" + literal + "' of screen '" + screen.Name + "' is not Latin-1.", (int)ErrorKind.InvalidData);

			var bytes = Latin1Bytes(literal);

			writer.Word((int)try CheckedWord(bytes.Length, "literal text length"));
			writer.Bytes(bytes);

			if (bytes.Length % 2 != 0)
				writer.Byte(0);
		}

		return writer.ToArray();
	}

	static Error<void> AddNode<TSymbols>(ScreenDefinition screen, NodeDefinition node, uint16 parent, ref TSymbols symbols, List<string> literals, List<NodeRecord> nodes)
		where TSymbols : IScreenSymbols
	{
		uint16 index = (uint16)nodes.Count();

		nodes.Add(try EncodeNode(screen, node, index, parent, ref symbols, literals));

		foreach (var child in node.Children)
			try AddNode(screen, child, index, ref symbols, literals, nodes);

		return;
	}

	/// Decodes a chunk. Returns an InvalidChunk error if it is truncated or inconsistent.
	static Error<ScreenChunk> Read(uint8[] data)
	{
		if (data.Length < ScreenChunkHeaderWords * 2)
			return error("Screen chunk is shorter than its header.", (int)ErrorKind.InvalidChunk);

		int nodeCount = (int)try WordOf(data, 7);
		int literalCount = (int)try WordOf(data, 8);
		int passthroughCount = (int)try WordOf(data, 9);
		int nodeTable = (int)try WordOf(data, 14);
		int literalTable = (int)try WordOf(data, 15);

		if (nodeTable != ScreenChunkHeaderWords + passthroughCount * 4 || literalTable != nodeTable + nodeCount * NodeRecordWords)
			return error("Screen chunk has inconsistent table offsets.", (int)ErrorKind.InvalidChunk);

		var passthrough = List<ScreenRect>.Create();

		for (var i = 0; i < passthroughCount; i += 1)
		{
			int at = ScreenChunkHeaderWords + i * 4;

			passthrough.Add(ScreenRect.Of((int)(int16)try WordOf(data, at), (int)(int16)try WordOf(data, at + 1), (int)try WordOf(data, at + 2), (int)try WordOf(data, at + 3)));
		}

		var nodes = List<NodeRecord>.Create();

		for (var i = 0; i < nodeCount; i += 1)
		{
			int at = nodeTable + i * NodeRecordWords;
			uint16 first = try WordOf(data, at);
			int type = (int)first >> 8;

			if (type > (int)NodeType.Picture)
				return error("Node " + i + " has the unknown type " + type + ".", (int)ErrorKind.InvalidChunk);

			uint16 parent = try WordOf(data, at + 2);

			if (parent != Wire.None && (int)parent >= i)
				return error("Node " + i + " has the invalid parent " + parent + ".", (int)ErrorKind.InvalidChunk);

			nodes.Add(NodeRecord
			{
				Type = (NodeType)type,
				Flags = (NodeFlags)((int)first & 0xFF),
				Id = try WordOf(data, at + 1),
				Parent = parent,
				X = (int16)try WordOf(data, at + 3),
				Y = (int16)try WordOf(data, at + 4),
				Width = (int16)try WordOf(data, at + 5),
				Height = (int16)try WordOf(data, at + 6),
				Layer = try WordOf(data, at + 7),
				Graphic = try WordOf(data, at + 8),
				Text = try WordOf(data, at + 9),
				BindArgument = try WordOf(data, at + 10),
				OnClick = try WordOf(data, at + 11),
				OnHover = try WordOf(data, at + 12),
				Extra0 = try WordOf(data, at + 13),
				Extra1 = try WordOf(data, at + 14),
				Extra2 = try WordOf(data, at + 15)
			});
		}

		var literals = List<string>.Create();
		int offset = literalTable * 2;

		for (var i = 0; i < literalCount; i += 1)
		{
			int length = (int)try ScriptChunk.ReadWord(data, offset);

			offset += 2;

			if (offset + length > data.Length)
				return error("A literal text of the screen chunk is truncated.", (int)ErrorKind.InvalidChunk);

			literals.Add(Latin1String(data, offset, length));
			offset += length + length % 2;
		}

		if (offset > data.Length)
			return error("The literal texts of the screen chunk are truncated.", (int)ErrorKind.InvalidChunk);

		return ScreenChunk
		{
			ScreenId = try WordOf(data, 0),
			Flags = (ScreenFlags)try WordOf(data, 1),
			Region = ScreenRect.Of((int)(int16)try WordOf(data, 2), (int)(int16)try WordOf(data, 3), (int)try WordOf(data, 4), (int)try WordOf(data, 5)),
			ArgumentCount = (int)try WordOf(data, 6),
			Passthrough = ArrayOf(passthrough),
			OnOpen = try WordOf(data, 10),
			OnClose = try WordOf(data, 11),
			OnResume = try WordOf(data, 12),
			Cursor = try WordOf(data, 13),
			Nodes = ArrayOf(nodes),
			Literals = ArrayOf(literals)
		};
	}

	static Error<uint16> Handler<TSymbols>(ScreenDefinition screen, string group, ref TSymbols symbols)
		where TSymbols : IScreenSymbols
	{
		if (group == null)
			return Wire.None;

		return (uint16)try symbols.Group(screen.Name, group);
	}

	static Error<NodeRecord> EncodeNode<TSymbols>(ScreenDefinition screen, NodeDefinition node, uint16 index, uint16 parent, ref TSymbols symbols, List<string> literals)
		where TSymbols : IScreenSymbols
	{
		NodeType type;

		switch (node.Kind)
		{
			case "container":
				type = NodeType.Container;
				break;
			case "image":
				type = NodeType.Image;
				break;
			case "label":
				type = NodeType.Label;
				break;
			case "button":
				type = NodeType.Button;
				break;
			case "input":
				type = NodeType.Input;
				break;
			case "list":
				type = NodeType.List;
				break;
			case "itemgrid":
				type = NodeType.ItemGrid;
				break;
			case "portrait":
				type = NodeType.Portrait;
				break;
			case "bar":
				type = NodeType.Bar;
				break;
			case "window":
				type = NodeType.Window;
				break;
			case "textview":
				type = NodeType.TextView;
				break;
			case "viewport":
				type = NodeType.Viewport;
				break;
			case "picture":
				type = NodeType.Picture;
				break;
			default:
				return error("Screen '" + screen.Name + "': unknown node kind '" + node.Kind + "'.", (int)ErrorKind.InvalidData);
		}

		var encoder = NodeEncoder
		{
			Flags = (node.Visible ? (int)NodeFlags.Visible : 0) | (node.Enabled ? (int)NodeFlags.Enabled : 0),
			BindArgument = Wire.None
		};
		uint16 graphic = 0;
		uint16 text = 0;
		uint16 extra0 = 0;
		uint16 extra1 = 0;
		uint16 extra2 = 0;

		switch (type)
		{
			case NodeType.Window:
			{
				var tiles = IntPair { First = 0, Second = 0 };

				if (node.GetPair("size_tiles") is IntPair pair)
					tiles = pair;

				extra0 = (uint16)((tiles.First << 8) | tiles.Second);
				extra1 = (uint16)(node.GetBool("dark", false) ? 1 : 0);
				break;
			}
			case NodeType.Label:
			{
				string bind = node.GetString("bind");

				if (bind != null)
					text = try encoder.Bound(screen, bind, ref symbols);
				else
					text = try encoder.TextField(screen, node.GetString("text"), ref symbols, literals);

				string align = node.GetString("align");

				extra0 = (uint16)(align == "center" ? 1 : (align == "right" ? 2 : 0));
				extra1 = (uint16)node.GetInt("color", 0);
				extra2 = (uint16)(node.GetBool("blink", false) ? 1 : 0);
				break;
			}
			case NodeType.Button:
			{
				string icon = node.GetString("icon");

				if (icon != null)
					graphic = try CheckedWord(try symbols.Graphic(icon), "graphic ID");

				text = try encoder.TextField(screen, node.GetString("text"), ref symbols, literals);

				string hotkey = node.GetString("hotkey");

				if (hotkey != null)
					extra0 = try ScreenKeys.Parse(hotkey);

				break;
			}
			case NodeType.Input:
			{
				string inputBind = node.GetString("bind");

				if (inputBind != null)
					text = try encoder.Bound(screen, inputBind, ref symbols);

				extra0 = (uint16)node.GetInt("max_length", 0);
				extra1 = try Handler(screen, node.GetString("on_submit"), ref symbols);
				extra2 = Wire.None;
				break;
			}
			case NodeType.List:
			{
				string listSource = node.GetString("source");

				if (listSource != null)
					text = try encoder.Bound(screen, listSource, ref symbols);

				extra0 = (uint16)((node.GetInt("columns", 1) << 8) | node.GetInt("rows", 0));
				extra1 = try Handler(screen, node.GetString("on_select"), ref symbols);
				extra2 = Wire.None;
				break;
			}
			case NodeType.ItemGrid:
			{
				string gridSource = node.GetString("source");

				if (gridSource != null)
					text = try encoder.Bound(screen, gridSource, ref symbols);

				extra0 = (uint16)((node.GetInt("cols", 0) << 8) | node.GetInt("rows", 0));
				extra1 = try Handler(screen, node.GetString("on_select"), ref symbols);
				extra2 = try Handler(screen, node.GetString("on_drop"), ref symbols);
				break;
			}
			case NodeType.Portrait:
				extra0 = (uint16)node.GetInt("slot", 0);
				break;
			case NodeType.Bar:
				extra0 = (uint16)(node.GetString("kind") == "sp" ? 1 : 0);
				extra1 = (uint16)node.GetInt("slot", 0);
				break;
			case NodeType.TextView:
			{
				string viewSource = node.GetString("source");

				if (viewSource != null)
					text = try encoder.Bound(screen, viewSource, ref symbols);
				else
					text = try encoder.TextField(screen, node.GetString("text"), ref symbols, literals);

				extra0 = (uint16)(node.GetBool("paged", true) ? 1 : 0);
				break;
			}
			case NodeType.Viewport:
			{
				string kind = node.GetString("kind");

				extra0 = (uint16)(kind == "map3d" ? 1 : (kind == "battle" ? 2 : 0));
				break;
			}
			default:
			{
				// image and picture
				string gfx = node.GetString("gfx");

				if (gfx != null)
					graphic = try CheckedWord(try symbols.Graphic(gfx), "graphic ID");

				extra0 = (uint16)(node.GetBool("opaque", false) ? 1 : 0);
				break;
			}
		}

		return NodeRecord
		{
			Type = type,
			Flags = (NodeFlags)encoder.Flags,
			Id = node.Id == null ? Wire.None : index,
			Parent = parent,
			X = (int16)node.X,
			Y = (int16)node.Y,
			Width = (int16)node.Width,
			Height = (int16)node.Height,
			Layer = (uint16)node.Layer,
			Graphic = graphic,
			Text = text,
			BindArgument = encoder.BindArgument,
			OnClick = try Handler(screen, node.OnClick, ref symbols),
			OnHover = try Handler(screen, node.OnHover, ref symbols),
			Extra0 = extra0,
			Extra1 = extra1,
			Extra2 = extra2
		};
	}
}

const int ScreenChunkHeaderWords = 16;

/// The flags and the bind argument while one node is encoded (C#: the local variables of EncodeNode that its local
/// functions change).
struct NodeEncoder
{
	int Flags;
	uint16 BindArgument;

	Error<uint16> Bound<TSymbols>(ScreenDefinition screen, string source, ref TSymbols symbols)
		where TSymbols : IScreenSymbols
	{
		Flags = Flags | (int)NodeFlags.Bound;

		// "<node>.detail" and "<node>.name" are the description and the text of the selected row of a list or item grid of
		// the screen itself: 0x8000 | node index, and 0xC000 | node index
		int dot = source.LastIndexOf('.');

		if (dot > 0)
		{
			string suffix = source.Substring(dot + 1);

			if (suffix == "detail" || suffix == "name")
			{
				int listIndex = screen.NodeIndex(source.Substring(0, dot));

				if (listIndex >= 0)
					return (uint16)((int)LocalSource | (source.EndsWith(".name") ? (int)LocalName : 0) | listIndex);
			}
		}

		// "party[2].hp": the index in brackets is the bind argument, the source is "party.hp"
		string name = source;
		int open = name.IndexOf('[');
		int close = name.IndexOf(']');

		if (open > 0 && close > open)
		{
			if (TryParseInt(name.Substring(open + 1, close - open - 1)) is int argument)
			{
				BindArgument = (uint16)argument;
				name = name.Substring(0, open) + name.Substring(close + 1);
			}
		}

		int id = try symbols.Source(name);

		if (id < (int)LocalSource)
			return (uint16)id;

		return error("The data source '" + name + "' has the ID " + id + ", which is reserved for local sources (from 0x8000).", (int)ErrorKind.InvalidData);
	}

	Error<uint16> TextField<TSymbols>(ScreenDefinition screen, string raw, ref TSymbols symbols, List<string> literals)
		where TSymbols : IScreenSymbols
	{
		if (raw == null || raw.Length == 0)
			return 0;

		if (raw.StartsWith("T."))
			return CheckedWord(try symbols.Text(raw.Substring(2)), "text ID");

		if (raw.StartsWith("$"))
		{
			int argument = screen.ArgIndex(raw.Substring(1));

			if (argument < 0)
				return error("Screen '" + screen.Name + "': '" + raw + "' is not an argument of the screen.", (int)ErrorKind.InvalidData);

			return (uint16)((int)ArgumentText | argument);
		}

		literals.Add(raw);

		return (uint16)((int)LiteralText | (literals.Count() - 1));
	}
}

Error<uint16> WordOf(uint8[] data, int wordIndex)
{
	return ScriptChunk.ReadWord(data, wordIndex * 2);
}

Error<uint16> CheckedWord(int value, string what)
{
	if (value < 0 || value > 0xFFFF)
		return error("The " + what + " " + value + " does not fit into a word.", (int)ErrorKind.InvalidData);

	return (uint16)value;
}
