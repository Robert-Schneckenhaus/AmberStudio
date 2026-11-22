// The 3D view (3D design, "Darstellung"): a raycaster that draws a map from the inside into a buffer of palette indices.
// Everything is fixed point (16.16) with tables for sine and cosine, so that the same code can run on a 68000 without an
// FPU later. The textures have the formats of Ambermoon: walls 128x80 (one wall fills a cell's width), floor and ceiling
// 64x64 per cell, billboards any height with a width in multiples of 16. Other sizes work too, they are only stretched.
// Light comes from shade tables of the palette: each level maps every art entry to a darker entry of the same palette.

namespace Amber.Player.Graphics;

using System;
using Amber.Base;
using Amber.Graphics;

/// One in fixed point.
const int Fixed = 65536;

/// Steps of a full turn (angle 0 looks north, the angle grows clockwise).
const int AngleSteps = 1024;

/// Shade levels: 0 is the full color, ShadeLevels - 1 nearly black.
const int ShadeLevels = 16;

/// The height of a wall in cells: 80 / 128 like the wall textures of Ambermoon. The eye is in the middle of it.
const int WallHeightFixed = 40960;

/// Half the width of the view plane at distance 1 (0.66: a field of view of about 67 degrees).
const int PlaneFixed = 43254;

/// The size of a texel of the billboards of the map in cells (1/128: the texels of a wall).
const int TexelFixed = 512;

/// sin(angle) * 65536 for the AngleSteps angles.
int[] SineTable = MakeSineTable();

int[] MakeSineTable()
{
	var table = new int[AngleSteps];

	for (var i = 0; i < AngleSteps; i += 1)
		table[i] = (int)Math.Round(Math.Sin((double)i * 2.0 * Math.PI / (double)AngleSteps) * (double)Fixed);

	return table;
}

int SinOf(int angle)
{
	return SineTable[angle & (AngleSteps - 1)];
}

int CosOf(int angle)
{
	return SineTable[(angle + AngleSteps / 4) & (AngleSteps - 1)];
}

/// x * y in fixed point.
int FixMul(int x, int y)
{
	return (int)(((int64)x * (int64)y) >> 16);
}

/// x / y in fixed point.
int FixDiv(int x, int y)
{
	return (int)(((int64)x << 16) / (int64)y);
}

/// A texture: palette indices, row by row (index 0 is transparent, only billboards use it).
struct RayTexture
{
	uint8[] Pixels;
	int Width;
	int Height;
}

/// A billboard: an upright picture that always faces the viewer, standing on the floor at a point of the map.
struct Billboard
{
	int X;
	int Y;
	int Texture;
	/// The size of a texel in cells (fixed point).
	int Texel;
	/// Filled while drawing: the distance in front of the viewer.
	int Depth;
}

/// What the raycaster draws: per cell the texture of the wall, the floor and the ceiling (an index into Textures, -1 for
/// none), the billboards, the shade tables and the colors without a texture.
struct RayScene
{
	int Width;
	int Height;
	int[] Walls;
	int[] Floors;
	int[] Ceilings;
	List<RayTexture> Textures;
	List<Billboard> Billboards;
	/// ShadeLevels tables of 256 entries.
	uint8[] Shades;
	/// The base brightness 0..15 and how fast it falls off with the distance (levels per cell, fixed point).
	int Light;
	int Falloff;
	bool FlatFloor;
	bool FlatCeiling;
	bool Sky;
	uint8 FloorColor;
	uint8 CeilingColor;
	/// Beyond the map, missing textures.
	uint8 Background;
	/// The sky by row of the upper half (Sky).
	uint8[] SkyRows;
}

/// Where the viewer stands: the position in cells (fixed point) and the angle.
struct RayCamera
{
	int X;
	int Y;
	int Angle;
}

