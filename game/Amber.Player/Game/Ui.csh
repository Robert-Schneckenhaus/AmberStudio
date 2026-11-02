// The 2D parts of the user interface: bordered frames, themed boxes (UiTheme looks), the HUD, speech bubbles and the black
// screen of a map change. They keep what they show as draw items; the renderer collects them every frame.

namespace Amber.Player.Game.Ui;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Screens;
using Amber.Player.Game;
using Amber.Player.Graphics;

Color UiBorder = Color.Of(214, 170, 90);
Color UiBackground = Color.Of(28, 22, 44);
Color UiHighlight = Color.Of(70, 50, 100);

const int VirtualWidth = 320;
const int VirtualHeight = 200;

/// The theme sprites that are installed (C#: UiSprites): the pictures of ui.yaml's sprites by name.
struct UiSprites
{
	Dictionary<string, Image> Pictures;

	static UiSprites Empty()
	{
		return UiSprites { Pictures = Dictionary<string, Image>.Create() };
	}

	bool Has(string name)
	{
		return Pictures.ContainsKey(name);
	}

	SpriteSizes Sizes()
	{
		var sizes = SpriteSizes.Create();

		foreach (var pair in Pictures.Entries())
			sizes.Set(pair.Key, pair.Value.Width, pair.Value.Height);

		return sizes;
	}

	SpriteAvailability Availability()
	{
		if (Pictures.Count() == 0)
			return SpriteAvailability.Nothing();

		var names = List<string>.Create();

		foreach (var name in Pictures.Keys())
			names.Add(name);

		return SpriteAvailability.Only(names);
	}
}

/// Reads the sprite files of the theme (the sprite folder is relative to the assets folder, or absolute); the names of the
/// sprites whose file is not installed are added to missing.
UiSprites LoadUiSprites(UiTheme theme, string assetsFolder, List<string> missing)
{
	var sprites = UiSprites.Empty();
	var files = Dictionary<string, Image>.Create();
	string folder = Path.Combine(assetsFolder, theme.SpriteFolder);

	foreach (var pair in theme.Sprites.Entries())
	{
		var source = pair.Value;
		string path = Path.Combine(folder, source.File);

		if (!File.Exists(path))
		{
			missing.Add(pair.Key);

			continue;
		}

		if (!files.ContainsKey(path))
		{
			if (LoadPng(path) is Image loaded)
				files.Set(path, loaded);
			else
			{
				missing.Add(pair.Key);

				continue;
			}
		}

		var file = files.GetOrDefault(path, Image.Empty());

		sprites.Pictures.Set(pair.Key, source.WholeFile() ? file : file.Slice(source.X, source.Y, source.Width, source.Height));
	}

	return sprites;
}

/// The item icons: 16x16 cells of the icon sheet (a licensed pack which is not part of the repository) by cell index.
struct IconSheet
{
	Dictionary<int, Image> Icons;

	static IconSheet Empty()
	{
		return IconSheet { Icons = Dictionary<int, Image>.Create() };
	}

	bool Available()
	{
		return Icons.Count() > 0;
	}
}

const int IconSize = 16;

/// Reads the sheet and cuts the used icons (cell index = row * columns + column). Empty if the sheet is not installed or no
/// icon is used: the game then shows abbreviations instead.
Error<IconSheet> LoadIcons(string sheetPath, List<int> icons)
{
	var result = IconSheet.Empty();

	if (sheetPath == null || !File.Exists(sheetPath) || icons.Count() == 0)
		return result;

	var sheet = try LoadPng(sheetPath);
	int columns = sheet.Width / IconSize;
	int rows = sheet.Height / IconSize;

	foreach (var icon in icons)
	{
		if (icon < 0 || icon / columns >= rows)
			return error("Icon " + icon + " is not in the icon sheet '" + sheetPath + "' (" + columns + " columns, " + rows + " rows).", (int)ErrorKind.InvalidData);

		result.Icons.Set(icon, sheet.Slice(icon % columns * IconSize, icon / columns * IconSize, IconSize, IconSize));
	}

	return result;
}

/// What the user interface draws with: the theme (content/ui.yaml), its installed sprites and the item icons.
struct UiKit
{
	UiTheme Theme;
	UiSprites Sprites;
	IconSheet Icons;

	/// The thickness the border sprites of a look (or its default for kind) add around its content, 0 on a side without
	/// one. A window widget grows its drawn area outward by this so the border sits around the space other nodes use.
	LookInset BorderThickness(string kind, string lookName)
	{
		if (Theme.Resolve(lookName, kind, Sprites.Availability()) is LookDefinition look)
			return LookLayout.BorderThickness(look.Parts, Sprites.Sizes());

		return LookInset.None();
	}

