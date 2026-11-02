// The software renderer of the prototype (C#: the layers of the Amber OpenGL renderer). Everything that is visible in a
// frame is a draw item: colored rectangles, pictures and texts. The items are sorted like the layers of the C# renderer
// and drawn into a 320x200 RGBA frame (640x400 in the editor), which the window scales up or a screenshot writes.

namespace Amber.Player.Graphics;

using System;
using Amber.Base;
using Amber.Graphics;

/// The planes in drawing order (C#: the renderer layers with their base Z): the map, then the colored panels of the user
/// interface, the theme sprites, the item icons and the text on top.
enum DrawPlane : int32
{
	Ground = 0,
	Decor = 1,
	World = 2,
	Panels = 3,
	UiSprites = 4,
	Icons = 5,
	Text = 6
}

enum DrawKind : int32
{
	Rect = 0,
	Picture = 1,
	Text = 2,
	/// A palette picture (Ziele Z4): indices, drawn with the colors of a palette at render time; index 0 is transparent.
	Indexed = 3
}

enum TextColor : int32
{
	White,
	Yellow,
	Gray,
	Cyan,
	Green,
	Red,
	Orange,
	Black
}

Color[] TextColors = new Color[]
{
	Color.Of(245, 245, 235), Color.Of(255, 222, 90), Color.Of(150, 150, 160), Color.Of(120, 220, 240),
	Color.Of(140, 230, 120), Color.Of(240, 100, 90), Color.Of(255, 170, 60), Color.Of(20, 20, 30)
};

/// One thing to draw. Layer is the display layer of the plane (UI) or the base line (world plane: the bottom edge plus
/// the base line offset; the higher one is drawn later).
struct DrawItem
{
	DrawPlane Plane;
	int Layer;
	int Order;
	DrawKind Kind;
	int X;
	int Y;
	int Width;
	int Height;
	Color Color;
	Image Picture;
	string Text;
	TextColor TextColor;
	/// Indexed: one palette index per pixel (Width x Height, native size) and the palette (3 bytes per entry).
	uint8[] Indices;
	uint8[] PaletteRgb;
}

DrawItem RectItem(DrawPlane plane, int layer, int x, int y, int width, int height, Color color)
{
	return DrawItem { Plane = plane, Layer = layer, Kind = DrawKind.Rect, X = x, Y = y, Width = width, Height = height, Color = color };
}

/// A picture scaled to the rectangle (the native size if width or height is 0).
DrawItem PictureItem(DrawPlane plane, int layer, Image picture, int x, int y, int width, int height)
{
	return DrawItem
	{
		Plane = plane, Layer = layer, Kind = DrawKind.Picture, X = x, Y = y, Width = width == 0 ? picture.Width : width,
		Height = height == 0 ? picture.Height : height, Picture = picture
	};
}

/// A palette picture in its native size; the palette is read when the frame is rendered, so a palette that changes (day and
/// night, a fade) changes the picture without touching it.
DrawItem IndexedItem(DrawPlane plane, int layer, uint8[] indices, int width, int height, uint8[] paletteRgb, int x, int y)
{
	return DrawItem
	{
		Plane = plane, Layer = layer, Kind = DrawKind.Indexed, X = x, Y = y, Width = width, Height = height, Indices = indices, PaletteRgb = paletteRgb
	};
}

DrawItem TextItem(int layer, string text, int x, int y, TextColor color)
{
	return DrawItem { Plane = DrawPlane.Text, Layer = layer, Kind = DrawKind.Text, X = x, Y = y, Text = text, TextColor = color };
}

/// The items of one frame. Copies share the items.
struct DrawList
{
	List<DrawItem> Items;

	static DrawList Create()
	{
		return DrawList { Items = List<DrawItem>.Create() };
	}

	void Add(DrawItem item)
	{
		item.Order = Items.Count();
		Items.Add(item);
	}

	void AddAll(List<DrawItem> items)
	{
		foreach (var item in items)
			Add(item);
	}

	void Clear()
	{
		Items.Clear();
	}

	/// Draws the items into the frame, sorted by plane, then layer, then the order they were added in.
	void Render(Image frame)
	{
		var sorted = SortArray(ArrayOf(Items), CompareDrawItems);

		foreach (var item in sorted)
		{
			if (item.Kind == DrawKind.Rect)
				FillBlended(frame, item.X, item.Y, item.Width, item.Height, item.Color);
			else if (item.Kind == DrawKind.Picture)
				DrawPicture(frame, item.Picture, item.X, item.Y, item.Width, item.Height);
			else if (item.Kind == DrawKind.Indexed)
				DrawIndexed(frame, item.Indices, item.Width, item.Height, item.PaletteRgb, item.X, item.Y);
			else
				DrawText(frame, item.Text, item.X, item.Y, item.TextColor);
		}
	}
}

int CompareDrawItems(DrawItem a, DrawItem b)
{
	if (a.Plane != b.Plane)
		return (int)a.Plane < (int)b.Plane ? -1 : 1;

	if (a.Layer != b.Layer)
		return a.Layer < b.Layer ? -1 : 1;

	return CompareInt(a.Order, b.Order);
}

void Blend(Image frame, int x, int y, int red, int green, int blue, int alpha)
{
	if (x < 0 || y < 0 || x >= frame.Width || y >= frame.Height || alpha == 0)
		return;

	int index = (y * frame.Width + x) * 4;

	if (alpha == 255)
	{
		frame.Data[index] = (uint8)red;
		frame.Data[index + 1] = (uint8)green;
		frame.Data[index + 2] = (uint8)blue;
		frame.Data[index + 3] = 255;

		return;
	}

	// rounded to the nearest value, like the GPU writes a blended color into an 8 bit framebuffer
	frame.Data[index] = (uint8)((red * alpha + (int)frame.Data[index] * (255 - alpha) + 127) / 255);
	frame.Data[index + 1] = (uint8)((green * alpha + (int)frame.Data[index + 1] * (255 - alpha) + 127) / 255);
	frame.Data[index + 2] = (uint8)((blue * alpha + (int)frame.Data[index + 2] * (255 - alpha) + 127) / 255);
	frame.Data[index + 3] = 255;
}

