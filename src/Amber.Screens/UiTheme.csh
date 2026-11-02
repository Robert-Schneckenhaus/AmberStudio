namespace Amber.Screens;

using System;
using Amber.Base;

/// An RGBA color of a look (no dependency on a graphics library).
struct LookColor
{
	uint8 R;
	uint8 G;
	uint8 B;
	uint8 A;

	static LookColor Of(int r, int g, int b)
	{
		return LookColor { R = (uint8)r, G = (uint8)g, B = (uint8)b, A = 255 };
	}

	static LookColor OfAlpha(int r, int g, int b, int a)
	{
		return LookColor { R = (uint8)r, G = (uint8)g, B = (uint8)b, A = (uint8)a };
	}

	bool Same(LookColor other)
	{
		return R == other.R && G == other.G && B == other.B && A == other.A;
	}
}

/// Where a sprite of the theme comes from: a file of the sprite folder, or a rectangle of a sheet file.
struct SpriteSource
{
	string File;
	int X;
	int Y;
	int Width;
	int Height;

	/// True if the whole file is used (no rectangle given).
	bool WholeFile()
	{
		return Width == 0 && Height == 0;
	}
}

enum LookPartKind : int32
{
	/// A filled rectangle.
	Rect,
	/// A ring of colored lines around the area.
	Frame,
	/// The area filled with copies of a sprite.
	Tile,
	/// Corner sprites and edge sprites which repeat along the edges.
	Border,
	/// One sprite in the area.
	Image
}

/// The distance of a part from the edges of the widget. FromBorder: the thickness of the border part of the same look (a
/// fill inside a sprite border).
struct LookInset
{
	int Left;
	int Top;
	int Right;
	int Bottom;
	bool FromBorder;

	static LookInset None()
	{
		return LookInset { Left = 0, Top = 0, Right = 0, Bottom = 0, FromBorder = false };
	}

	static LookInset Of(int left, int top, int right, int bottom)
	{
		return LookInset { Left = left, Top = top, Right = right, Bottom = bottom, FromBorder = false };
	}

	bool Same(LookInset other)
	{
		return Left == other.Left && Top == other.Top && Right == other.Right && Bottom == other.Bottom && FromBorder == other.FromBorder;
	}
}

/// The names of the eight sprites of a border. Missing ones are null.
struct BorderSprites
{
	string TopLeft;
	string Top;
	string TopRight;
	string Left;
	string Right;
	string BottomLeft;
	string Bottom;
	string BottomRight;

	string[] All()
	{
		return new string[] { TopLeft, Top, TopRight, Left, Right, BottomLeft, Bottom, BottomRight };
	}
}

/// One layer of a look: what is drawn, in the order of the list (later parts cover earlier ones of the same kind).
struct LookPart
{
	LookPartKind Kind;
	LookColor Color;
	/// Sprite of a tile or image, or null.
	string Sprite;
	LookInset Inset;
	/// Colored areas lie below the sprites; "front" puts them above (highlights on a sprite).
	bool Front;
	/// Line width of a frame.
	int Width;
	/// Image: where it sits in the area (center, left, right, top, bottom, top_left ...).
	string Align;
	int OffsetX;
	int OffsetY;
	/// Image: scale to the size of the area.
	bool Stretch;
	Optional<BorderSprites> Border;

	static LookPart Create(LookPartKind kind)
	{
		return LookPart { Kind = kind, Inset = LookInset.None(), Width = 1, Align = "center", Border = null };
	}
}

/// A named appearance of a widget: parts for the normal state and optionally other parts for further states (hover,
/// focused, disabled ... or the bar states high, medium, low). A state without an entry looks like the normal one.
struct LookDefinition
{
	string Name;
	/// The look used instead when a sprite of this one is not available (null: the widget draws its built-in flat look).
	string Fallback;
	LookPart[] Parts;
	Dictionary<string, LookPart[]> States;

	LookPart[] PartsFor(string state)
	{
		if (States.TryGet(state) is LookPart[] parts)
			return parts;

		return Parts;
	}

	/// The names of all sprites the look uses (each once).
	List<string> SpriteNames()
	{
		var names = List<string>.Create();

		AddSprites(names, Parts);

		foreach (var parts in States.Values())
			AddSprites(names, parts);

		return names;
	}