	/// A bordered rectangle (C#: Frame): the border at the layer, the fill one above it.
	void Frame(List<DrawItem> items, int layer, int x, int y, int width, int height, Color border, Color fill)
	{
		items.Add(RectItem(DrawPlane.Panels, layer, x, y, width, height, border));
		items.Add(RectItem(DrawPlane.Panels, layer + 1, x + 2, y + 2, width - 4, height - 4, fill));
	}

	/// A widget background built from the theme (C#: LookBox.Update): rectangles on the panel plane, sprites above them in
	/// the order the look lists them. Falls back to a plain bordered rectangle when the widget kind has no look or a
	/// look's sprites are not installed.
	void LookBox(List<DrawItem> items, int baseLayer, string kind, string lookName, string state, int x, int y, int width, int height, Color fallbackBorder, Color fallbackFill)
	{
		int rectIndex = 0;
		int spriteIndex = 0;

		if (Theme.Resolve(lookName, kind, Sprites.Availability()) is LookDefinition look)
		{
			var elements = LookLayout.Place(look, state, x, y, width, height, Sprites.Sizes());
			var backRects = List<LookElement>.Create();
			var sprites = List<LookElement>.Create();
			var frontRects = List<LookElement>.Create();

			foreach (var element in elements)
			{
				if (element.IsSprite())
					sprites.Add(element);
				else if (element.Front)
					frontRects.Add(element);
				else
					backRects.Add(element);
			}

			foreach (var element in SortArray(ArrayOf(backRects), CompareLookRank))
			{
				items.Add(RectItem(DrawPlane.Panels, Min(255, baseLayer + rectIndex), element.X, element.Y, Max(0, element.Width), Max(0, element.Height), ToColor(element.Color)));
				rectIndex += 1;
			}

			foreach (var element in SortArray(ArrayOf(sprites), CompareLookRank))
			{
				items.Add(PictureItem(DrawPlane.UiSprites, Min(255, baseLayer + spriteIndex), Sprites.Pictures.GetOrDefault(element.Sprite, Image.Empty()), element.X, element.Y,
					element.Width, element.Height));
				spriteIndex += 1;
			}

			foreach (var element in SortArray(ArrayOf(frontRects), CompareLookRank))
			{
				items.Add(RectItem(DrawPlane.Panels, Min(255, baseLayer + rectIndex), element.X, element.Y, Max(0, element.Width), Max(0, element.Height), ToColor(element.Color)));
				rectIndex += 1;
			}

			return;
		}

		items.Add(RectItem(DrawPlane.Panels, baseLayer, x, y, Max(0, width), Max(0, height), fallbackBorder));
		items.Add(RectItem(DrawPlane.Panels, Min(255, baseLayer + 1), x + 2, y + 2, Max(0, width - 4), Max(0, height - 4), fallbackFill));
	}
}

int CompareLookRank(LookElement a, LookElement b)
{
	return CompareInt(a.Rank, b.Rank);
}

Color ToColor(LookColor color)
{
	return Color.OfAlpha((int)color.R, (int)color.G, (int)color.B, (int)color.A);
}

struct BubbleState
{
	bool HasOwner;
	Actor Owner;
	int Remaining;
	int Width;
	int Height;
	string Text;
	List<DrawItem> Items;
}

/// A short text over an actor (barks) that disappears after a while.
struct Bubble
{
	BubbleState[] _s;

	static Bubble Create()
	{
		var state = new BubbleState[1];

		state[0].Items = List<DrawItem>.Create();
		state[0].Text = "";

		return Bubble { _s = state };
	}

	bool OwnedBy(Actor actor)
	{
		return _s[0].HasOwner && _s[0].Owner.Same(actor);
	}

	bool Active()
	{
		return _s[0].Remaining > 0;
	}

	List<DrawItem> Items()
	{
		return _s[0].Items;
	}

	void Start(Actor owner, string text, int ticks)
	{
		var lines = Wrap(text, 132);
		int widest = 0;

		foreach (var line in lines)
			widest = Max(widest, TextLength(line));

		_s[0].HasOwner = true;
		_s[0].Owner = owner;
		_s[0].Remaining = ticks;
		_s[0].Width = widest * CellWidth + 8;
		_s[0].Height = lines.Count() * LineHeight + 6;
		_s[0].Text = JoinList("\n", lines);
		// the label is placed at (0, 0) until the first update, the frame keeps its last place (C#: Frame, TextLabel)
		_s[0].Items.Clear();
		_s[0].Items.Add(TextItem(32, _s[0].Text, 0, 0, TextColor.White));
	}

	void Stop()
	{
		_s[0].Remaining = 0;
		_s[0].Items.Clear();
	}

