// Developer tools that write pictures without a window: a whole Tiled map (--preview-map), a region of a tile sheet with
// the tile numbers (--contact) and characters of the character pack (--char-preview).

namespace Amber.Player.Tools;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Game;
using Amber.Player.Graphics;
using Amber.Player.Tiled;

Error<void> SavePicture(Image image, string outputPath)
{
	string directory = Path.GetDirectory(outputPath);

	if (directory.Length > 0 && !Directory.Exists(directory))
		Directory.Create(directory);

	return SavePng(outputPath, image);
}

/// Renders a complete Tiled map to a PNG (ground first, then objects sorted by their bottom edge, then over layers). Used
/// to check generated maps without opening the game. Blocked cells can be tinted. Tiles of tilesets which are not installed
/// are drawn as placeholders.
Error<void> CreateMapPreview(string mapPath, string outputPath, int scale, bool showCollision, bool showGrid)
{
	var map = try TiledLoader.Load(mapPath);
	var images = TileImages.Create(map);
	int width = map.Width * map.TileWidth;
	int height = map.Height * map.TileHeight;
	var canvas = Image.Create(width, height);

	canvas.FillRect(0, 0, width, height, Color.Of(40, 40, 50));

	foreach (var layer in map.Layers)
	{
		var role = RoleOf(layer);

		if (role == LayerRole.Ground || role == LayerRole.Decor)
			DrawPreviewLayer(canvas, map, images, layer, (int)role, 0, map.Height);
	}

	// objects sorted by row (bottom edge)
	for (var row = 0; row < map.Height; row += 1)
	{
		foreach (var layer in map.Layers)
		{
			if (RoleOf(layer) == LayerRole.Objects)
				DrawPreviewLayer(canvas, map, images, layer, (int)LayerRole.Objects, row, row + 1);
		}
	}

	foreach (var layer in map.Layers)
	{
		if (RoleOf(layer) == LayerRole.Over)
			DrawPreviewLayer(canvas, map, images, layer, (int)LayerRole.Over, 0, map.Height);
	}

	if (showCollision && map.FindLayer("collision") is TiledLayer collision)
	{
		for (var row = 0; row < map.Height; row += 1)
		{
			for (var column = 0; column < map.Width; column += 1)
			{
				if (GidOf(collision.Get(column, row)) == 0)
					continue;

				for (var y = 0; y < map.TileHeight; y += 1)
				{
					for (var x = 0; x < map.TileWidth; x += 1)
					{
						if ((x + y) % 2 == 0)
							canvas.Set(column * map.TileWidth + x, row * map.TileHeight + y, Color.Of(255, 40, 40));
					}
				}
			}
		}
	}

	foreach (var objectLayer in map.ObjectLayers)
	{
		foreach (var point in objectLayer.Objects)
			canvas.FillRect((int)point.X - 2, (int)point.Y - 2, 5, 5, Color.Of(255, 0, 255));
	}

	if (showGrid)
	{
		for (var column = 0; column < map.Width; column += 5)
			canvas.FillRect(column * map.TileWidth, 0, 1, height, Color.Of(255, 255, 255));

		for (var row = 0; row < map.Height; row += 5)
			canvas.FillRect(0, row * map.TileHeight, width, 1, Color.Of(255, 255, 255));
	}

	var output = ScalePicture(canvas, scale);

	for (var i = 3; i < output.Data.Length; i += 4)
		output.Data[i] = 255;

	try SavePicture(output, outputPath);
	Console.WriteLine("Map preview: " + outputPath);

	return;
}

/// Draws the rows [firstRow, endRow) of a layer; a tile stands on the bottom edge of its cell, pixels with little alpha
/// are left out.
void DrawPreviewLayer(Image canvas, TiledMap map, TileImages images, TiledLayer layer, int role, int firstRow, int endRow)
{
	for (var row = firstRow; row < endRow; row += 1)
	{
		for (var column = 0; column < map.Width; column += 1)
		{
			uint32 raw = layer.Get(column, row);

			if (GidOf(raw) == 0)
				continue;

			var tile = images.Get(raw, role);
			int originX = column * map.TileWidth;
			int originY = (row + 1) * map.TileHeight - tile.Height;

			for (var y = 0; y < tile.Height; y += 1)
			{
				for (var x = 0; x < tile.Width; x += 1)
				{
					int index = (y * tile.Width + x) * 4;

					if (tile.Data[index + 3] < 128)
						continue;

					canvas.Set(originX + x, originY + y, Color.Of((int)tile.Data[index], (int)tile.Data[index + 1], (int)tile.Data[index + 2]));
				}
			}
		}
	}
}

/// The picture enlarged by a whole factor (nearest neighbor, alpha kept).
Image ScalePicture(Image source, int scale)
{
	if (scale <= 1)
		return source;

	var result = Image.Create(source.Width * scale, source.Height * scale);

	for (var y = 0; y < result.Height; y += 1)
	{
		for (var x = 0; x < result.Width; x += 1)
		{
			int from = ((y / scale) * source.Width + x / scale) * 4;
			int to = (y * result.Width + x) * 4;

			result.Data[to] = source.Data[from];
			result.Data[to + 1] = source.Data[from + 1];
			result.Data[to + 2] = source.Data[from + 2];
			result.Data[to + 3] = source.Data[from + 3];
		}
	}

	return result;
}