	static void AddSprites(List<string> names, LookPart[] parts)
	{
		foreach (var part in parts)
		{
			if (part.Sprite != null && !ContainsText(names, part.Sprite))
				names.Add(part.Sprite);

			if (part.Border is BorderSprites border)
			{
				foreach (var name in border.All())
				{
					if (name != null && !ContainsText(names, name))
						names.Add(name);
				}
			}
		}
	}
}

/// Which sprites a game has loaded (C#: the predicate Func<string, bool> hasSprite).
struct SpriteAvailability
{
	bool All;
	HashSet<string> Names;

	static SpriteAvailability Everything()
	{
		return SpriteAvailability { All = true, Names = HashSet<string>.Create() };
	}

	static SpriteAvailability Nothing()
	{
		return SpriteAvailability { All = false, Names = HashSet<string>.Create() };
	}

	/// All sprites except the given ones.
	static SpriteAvailability AllBut(string[] missing)
	{
		var names = HashSet<string>.Create();

		foreach (var name in missing)
			names.Add(name);

		return SpriteAvailability { All = true, Names = names };
	}

	static SpriteAvailability Only(List<string> names)
	{
		var set = HashSet<string>.Create();

		foreach (var name in names)
			set.Add(name);

		return SpriteAvailability { All = false, Names = set };
	}

	bool Has(string name)
	{
		return All ? !Names.Contains(name) : Names.Contains(name);
	}
}

/// The user interface theme of a game (content/ui.yaml): the sprites, the colors, the looks built from them and which look
/// each kind of widget uses by default. Windows, buttons, grids and bars can be put together from sprites and colored
/// areas.
struct UiTheme
{
	/// The folder of the sprite files (relative to the assets folder of the game, or absolute).
	string SpriteFolder;
	Dictionary<string, SpriteSource> Sprites;
	Dictionary<string, LookDefinition> Looks;
	/// The look name for a widget kind ("window", "button", "input", "itemgrid", "bar", "hud" ...), used when a node names
	/// none.
	Dictionary<string, string> Defaults;

	static UiTheme Empty()
	{
		return UiTheme
		{
			SpriteFolder = "",
			Sprites = Dictionary<string, SpriteSource>.Create(),
			Looks = Dictionary<string, LookDefinition>.Create(),
			Defaults = Dictionary<string, string>.Create()
		};
	}

	/// The look for a node: the named one (null: none named), else the default of the widget kind. No value means "draw
	/// flat". A look with a sprite that is not available is replaced by its fallback, so a game without the sprite files
	/// still works.
	Optional<LookDefinition> Resolve(string name, string kind, SpriteAvailability available)
	{
		string current = name;

		if (current == null)
			current = Defaults.GetOrDefault(kind, null);

		var seen = HashSet<string>.Create();

		while (current != null && current != NoLook)
		{
			if (!seen.Add(current))
				return null;

			if (Looks.TryGet(current) is LookDefinition look)
			{
				bool complete = true;

				foreach (var sprite in look.SpriteNames())
				{
					if (!available.Has(sprite))
						complete = false;
				}

				if (complete)
					return look;

				current = look.Fallback;
			}
			else
			{
				return null;
			}
		}

		return null;
	}

	static Error<UiTheme> Load(string path)
	{
		string text = try ReadText(path);
		var theme = Parse(text);

		if (theme is UiTheme parsed)
			return parsed;

		return error(path + ": " + theme.Message, theme.Code);
	}