/// The shade tables of a palette: for every level the darker art entry nearest to the darkened color of each entry. The
/// transparent entry and the user interface entries stay as they are.
uint8[] MakeShadeTables(Palette palette)
{
	var tables = new uint8[ShadeLevels * 256];
	int first = palette.Start(PaletteRange.Art);
	int end = palette.End(PaletteRange.Art);

	for (var level = 0; level < ShadeLevels; level += 1)
	{
		int factor = ShadeLevels - level;

		for (var index = 0; index < 256; index += 1)
		{
			if (index < first || index >= end)
			{
				tables[level * 256 + index] = (uint8)index;

				continue;
			}

			if (level == 0)
			{
				tables[index] = (uint8)index;

				continue;
			}

			int red = (int)palette.Rgb[index * 3] * factor / ShadeLevels;
			int green = (int)palette.Rgb[index * 3 + 1] * factor / ShadeLevels;
			int blue = (int)palette.Rgb[index * 3 + 2] * factor / ShadeLevels;

			tables[level * 256 + index] = (uint8)NearestEntry(palette, red, green, blue);
		}
	}

	return tables;
}

/// The art entry of the palette nearest to a color.
int NearestEntry(Palette palette, int red, int green, int blue)
{
	int best = palette.Start(PaletteRange.Art);
	int bestDistance = 0x7FFFFFFF;

	for (var i = palette.Start(PaletteRange.Art); i < palette.End(PaletteRange.Art); i += 1)
	{
		int dr = (int)palette.Rgb[i * 3] - red;
		int dg = (int)palette.Rgb[i * 3 + 1] - green;
		int db = (int)palette.Rgb[i * 3 + 2] - blue;
		int distance = dr * dr * 3 + dg * dg * 4 + db * db * 2;

		if (distance < bestDistance)
		{
			bestDistance = distance;
			best = i;
		}
	}

	return best;
}

/// The shade level at a distance (fixed point cells).
int ShadeAt(RayScene scene, int distance)
{
	int level = 15 - scene.Light + FixMul(distance, scene.Falloff) / Fixed;

	return level < 0 ? 0 : level >= ShadeLevels ? ShadeLevels - 1 : level;
}

/// The focal length in pixels: the distance at which a cell is as wide on screen as the view is half wide over PlaneFixed.
int FocalOf(int width)
{
	return (int)((int64)width * (int64)Fixed / 2 / (int64)PlaneFixed);
}

/// Draws the scene from the camera into the buffer (width x height palette indices). Returns the depth of every column
/// (the distance of the wall, fixed point), which tells what a click hits.
int[] RenderScene(RayScene scene, RayCamera camera, uint8[] buffer, int width, int height)
{
	int focal = FocalOf(width);
	int horizon = height / 2;
	int forwardX = SinOf(camera.Angle);
	int forwardY = -CosOf(camera.Angle);
	int planeX = FixMul(CosOf(camera.Angle), PlaneFixed);
	int planeY = FixMul(SinOf(camera.Angle), PlaneFixed);
	var depths = new int[width];

	DrawFloorAndCeiling(scene, camera, buffer, width, height, focal, forwardX, forwardY, planeX, planeY);

	for (var column = 0; column < width; column += 1)
	{
		// -1 at the left edge, +1 at the right edge (at the middle of the pixel)
		int cameraX = (int)((int64)(2 * column + 1 - width) * (int64)Fixed / (int64)width);
		int rayX = forwardX + FixMul(planeX, cameraX);
		int rayY = forwardY + FixMul(planeY, cameraX);

		depths[column] = DrawWallColumn(scene, camera, buffer, width, height, focal, horizon, column, rayX, rayY);
	}

	DrawBillboards(scene, camera, buffer, width, height, focal, horizon, forwardX, forwardY, depths);

	return depths;
}

/// The distance to cross one cell along an axis of a ray (fixed point), large for an axis the ray does not move along.
int DeltaOf(int ray)
{
	if (ray == 0)
		return 0x3FFFFFFF;

	int64 delta = ((int64)Fixed * (int64)Fixed) / (int64)(ray < 0 ? -ray : ray);

	return delta > (int64)0x3FFFFFFF ? 0x3FFFFFFF : (int)delta;
}

