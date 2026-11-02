// Between the engine and System.Ui: both have an Image, a Color and a Key, so this file uses the engine's names and
// writes the ones of System.Ui in full. The engine's pictures are RGBA bytes, the ones of System.Ui 0xAARRGGBB words.

namespace Amber.Studio;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Game;
using Amber.Player.Graphics;
using Amber.Player.Platform;
using Amber.Player.Tiled;

/// The picture of the engine as an image of System.Ui (transparent pixels stay transparent).
System.Image.Image ToUiImage(Image source)
{
	var image = System.Image.Image.Create(Math.Max(1, source.Width), Math.Max(1, source.Height));

	for (var i = 0; i < source.Width * source.Height; i += 1)
	{
		int p = i * 4;

		image.Pixels[i] = ((uint32)source.Data[p + 3] << 24) | ((uint32)source.Data[p] << 16) | ((uint32)source.Data[p + 1] << 8) | (uint32)source.Data[p + 2];
	}

	return image;
}

/// The whole map (all tile layers but the hidden ones; the collision layer on top if it is not hidden) in its own size.
System.Image.Image RenderMapImage(TiledMap map, TileImages images, Dictionary<int, bool> hidden, int collisionLayer)
{
	int width = map.Width * map.TileWidth;
	int height = map.Height * map.TileHeight;
	var list = DrawList.Create();

	DrawTileMap(list, map, images, hidden, collisionLayer, 0, 0, width, height, 0);

	var frame = Image.Create(width, height);

	frame.FillRect(0, 0, width, height, Color.Of(24, 24, 28));
	list.Render(frame);

	return ToUiImage(frame);
}

/// The tiles of a tileset side by side as in its picture (missing pictures are placeholders), one cell per tile.
System.Image.Image RenderTileset(TiledTilesetReference reference, TileImages images)
{
	var tileset = reference.Tileset;
	int columns = Math.Max(1, tileset.Columns);
	int rows = (tileset.TileCount + columns - 1) / columns;
	int cellWidth = Math.Max(1, tileset.TileWidth);
	int cellHeight = Math.Max(1, tileset.TileHeight);
	var sheet = Image.Create(columns * cellWidth, Math.Max(1, rows) * cellHeight);

	for (var i = 0; i < tileset.TileCount; i += 1)
	{
		var tile = images.Get((uint32)(reference.FirstGid + i), 1);

		if (tile.Width > 0)
			CopyPixels(tile, sheet, i % columns * cellWidth, i / columns * cellHeight);
	}

	return ToUiImage(sheet);
}

/// Copies the picture into the other one at (x, y), clipped.
void CopyPixels(Image source, Image target, int x, int y)
{
	for (var row = 0; row < source.Height; row += 1)
	{
		int ty = y + row;

		if (ty < 0 || ty >= target.Height)
			continue;

		for (var column = 0; column < source.Width; column += 1)
		{
			int tx = x + column;

			if (tx < 0 || tx >= target.Width)
				continue;

			int from = (row * source.Width + column) * 4;
			int to = (ty * target.Width + tx) * 4;

			target.Data[to] = source.Data[from];
			target.Data[to + 1] = source.Data[from + 1];
			target.Data[to + 2] = source.Data[from + 2];
			target.Data[to + 3] = source.Data[from + 3];
		}
	}
}

/// One frame of the game in the size of the virtual screen.
System.Image.Image RenderGame(PrototypeGame game)
{
	var list = DrawList.Create();

	game.Draw(list);

	return ToUiImage(RenderList(list, VirtualScreenWidth, VirtualScreenHeight));
}

/// The key of the engine for a key of System.Ui (Key.Unknown for keys the game does not know).
Key EngineKey(System.Ui.Key key)
{
	int k = (int)key;

	if (k >= (int)System.Ui.Key.A && k <= (int)System.Ui.Key.Z)
		return (Key)(65 + k - (int)System.Ui.Key.A);

	if (k >= (int)System.Ui.Key.D0 && k <= (int)System.Ui.Key.D9)
		return (Key)(48 + k - (int)System.Ui.Key.D0);

	if (k >= (int)System.Ui.Key.F1 && k <= (int)System.Ui.Key.F12)
		return (Key)(290 + k - (int)System.Ui.Key.F1);

	if (k >= (int)System.Ui.Key.NumPad0 && k <= (int)System.Ui.Key.NumPad9)
		return (Key)(320 + k - (int)System.Ui.Key.NumPad0);

	switch (key)
	{
	case System.Ui.Key.Enter:
		return Key.Enter;
	case System.Ui.Key.Escape:
		return Key.Escape;
	case System.Ui.Key.Backspace:
		return Key.Backspace;
	case System.Ui.Key.Delete:
		return Key.Delete;
	case System.Ui.Key.Tab:
		return Key.Tab;
	case System.Ui.Key.Space:
		return Key.Space;
	case System.Ui.Key.Insert:
		return Key.Insert;
	case System.Ui.Key.Left:
		return Key.Left;
	case System.Ui.Key.Right:
		return Key.Right;
	case System.Ui.Key.Up:
		return Key.Up;
	case System.Ui.Key.Down:
		return Key.Down;
	case System.Ui.Key.Home:
		return Key.Home;
	case System.Ui.Key.End:
		return Key.End;
	case System.Ui.Key.PageUp:
		return Key.PageUp;
	case System.Ui.Key.PageDown:
		return Key.PageDown;
	case System.Ui.Key.Minus:
		return Key.Minus;
	case System.Ui.Key.Comma:
		return Key.Comma;
	case System.Ui.Key.Period:
		return Key.Period;
	case System.Ui.Key.Plus:
		return Key.Equal;
	default:
		return Key.Unknown;
	}
}