void FillBlended(Image frame, int x, int y, int width, int height, Color color)
{
	int left = Max0(x);
	int top = Max0(y);
	int right = x + width < frame.Width ? x + width : frame.Width;
	int bottom = y + height < frame.Height ? y + height : frame.Height;

	for (var row = top; row < bottom; row += 1)
	{
		for (var column = left; column < right; column += 1)
			Blend(frame, column, row, (int)color.R, (int)color.G, (int)color.B, (int)color.A);
	}
}

int Max0(int value)
{
	return value < 0 ? 0 : value;
}

/// Draws a picture scaled to the rectangle (nearest neighbor). Like the texture shader of the Amber engine (the layers
/// of the C# version use Transparency, never Alpha) a pixel is either drawn opaque (alpha 128 and more) or not at all.
void DrawPicture(Image frame, Image picture, int x, int y, int width, int height)
{
	if (picture.Width == 0 || picture.Height == 0 || width <= 0 || height <= 0)
		return;

	int top = Max0(y);
	int bottom = y + height < frame.Height ? y + height : frame.Height;
	int left = Max0(x);
	int right = x + width < frame.Width ? x + width : frame.Width;

	for (var row = top; row < bottom; row += 1)
	{
		int sourceY = (row - y) * picture.Height / height;

		for (var column = left; column < right; column += 1)
		{
			int sourceX = (column - x) * picture.Width / width;
			int index = (sourceY * picture.Width + sourceX) * 4;

			if (picture.Data[index + 3] >= 128)
				Blend(frame, column, row, (int)picture.Data[index], (int)picture.Data[index + 1], (int)picture.Data[index + 2], 255);
		}
	}
}

/// Draws a palette picture in its native size; index 0 is transparent.
void DrawIndexed(Image frame, uint8[] indices, int width, int height, uint8[] palette, int x, int y)
{
	int top = Max0(y);
	int bottom = y + height < frame.Height ? y + height : frame.Height;
	int left = Max0(x);
	int right = x + width < frame.Width ? x + width : frame.Width;
	int entries = palette.Length / 3;

	for (var row = top; row < bottom; row += 1)
	{
		int source = (row - y) * width - x;

		for (var column = left; column < right; column += 1)
		{
			int index = (int)indices[source + column];

			if (index == 0 || index >= entries)
				continue;

			int to = (row * frame.Width + column) * 4;

			frame.Data[to] = palette[index * 3];
			frame.Data[to + 1] = palette[index * 3 + 1];
			frame.Data[to + 2] = palette[index * 3 + 2];
			frame.Data[to + 3] = 255;
		}
	}
}

/// Draws text with the pixel font: '\n' starts a new line, characters without a glyph are drawn as '?'.
void DrawText(Image frame, string text, int x, int y, TextColor textColor)
{
	var color = TextColors[(int)textColor];
	int cursorX = x;
	int cursorY = y;
	int offset = 0;

	while (offset < text.Length)
	{
		var point = DecodeUtf8(text, offset);

		offset += point.Length;

		if (point.Value == 10)
		{
			cursorX = x;
			cursorY += LineHeight;

			continue;
		}

		if (point.Value != 32)
		{
			var glyph = DrawableCharacters.ContainsKey(point.Value) ? GlyphOf(point.Value) : GlyphOf(63);

			for (var row = 0; row < 9; row += 1)
			{
				for (var column = 0; column < 5; column += 1)
				{
					if (glyph[row * 5 + column] != 0)
						Blend(frame, cursorX + column, cursorY + row, (int)color.R, (int)color.G, (int)color.B, 255);
				}
			}
		}

		cursorX += CellWidth;
	}
}

/// The number of characters (code points) of a text; the pixel width is this times CellWidth.
int TextLength(string text)
{
	return CharCount(text);
}

/// The first characters (code points) of a text.
string TextPrefix(string text, int characters)
{
	int offset = 0;
	int count = 0;

	while (offset < text.Length && count < characters)
	{
		offset += DecodeUtf8(text, offset).Length;
		count += 1;
	}

	return text.Substring(0, offset);
}

/// The text without its first characters (code points).
string TextSuffix(string text, int skip)
{
	return text.Substring(TextPrefix(text, skip).Length);
}

int MeasureWidth(string text)
{
	int widest = 0;

	foreach (var line in text.Split("\n"))
		widest = TextLength(line.ToString()) > widest ? TextLength(line.ToString()) : widest;

	return widest * CellWidth;
}

/// Word wraps text to the given pixel width (C#: TextRenderer.Wrap).
List<string> Wrap(string text, int maxWidth)
{
	int maxChars = maxWidth / CellWidth < 1 ? 1 : maxWidth / CellWidth;
	var lines = List<string>.Create();

	foreach (var paragraph in text.Split("\n"))
	{
		string current = "";

		foreach (var word in paragraph.Split(" "))
		{
			if (current.Length == 0)
				current = word.ToString();
			else if (TextLength(current) + 1 + TextLength(word.ToString()) <= maxChars)
				current = current + " " + word;
			else
			{
				lines.Add(current);
				current = word.ToString();
			}
		}

		lines.Add(current);
	}

	return lines;
}