int DrawWallColumn(RayScene scene, RayCamera camera, uint8[] buffer, int width, int height, int focal, int horizon, int column, int rayX, int rayY)
{
	int cellX = camera.X >> 16;
	int cellY = camera.Y >> 16;
	int deltaX = DeltaOf(rayX);
	int deltaY = DeltaOf(rayY);
	int stepX = rayX < 0 ? -1 : 1;
	int stepY = rayY < 0 ? -1 : 1;
	int64 sideX = rayX < 0 ? ((int64)(camera.X - cellX * Fixed) * (int64)deltaX) >> 16 : ((int64)((cellX + 1) * Fixed - camera.X) * (int64)deltaX) >> 16;
	int64 sideY = rayY < 0 ? ((int64)(camera.Y - cellY * Fixed) * (int64)deltaY) >> 16 : ((int64)((cellY + 1) * Fixed - camera.Y) * (int64)deltaY) >> 16;
	int side = 0;
	int texture = -1;
	bool hit = false;

	for (var steps = 0; steps < 96 && !hit; steps += 1)
	{
		if (sideX < sideY)
		{
			sideX += (int64)deltaX;
			cellX += stepX;
			side = 0;
		}
		else
		{
			sideY += (int64)deltaY;
			cellY += stepY;
			side = 1;
		}

		if (cellX < 0 || cellY < 0 || cellX >= scene.Width || cellY >= scene.Height)
			return 0x3FFFFFFF;

		texture = scene.Walls[cellY * scene.Width + cellX];
		hit = texture >= 0;
	}

	if (!hit)
		return 0x3FFFFFFF;

	int64 distance64 = side == 0 ? sideX - (int64)deltaX : sideY - (int64)deltaY;
	int distance = distance64 < (int64)(Fixed / 64) ? Fixed / 64 : distance64 > (int64)0x3FFFFFFF ? 0x3FFFFFFF : (int)distance64;
	// where the ray hits the wall, 0..1 across it
	int along = side == 0 ? camera.Y + FixMul(distance, rayY) : camera.X + FixMul(distance, rayX);
	int fraction = along & (Fixed - 1);

	// so that a texture reads from left to right on every side of a wall
	if ((side == 0 && rayX < 0) || (side == 1 && rayY > 0))
		fraction = Fixed - 1 - fraction;

	int lineHeight = (int)((int64)WallHeightFixed * (int64)focal / (int64)distance);
	int top = horizon - lineHeight / 2;
	int first = top < 0 ? 0 : top;
	int last = top + lineHeight > height ? height : top + lineHeight;
	int level = ShadeAt(scene, distance) + side;
	int shade = (level >= ShadeLevels ? ShadeLevels - 1 : level) * 256;

	if (texture >= scene.Textures.Count())
	{
		for (var y = first; y < last; y += 1)
			buffer[y * width + column] = scene.Background;

		return distance;
	}

	var image = scene.Textures.Get(texture);
	int textureX = (int)(((int64)fraction * (int64)image.Width) >> 16);
	int step = lineHeight <= 0 ? 0 : (int)(((int64)image.Height << 16) / (int64)lineHeight);
	int position = (first - top) * step;

	for (var y = first; y < last; y += 1)
	{
		int textureY = position >> 16;

		if (textureY >= image.Height)
			textureY = image.Height - 1;

		uint8 index = image.Pixels[textureY * image.Width + textureX];

		buffer[y * width + column] = index == 0 ? scene.Background : scene.Shades[shade + (int)index];
		position += step;
	}

	return distance;
}

/// Floor and ceiling row by row: every row of the lower half is at a fixed distance from the eye (the ceiling mirrors it).
void DrawFloorAndCeiling(RayScene scene, RayCamera camera, uint8[] buffer, int width, int height, int focal, int forwardX, int forwardY, int planeX, int planeY)
{
	int horizon = height / 2;
	int leftX = forwardX - planeX;
	int leftY = forwardY - planeY;
	int rightX = forwardX + planeX;
	int rightY = forwardY + planeY;
	int eye = WallHeightFixed / 2;

	for (var y = horizon; y < height; y += 1)
	{
		// the distance of the floor seen in this row: eye height * focal / rows below the horizon (at the pixel's middle)
		int distance = (int)((int64)eye * (int64)focal * 2 / (int64)(2 * (y - horizon) + 1));
		int stepX = (int)((int64)distance * (int64)(rightX - leftX) / (int64)Fixed / (int64)width);
		int stepY = (int)((int64)distance * (int64)(rightY - leftY) / (int64)Fixed / (int64)width);
		int floorX = camera.X + FixMul(distance, leftX) + stepX / 2;
		int floorY = camera.Y + FixMul(distance, leftY) + stepY / 2;
		int shade = ShadeAt(scene, distance) * 256;
		int ceilingRow = height - 1 - y;
		uint8 flatFloor = scene.Shades[shade + (int)scene.FloorColor];
		uint8 flatCeiling = scene.Shades[shade + (int)scene.CeilingColor];

		for (var x = 0; x < width; x += 1)
		{
			int cellX = floorX >> 16;
			int cellY = floorY >> 16;
			bool inside = floorX >= 0 && floorY >= 0 && cellX < scene.Width && cellY < scene.Height;
			int cell = inside ? cellY * scene.Width + cellX : 0;

			buffer[y * width + x] = !inside ? scene.Background : scene.FlatFloor ? flatFloor : Texel(scene, scene.Floors[cell], floorX, floorY, shade, flatFloor);

			if (scene.Sky)
				buffer[ceilingRow * width + x] = scene.SkyRows[ceilingRow];
			else
				buffer[ceilingRow * width + x] = !inside ? scene.Background : scene.FlatCeiling ? flatCeiling : Texel(scene, scene.Ceilings[cell], floorX, floorY, shade, flatCeiling);

			floorX += stepX;
			floorY += stepY;
		}
	}
}