	static Error<UiTheme> Parse(string yaml)
	{
		var document = ParseYaml(yaml);
		var root = YamlNode.Mapping(0);

		if (document is YamlNode node)
			root = try ThemeMap(node, "the document");
		else
			return error(document.Message, (int)ErrorKind.InvalidData);

		try CheckKeys(root, "the document", new string[] { "sprite_folder", "sprites", "colors", "defaults", "looks" });

		var colors = Dictionary<string, LookColor>.Create();
		var colorMap = try MapOf(root, "colors");

		for (var i = 0; i < colorMap.Count(); i += 1)
		{
			string name = colorMap.KeyAt(i);

			colors.Set(name, try ParseColor(try Text(colorMap.ItemAt(i), "color '" + name + "'"), colors, "color '" + name + "'"));
		}

		var sprites = Dictionary<string, SpriteSource>.Create();
		var spriteMap = try MapOf(root, "sprites");

		for (var i = 0; i < spriteMap.Count(); i += 1)
			sprites.Set(spriteMap.KeyAt(i), try ParseSprite(spriteMap.KeyAt(i), spriteMap.ItemAt(i)));

		var defaults = Dictionary<string, string>.Create();
		var defaultMap = try MapOf(root, "defaults");

		for (var i = 0; i < defaultMap.Count(); i += 1)
			defaults.Set(defaultMap.KeyAt(i), try Text(defaultMap.ItemAt(i), "default look of '" + defaultMap.KeyAt(i) + "'"));

		var theme = Empty();

		theme.Sprites = sprites;
		theme.Defaults = defaults;

		if (root.GetValue("sprite_folder") is YamlNode folder)
			theme.SpriteFolder = try Text(folder, "sprite_folder");

		var lookMap = try MapOf(root, "looks");

		for (var i = 0; i < lookMap.Count(); i += 1)
		{
			string name = lookMap.KeyAt(i);

			theme.Looks.Set(name, try ParseLook(name, try ThemeMap(lookMap.ItemAt(i), "look '" + name + "'"), colors, sprites));
		}

		foreach (var look in theme.Looks.Values())
		{
			if (look.Fallback != null && look.Fallback != NoLook && !theme.Looks.ContainsKey(look.Fallback))
				return error("look '" + look.Name + "': the fallback look '" + look.Fallback + "' does not exist.", (int)ErrorKind.InvalidData);

			var chain = HashSet<string>.Create();

			chain.Add(look.Name);

			string next = look.Fallback;

			while (next != null && next != NoLook)
			{
				if (!chain.Add(next))
					return error("look '" + look.Name + "': the fallbacks form a cycle.", (int)ErrorKind.InvalidData);

				next = theme.Looks.GetOrDefault(next, LookDefinition { Fallback = null }).Fallback;
			}
		}

		foreach (var entry in defaults.Entries())
		{
			if (entry.Value != NoLook && !theme.Looks.ContainsKey(entry.Value))
				return error("the default look of '" + entry.Key + "' is '" + entry.Value + "', which does not exist.", (int)ErrorKind.InvalidData);
		}

		return theme;
	}

	static Error<LookDefinition> ParseLook(string name, YamlNode data, Dictionary<string, LookColor> colors, Dictionary<string, SpriteSource> sprites)
	{
		try CheckKeys(data, "look '" + name + "'", new string[] { "fallback", "parts", "states" });

		var parts = try ParseParts(name, data.Get("parts"), colors, sprites);
		var states = Dictionary<string, LookPart[]>.Create();
		var stateMap = try MapOf(data, "states");

		for (var i = 0; i < stateMap.Count(); i += 1)
			states.Set(stateMap.KeyAt(i), try ParseParts(name + "/" + stateMap.KeyAt(i), stateMap.Get(stateMap.KeyAt(i)), colors, sprites));

		string fallback = null;

		if (data.GetValue("fallback") is YamlNode fallbackValue)
			fallback = try Text(fallbackValue, "look '" + name + "' fallback");

		return LookDefinition { Name = name, Fallback = fallback, Parts = parts, States = states };
	}

	static Error<LookPart[]> ParseParts(string owner, Optional<YamlNode> value, Dictionary<string, LookColor> colors, Dictionary<string, SpriteSource> sprites)
	{
		var parts = List<LookPart>.Create();

		if (value is YamlNode list)
		{
			if (list.IsNull())
				return ArrayOf(parts);

			if (!list.IsSequence())
				return error("look '" + owner + "': parts must be a list.", (int)ErrorKind.InvalidData);

			for (var i = 0; i < list.Count(); i += 1)
			{
				var entry = try ThemeMap(list.ItemAt(i), "a part of look '" + owner + "'");

				if (entry.Count() != 1 || !ContainsText(PartKeys, entry.KeyAt(0)))
					return error("look '" + owner + "': every part is one of " + string.Join(", ", PartKeys.ToArray()) + ".", (int)ErrorKind.InvalidData);

				string kind = entry.KeyAt(0);

				parts.Add(try ParsePart(owner, kind, try ThemeMap(entry.ItemAt(0), "part '" + kind + "' of look '" + owner + "'"), colors, sprites));
			}
		}

		return ArrayOf(parts);
	}