	void Update(int cameraX, int cameraY)
	{
		if (!_s[0].HasOwner || _s[0].Remaining <= 0)
			return;

		_s[0].Remaining -= 1;

		if (_s[0].Remaining == 0)
		{
			_s[0].Items.Clear();

			return;
		}

		var owner = _s[0].Owner;
		int width = _s[0].Width;
		int height = _s[0].Height;
		int x = Clamp(owner.PixelX() - cameraX + owner.Art().Width / 2 - width / 2, 2, VirtualWidth - width - 2);
		int y = Max(20, owner.PixelY() - cameraY - height - 3);

		_s[0].Items.Clear();
		_s[0].Items.Add(RectItem(DrawPlane.Panels, 30, x, y, width, height, UiBorder));
		_s[0].Items.Add(RectItem(DrawPlane.Panels, 31, x + 2, y + 2, width - 4, height - 4, UiBackground));
		_s[0].Items.Add(TextItem(32, _s[0].Text, x + 4, y + 3, TextColor.White));
	}
}

struct HudState
{
	int NoticeTicks;
	bool Suppressed;
	string NoticeText;
	int NoticeX;
	int NoticeWidth;
	List<DrawItem> Items;
}

/// The always visible parts of the screen: place and time, gold, a short-lived notice line, key help.
struct Hud
{
	HudState[] _s;

	static Hud Create()
	{
		var state = new HudState[1];

		state[0].Items = List<DrawItem>.Create();
		state[0].NoticeText = "";

		return Hud { _s = state };
	}

	List<DrawItem> Items()
	{
		return _s[0].Items;
	}

	void ShowNotice(string text, int ticks)
	{
		_s[0].NoticeWidth = TextLength(text) * CellWidth + 10;
		_s[0].NoticeX = VirtualWidth - _s[0].NoticeWidth - 2;
		_s[0].NoticeText = text;
		_s[0].NoticeTicks = ticks;
	}

	/// Hides the whole HUD (during map changes).
	void SetSuppressed(bool value)
	{
		_s[0].Suppressed = value;
	}

	void Update(string place, string time, int gold, int hp, int maxHp, bool showHelp)
	{
		var items = _s[0].Items;

		items.Clear();

		if (_s[0].Suppressed)
		{
			_s[0].NoticeTicks = 0;

			return;
		}

		string text = place + "  " + time + "  " + gold + " G  HP " + hp + "/" + maxHp;

		items.Add(RectItem(DrawPlane.Panels, 20, 2, 2, TextLength(text) * CellWidth + 10, 15, UiBorder));
		items.Add(RectItem(DrawPlane.Panels, 21, 4, 4, TextLength(text) * CellWidth + 6, 11, UiBackground));
		items.Add(TextItem(22, text, 7, 6, TextColor.White));

		if (showHelp)
		{
			items.Add(RectItem(DrawPlane.Panels, 20, 2, 185, 274, 14, UiBorder));
			items.Add(RectItem(DrawPlane.Panels, 21, 4, 187, 270, 10, UiBackground));
			items.Add(TextItem(22, "Arrows: walk  Space: talk/examine  I: items", 7, 189, TextColor.Gray));
		}

		if (_s[0].NoticeTicks > 0)
		{
			items.Add(RectItem(DrawPlane.Panels, 20, _s[0].NoticeX, 2, _s[0].NoticeWidth, 15, UiBorder));
			items.Add(RectItem(DrawPlane.Panels, 21, _s[0].NoticeX + 2, 4, _s[0].NoticeWidth - 4, 11, UiBackground));
			items.Add(TextItem(22, _s[0].NoticeText, _s[0].NoticeX + 5, 6, TextColor.Yellow));
			_s[0].NoticeTicks -= 1;

			// the notice disappears in the tick its time runs out
			if (_s[0].NoticeTicks == 0)
			{
				items.RemoveAt(items.Count() - 1);
				items.RemoveAt(items.Count() - 1);
				items.RemoveAt(items.Count() - 1);
			}
		}
	}
}

/// A short black screen when the party changes the map.
struct ScreenFade
{
	int[] _remaining;

	static ScreenFade Create()
	{
		return ScreenFade { _remaining = new int[1] };
	}

	bool Active()
	{
		return _remaining[0] > 0;
	}

	void Start(int ticks)
	{
		_remaining[0] = ticks;
	}

	void Update()
	{
		if (_remaining[0] > 0)
			_remaining[0] -= 1;
	}

	void Draw(DrawList list)
	{
		if (_remaining[0] > 0)
			list.Add(RectItem(DrawPlane.Panels, 250, 0, 0, VirtualWidth, VirtualHeight, Color.Of(0, 0, 0)));
	}
}