/// Draws a region of a tile sheet enlarged with the tile index (row * columns + column) on every tile, to find tile IDs.
Error<void> CreateContactSheet(string sheetPath, int tileWidth, int tileHeight, string outputPath, int startColumn, int startRow, int columns, int rows, int scale)
{
	var sheet = try LoadPng(sheetPath);
	int sheetColumns = sheet.Width / tileWidth;
	int cellWidth = tileWidth * scale;
	int cellHeight = tileHeight * scale;
	int width = columns * cellWidth;
	int height = rows * cellHeight;
	var canvas = Image.Create(width, height);

	canvas.FillRect(0, 0, width, height, Color.Of(70, 70, 90));

	for (var row = 0; row < rows; row += 1)
	{
		for (var column = 0; column < columns; column += 1)
		{
			int tileColumn = startColumn + column;
			int tileRow = startRow + row;

			if (tileColumn >= sheetColumns || (tileRow + 1) * tileHeight > sheet.Height)
				continue;

			bool checker = (column + row) % 2 == 0;

			canvas.FillRect(column * cellWidth, row * cellHeight, cellWidth, cellHeight, checker ? Color.Of(90, 90, 110) : Color.Of(110, 110, 130));

			for (var y = 0; y < tileHeight; y += 1)
			{
				for (var x = 0; x < tileWidth; x += 1)
				{
					int source = ((tileRow * tileHeight + y) * sheet.Width + tileColumn * tileWidth + x) * 4;

					if (sheet.Data[source + 3] < 128)
						continue;

					var color = Color.Of((int)sheet.Data[source], (int)sheet.Data[source + 1], (int)sheet.Data[source + 2]);

					canvas.FillRect(column * cellWidth + x * scale, row * cellHeight + y * scale, scale, scale, color);
				}
			}

			// grid line
			canvas.FillRect(column * cellWidth, row * cellHeight, cellWidth, 1, Color.Of(255, 0, 255));
			canvas.FillRect(column * cellWidth, row * cellHeight, 1, cellHeight, Color.Of(255, 0, 255));

			DrawSheetNumber(canvas, column * cellWidth + 3, row * cellHeight + 3, "" + (tileRow * sheetColumns + tileColumn), 2);
		}
	}

	try SavePicture(canvas, outputPath);
	Console.WriteLine("Contact sheet: " + outputPath + " (" + sheetColumns + " columns in the sheet)");

	return;
}

/// A number in the pixel font, yellow with a black outline.
void DrawSheetNumber(Image canvas, int x, int y, string text, int scale)
{
	int cursor = x;

	for (var i = 0; i < text.Length; i += 1)
	{
		var glyph = GlyphOf((int)text[i]);

		for (var outline = 0; outline < 2; outline += 1)
		{
			for (var row = 0; row < CellHeight; row += 1)
			{
				for (var column = 0; column < 5; column += 1)
				{
					if (glyph[row * 5 + column] == 0)
						continue;

					int px = cursor + column * scale;
					int py = y + row * scale;

					if (outline == 0)
						canvas.FillRect(px - 1, py - 1, scale + 2, scale + 2, Color.Of(0, 0, 0));
					else
						canvas.FillRect(px, py, scale, scale, Color.Of(255, 255, 80));
				}
			}
		}

		cursor += CellWidth * scale;
	}
}

const int PreviewScale = 3;
const int PreviewCropX = 12;
const int PreviewCropY = 6;
const int PreviewCropWidth = 40;
const int PreviewCropHeight = 52;
const int CharacterSheetColumns = 8;

/// Renders characters (a comma separated list of layers each) as a PNG: the four standing directions and the walk cycle
/// facing down. Used to choose looks without starting the game.
Error<void> CreateCharacterPreview(string outputPath, List<string> looks)
{
	string pack = CharacterPackDirectory();

	if (pack == null)
		return error("The character pack is not installed under assets/.", (int)ErrorKind.Io);

	int cells = 10;
	int cellWidth = PreviewCropWidth * PreviewScale;
	int cellHeight = PreviewCropHeight * PreviewScale;
	int width = cells * cellWidth;
	int height = looks.Count() * cellHeight;
	var output = Image.Create(width, height);
	var frames = new int[] { 0, 8, 16, 24, 32, 33, 34, 35, 38, 39 };

	output.FillRect(0, 0, width, height, Color.Of(60, 70, 50));

	for (var row = 0; row < looks.Count(); row += 1)
	{
		var layers = List<string>.Create();

		foreach (var part in looks.Get(row).Split(","))
		{
			string trimmed = part.Trim().ToString();

			if (trimmed.Length > 0)
				layers.Add(trimmed);
		}

		var sheet = try ComposeCharacter(pack, ArrayOf(layers));

		for (var cell = 0; cell < cells; cell += 1)
		{
			int index = frames[cell];
			var frame = sheet.Slice(index % CharacterSheetColumns * CharacterFrameSize + PreviewCropX, index / CharacterSheetColumns * CharacterFrameSize + PreviewCropY, PreviewCropWidth, PreviewCropHeight);

			for (var y = 0; y < PreviewCropHeight * PreviewScale; y += 1)
			{
				for (var x = 0; x < PreviewCropWidth * PreviewScale; x += 1)
				{
					int source = ((y / PreviewScale) * PreviewCropWidth + x / PreviewScale) * 4;

					if (frame.Data[source + 3] == 0)
						continue;

					output.Set(cell * cellWidth + x, row * cellHeight + y, Color.Of((int)frame.Data[source], (int)frame.Data[source + 1], (int)frame.Data[source + 2]));
				}
			}
		}
	}

	for (var i = 3; i < output.Data.Length; i += 4)
		output.Data[i] = 255;

	try SavePicture(output, outputPath);
	Console.WriteLine("Character preview: " + outputPath);

	return;
}