	static Error<LookPart> ParsePart(string owner, string kind, YamlNode body, Dictionary<string, LookColor> colors, Dictionary<string, SpriteSource> sprites)
	{
		string context = "part '" + kind + "' of look '" + owner + "'";
		var inset = LookInset.None();
		bool front = false;

		if (body.Get("inset") is YamlNode insetValue)
			inset = try ParseInset(insetValue, context);

		if (body.GetValue("layer") is YamlNode layer)
		{
			string side = try Text(layer, context);

			if (side == "front")
				front = true;
			else if (side != "back")
				return error(context + ": layer is 'back' or 'front'.", (int)ErrorKind.InvalidData);
		}

		switch (kind)
		{
			case "rect":
			{
				try CheckKeys(body, context, new string[] { "color", "inset", "layer" });

				var part = LookPart.Create(LookPartKind.Rect);

				part.Color = try PartColor(body, "color", colors, context);
				part.Inset = inset;
				part.Front = front;

				return part;
			}
			case "frame":
			{
				try CheckKeys(body, context, new string[] { "color", "width", "inset", "layer" });

				var part = LookPart.Create(LookPartKind.Frame);

				part.Color = try PartColor(body, "color", colors, context);

				if (body.GetValue("width") is YamlNode width)
					part.Width = try Number(width, context);

				part.Inset = inset;
				part.Front = front;

				return part;
			}
			case "tile":
			{
				try CheckKeys(body, context, new string[] { "sprite", "inset" });

				var part = LookPart.Create(LookPartKind.Tile);

				part.Sprite = try PartSprite(body, "sprite", sprites, context);
				part.Inset = inset;

				return part;
			}
			case "border":
			{
				try CheckKeys(body, context, new string[] { "top_left", "top", "top_right", "left", "right", "bottom_left", "bottom", "bottom_right", "inset" });

				var part = LookPart.Create(LookPartKind.Border);

				part.Border = BorderSprites
				{
					TopLeft = try OptionalSprite(body, "top_left", sprites, context),
					Top = try OptionalSprite(body, "top", sprites, context),
					TopRight = try OptionalSprite(body, "top_right", sprites, context),
					Left = try OptionalSprite(body, "left", sprites, context),
					Right = try OptionalSprite(body, "right", sprites, context),
					BottomLeft = try OptionalSprite(body, "bottom_left", sprites, context),
					Bottom = try OptionalSprite(body, "bottom", sprites, context),
					BottomRight = try OptionalSprite(body, "bottom_right", sprites, context)
				};
				part.Inset = inset;

				return part;
			}
			default:
			{
				try CheckKeys(body, context, new string[] { "sprite", "align", "dx", "dy", "stretch", "inset" });

				var part = LookPart.Create(LookPartKind.Image);

				part.Sprite = try PartSprite(body, "sprite", sprites, context);
				part.Inset = inset;

				if (body.GetValue("align") is YamlNode align)
					part.Align = try Text(align, context);

				if (body.GetValue("dx") is YamlNode dx)
					part.OffsetX = try Number(dx, context);

				if (body.GetValue("dy") is YamlNode dy)
					part.OffsetY = try Number(dy, context);

				if (body.GetValue("stretch") is YamlNode stretch)
					part.Stretch = try Text(stretch, context) == "true";

				return part;
			}
		}
	}

	static Error<string> PartSprite(YamlNode body, string key, Dictionary<string, SpriteSource> sprites, string context)
	{
		if (body.GetValue(key) is YamlNode value)
		{
			string name = try Text(value, key);

			if (sprites.ContainsKey(name))
				return name;

			return error(context + ": the sprite '" + name + "' is not defined.", (int)ErrorKind.InvalidData);
		}

		return error(context + ": '" + key + "' is missing.", (int)ErrorKind.InvalidData);
	}

	static Error<string> OptionalSprite(YamlNode body, string key, Dictionary<string, SpriteSource> sprites, string context)
	{
		if (!body.ContainsKey(key))
			return (string)null;

		return PartSprite(body, key, sprites, context);
	}

	static Error<LookColor> PartColor(YamlNode body, string key, Dictionary<string, LookColor> colors, string context)
	{
		if (body.GetValue(key) is YamlNode value)
			return ParseColor(try Text(value, key), colors, context);

		return error(context + ": '" + key + "' is missing.", (int)ErrorKind.InvalidData);
	}

	static Error<LookInset> ParseInset(YamlNode value, string context)
	{
		if (value.IsScalar())
		{
			if (value.Value == "border")
				return LookInset { Left = 0, Top = 0, Right = 0, Bottom = 0, FromBorder = true };

			int all = try Number(value, context);

			return LookInset.Of(all, all, all, all);
		}

		if (value.IsSequence() && value.Count() == 2)
		{
			int horizontal = try Number(value.ItemAt(0), context);
			int vertical = try Number(value.ItemAt(1), context);

			return LookInset.Of(horizontal, vertical, horizontal, vertical);
		}

		if (value.IsSequence() && value.Count() == 4)
			return LookInset.Of(try Number(value.ItemAt(0), context), try Number(value.ItemAt(1), context), try Number(value.ItemAt(2), context), try Number(value.ItemAt(3), context));

		return error(context + ": inset is a number, [horizontal, vertical], [left, top, right, bottom] or 'border'.", (int)ErrorKind.InvalidData);
	}