/// The shaded texel of a floor or ceiling texture at a point of the map (the flat color without a texture).
uint8 Texel(RayScene scene, int texture, int x, int y, int shade, uint8 flat)
{
	if (texture < 0 || texture >= scene.Textures.Count())
		return flat;

	var image = scene.Textures.Get(texture);
	int u = (int)(((int64)(x & (Fixed - 1)) * (int64)image.Width) >> 16);
	int v = (int)(((int64)(y & (Fixed - 1)) * (int64)image.Height) >> 16);
	uint8 index = image.Pixels[v * image.Width + u];

	return index == 0 ? flat : scene.Shades[shade + (int)index];
}

int CompareBillboards(Billboard a, Billboard b)
{
	// far ones first
	return CompareInt(b.Depth, a.Depth);
}

void DrawBillboards(RayScene scene, RayCamera camera, uint8[] buffer, int width, int height, int focal, int horizon, int forwardX, int forwardY, int[] depths)
{
	var visible = List<Billboard>.Create();
	int rightX = -forwardY;
	int rightY = forwardX;

	foreach (var billboard in scene.Billboards)
	{
		int relativeX = billboard.X - camera.X;
		int relativeY = billboard.Y - camera.Y;
		var copy = billboard;

		copy.Depth = FixMul(relativeX, forwardX) + FixMul(relativeY, forwardY);

		if (copy.Depth > Fixed / 8 && billboard.Texture >= 0 && billboard.Texture < scene.Textures.Count())
			visible.Add(copy);
	}

	var sorted = SortArray(ArrayOf(visible), CompareBillboards);

	foreach (var billboard in sorted)
	{
		var image = scene.Textures.Get(billboard.Texture);
		int lateral = FixMul(billboard.X - camera.X, rightX) + FixMul(billboard.Y - camera.Y, rightY);
		int depth = billboard.Depth;
		int centerX = width / 2 + (int)((int64)lateral * (int64)focal / (int64)depth);
		int pixelsWide = (int)((int64)image.Width * (int64)billboard.Texel * (int64)focal / (int64)depth);
		int pixelsHigh = (int)((int64)image.Height * (int64)billboard.Texel * (int64)focal / (int64)depth);
		int bottom = horizon + (int)((int64)(WallHeightFixed / 2) * (int64)focal / (int64)depth);
		int top = bottom - pixelsHigh;
		int left = centerX - pixelsWide / 2;

		if (pixelsWide <= 0 || pixelsHigh <= 0 || left >= width || left + pixelsWide <= 0)
			continue;

		int shade = ShadeAt(scene, depth) * 256;
		int firstColumn = left < 0 ? 0 : left;
		int lastColumn = left + pixelsWide > width ? width : left + pixelsWide;
		int firstRow = top < 0 ? 0 : top;
		int lastRow = bottom > height ? height : bottom;

		for (var x = firstColumn; x < lastColumn; x += 1)
		{
			if (depth >= depths[x])
				continue;

			int u = (x - left) * image.Width / pixelsWide;

			for (var y = firstRow; y < lastRow; y += 1)
			{
				int v = (y - top) * image.Height / pixelsHigh;
				uint8 index = image.Pixels[v * image.Width + u];

				if (index != 0)
					buffer[y * width + x] = scene.Shades[shade + (int)index];
			}
		}
	}
}
