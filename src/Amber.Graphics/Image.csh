namespace Amber.Graphics;

using System;
using Amber.Base;

/// A color with alpha (C#: Amber.Assets.Common.Color).
struct Color
{
	uint8 R;
	uint8 G;
	uint8 B;
	uint8 A;

	static Color Of(int r, int g, int b)
	{
		return Color { R = (uint8)r, G = (uint8)g, B = (uint8)b, A = 255 };
	}

	static Color OfAlpha(int r, int g, int b, int a)
	{
		return Color { R = (uint8)r, G = (uint8)g, B = (uint8)b, A = (uint8)a };
	}

	bool Same(Color other)
	{
		return R == other.R && G == other.G && B == other.B && A == other.A;
	}
}

/// An RGBA picture (4 bytes per pixel, rows from the top). Copies share the pixels.
struct Image
{
	int Width;
	int Height;
	uint8[] Data;

	static Image Create(int width, int height)
	{
		return Image { Width = width, Height = height, Data = new uint8[width * height * 4] };
	}

	static Image Empty()
	{
		return Create(0, 0);
	}

	bool IsEmpty()
	{
		return Width == 0 || Height == 0;
	}

	int Alpha(int x, int y)
	{
		return (int)Data[(y * Width + x) * 4 + 3];
	}

	void Set(int x, int y, Color color)
	{
		if (x < 0 || y < 0 || x >= Width || y >= Height)
			return;

		int index = (y * Width + x) * 4;

		Data[index] = color.R;
		Data[index + 1] = color.G;
		Data[index + 2] = color.B;
		Data[index + 3] = color.A;
	}

	void FillRect(int x, int y, int width, int height, Color color)
	{
		for (var row = y; row < y + height; row += 1)
		{
			for (var column = x; column < x + width; column += 1)
				Set(column, row, color);
		}
	}

	Image Clone()
	{
		var copy = Create(Width, Height);

		for (var i = 0; i < Data.Length; i += 1)
			copy.Data[i] = Data[i];

		return copy;
	}

	/// A part of the picture (outside pixels are transparent).
	Image Slice(int x, int y, int width, int height)
	{
		var result = Create(width, height);

		for (var row = 0; row < height; row += 1)
		{
			int sourceY = y + row;

			if (sourceY < 0 || sourceY >= Height)
				continue;

			for (var column = 0; column < width; column += 1)
			{
				int sourceX = x + column;

				if (sourceX < 0 || sourceX >= Width)
					continue;

				int from = (sourceY * Width + sourceX) * 4;
				int to = (row * width + column) * 4;

				result.Data[to] = Data[from];
				result.Data[to + 1] = Data[from + 1];
				result.Data[to + 2] = Data[from + 2];
				result.Data[to + 3] = Data[from + 3];
			}
		}

		return result;
	}

	/// Applies Tiled flip flags: horizontal, vertical, diagonal (diagonal first, then the flips).
	Image Transform(bool horizontal, bool vertical, bool diagonal)
	{
		if (!horizontal && !vertical && !diagonal)
			return this;

		int width = diagonal ? Height : Width;
		int height = diagonal ? Width : Height;
		var result = Create(width, height);

		for (var y = 0; y < height; y += 1)
		{
			for (var x = 0; x < width; x += 1)
			{
				int sx = diagonal ? y : x;
				int sy = diagonal ? x : y;

				if (horizontal)
				{
					if (diagonal)
						sy = Height - 1 - sy;
					else
						sx = Width - 1 - sx;
				}

				if (vertical)
				{
					if (diagonal)
						sx = Width - 1 - sx;
					else
						sy = Height - 1 - sy;
				}

				int from = (sy * Width + sx) * 4;
				int to = (y * width + x) * 4;

				result.Data[to] = Data[from];
				result.Data[to + 1] = Data[from + 1];
				result.Data[to + 2] = Data[from + 2];
				result.Data[to + 3] = Data[from + 3];
			}
		}

		return result;
	}
}

/// The bounding box of the visible pixels of a picture.
struct PixelBounds
{
	int X;
	int Y;
	int Width;
	int Height;
}

/// The box of the visible pixels, or no value if the picture is empty (C#: CharacterComposer.Bounds).
Optional<PixelBounds> VisibleBounds(Image image)
{
	int minX = 0x7FFFFFFF;
	int minY = 0x7FFFFFFF;
	int maxX = -1;
	int maxY = -1;

	for (var y = 0; y < image.Height; y += 1)
	{
		for (var x = 0; x < image.Width; x += 1)
		{
			if (image.Alpha(x, y) == 0)
				continue;

			minX = x < minX ? x : minX;
			minY = y < minY ? y : minY;
			maxX = x > maxX ? x : maxX;
			maxY = y > maxY ? y : maxY;
		}
	}

	if (maxX < 0)
		return null;

	return PixelBounds { X = minX, Y = minY, Width = maxX - minX + 1, Height = maxY - minY + 1 };
}