	static Error<SpriteSource> ParseSprite(string name, YamlNode value)
	{
		if (value.IsScalar())
			return SpriteSource { File = value.Value, X = 0, Y = 0, Width = 0, Height = 0 };

		var map = try ThemeMap(value, "sprite '" + name + "'");

		try CheckKeys(map, "sprite '" + name + "'", new string[] { "file", "x", "y", "w", "h" });

		var file = map.GetValue("file");

		if (file == null)
			return error("sprite '" + name + "': 'file' is missing.", (int)ErrorKind.InvalidData);

		string source = "";

		if (file is YamlNode fileValue)
			source = try Text(fileValue, "file");

		int width = try SpriteNumber(map, "w", name);
		int height = try SpriteNumber(map, "h", name);

		if ((width == 0) != (height == 0))
			return error("sprite '" + name + "': give both w and h, or none.", (int)ErrorKind.InvalidData);

		return SpriteSource { File = source, X = try SpriteNumber(map, "x", name), Y = try SpriteNumber(map, "y", name), Width = width, Height = height };
	}

	static Error<int> SpriteNumber(YamlNode map, string key, string name)
	{
		if (map.GetValue(key) is YamlNode value)
			return Number(value, "sprite '" + name + "'");

		return 0;
	}

	/// "#rrggbb", "#rrggbbaa", "0xrrggbb" or the name of an entry of colors.
	static Error<LookColor> ParseColor(string text, Dictionary<string, LookColor> colors, string context)
	{
		if (colors.TryGet(text) is LookColor named)
			return named;

		string digits = "";

		if (text.StartsWith("#"))
			digits = text.Substring(1);
		else if (text.StartsWith("0x") || text.StartsWith("0X"))
			digits = text.Substring(2);

		if (digits.Length == 6 || digits.Length == 8)
		{
			if (TryParseHex(digits) is uint64 value)
			{
				if (digits.Length == 6)
					return LookColor.Of((int)((value >> 16) & 0xFF), (int)((value >> 8) & 0xFF), (int)(value & 0xFF));

				return LookColor.OfAlpha((int)((value >> 24) & 0xFF), (int)((value >> 16) & 0xFF), (int)((value >> 8) & 0xFF), (int)(value & 0xFF));
			}
		}

		return error(context + ": '" + text + "' is not a color (#rrggbb, 0xrrggbb or a name from colors).", (int)ErrorKind.InvalidData);
	}

	static Error<YamlNode> ThemeMap(YamlNode value, string what)
	{
		if (!value.IsMapping())
			return error(what + " must be a mapping.", (int)ErrorKind.InvalidData);

		return value;
	}

	/// The mapping of the key; a missing or null value is an empty mapping.
	static Error<YamlNode> MapOf(YamlNode parent, string key)
	{
		if (parent.GetValue(key) is YamlNode value)
			return ThemeMap(value, "'" + key + "'");

		return YamlNode.Mapping(0);
	}

	static Error<string> Text(YamlNode value, string what)
	{
		if (!value.IsScalar())
			return error(what + " must be a text or a number.", (int)ErrorKind.InvalidData);

		return value.Value;
	}

	static Error<int> Number(YamlNode value, string what)
	{
		if (value.IsScalar())
		{
			if (TryParseInt(value.Value) is int number)
				return number;
		}

		return error(what + ": '" + (value.IsScalar() ? value.Value : value.Describe()) + "' is not a whole number.", (int)ErrorKind.InvalidData);
	}

	static Error<void> CheckKeys(YamlNode map, string what, string[] allowed)
	{
		for (var i = 0; i < map.Count(); i += 1)
		{
			if (!ContainsText(allowed, map.KeyAt(i)))
				return error(what + ": unknown key '" + map.KeyAt(i) + "' (allowed: " + string.Join(", ", allowed) + ").", (int)ErrorKind.InvalidData);
		}

		return;
	}
}

/// The look name which stands for "the built-in flat look".
const string NoLook = "none";

const ReadOnlySlice<string> PartKeys = ["rect", "frame", "tile", "border", "image"];
