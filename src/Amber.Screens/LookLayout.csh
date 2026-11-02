/// Turns a look into the elements to draw for a rectangle: the sizes of the sprites decide how many pieces of a border or a
/// tile fill are needed. Pure geometry, no drawing.
namespace Amber.Screens.LookLayout;

using System;
using Amber.Base;

/// The thickness of the border of a look on each side (left, top, right, bottom), from the sizes of its sprites; 0 without a
/// border.
LookInset BorderThickness(LookPart[] parts, SpriteSizes sizes)
{
	foreach (var part in parts)
	{
		if (part.Kind != LookPartKind.Border)
			continue;

		if (part.Border is BorderSprites border)
		{
			return LookInset.Of(
				Math.Max(W(sizes, border.Left), Math.Max(W(sizes, border.TopLeft), W(sizes, border.BottomLeft))),
				Math.Max(H(sizes, border.Top), Math.Max(H(sizes, border.TopLeft), H(sizes, border.TopRight))),
				Math.Max(W(sizes, border.Right), Math.Max(W(sizes, border.TopRight), W(sizes, border.BottomRight))),
				Math.Max(H(sizes, border.Bottom), Math.Max(H(sizes, border.BottomLeft), H(sizes, border.BottomRight))));
		}

		return LookInset.None();
	}

	return LookInset.None();
}

int W(SpriteSizes sizes, string name)
{
	if (sizes.Get(name) is SpriteSize size)
		return size.Width;

	return 0;
}

int H(SpriteSizes sizes, string name)
{
	if (sizes.Get(name) is SpriteSize size)
		return size.Height;

	return 0;
}

/// The elements of the look in the given state for the rectangle. A sprite whose size is unknown is left out.
List<LookElement> Place(LookDefinition look, string state, int x, int y, int width, int height, SpriteSizes sizes)
{
	var parts = look.PartsFor(state);
	var thickness = BorderThickness(look.Parts.Length > 0 ? look.Parts : parts, sizes);
	var elements = List<LookElement>.Create();
	int rectRank = 0;
	int spriteRank = 0;

	foreach (var part in parts)
	{
		var inset = part.Inset.FromBorder ? thickness : part.Inset;
		int left = x + inset.Left;
		int top = y + inset.Top;
		int areaWidth = width - inset.Left - inset.Right;
		int areaHeight = height - inset.Top - inset.Bottom;

		if (areaWidth <= 0 || areaHeight <= 0)
			continue;

		switch (part.Kind)
		{
			case LookPartKind.Rect:
				elements.Add(Rect(part, left, top, areaWidth, areaHeight, rectRank));
				rectRank += 1;
				break;
			case LookPartKind.Frame:
			{
				int line = Math.Min(part.Width, Math.Min(areaWidth, areaHeight));

				elements.Add(Rect(part, left, top, areaWidth, line, rectRank));
				elements.Add(Rect(part, left, top + areaHeight - line, areaWidth, line, rectRank));
				elements.Add(Rect(part, left, top + line, line, areaHeight - 2 * line, rectRank));
				elements.Add(Rect(part, left + areaWidth - line, top + line, line, areaHeight - 2 * line, rectRank));
				rectRank += 1;
				break;
			}
			case LookPartKind.Tile:
			{
				if (sizes.Get(part.Sprite) is SpriteSize tile)
				{
					foreach (var tileY in Steps(top, areaHeight, tile.Height))
					{
						foreach (var tileX in Steps(left, areaWidth, tile.Width))
							elements.Add(Sprite(part.Sprite, tileX, tileY, tile.Width, tile.Height, spriteRank));
					}

					spriteRank += 1;
				}

				break;
			}
			case LookPartKind.Border:
			{
				if (part.Border is BorderSprites border)
				{
					PlaceBorder(elements, border, left, top, areaWidth, areaHeight, sizes, spriteRank);
					spriteRank += 1;
				}

				break;
			}
			default:
			{
				if (sizes.Get(part.Sprite) is SpriteSize image)
				{
					int imageWidth = part.Stretch ? areaWidth : image.Width;
					int imageHeight = part.Stretch ? areaHeight : image.Height;
					int imageX = left + Align(part.Align, true, areaWidth, imageWidth) + part.OffsetX;
					int imageY = top + Align(part.Align, false, areaHeight, imageHeight) + part.OffsetY;

					elements.Add(Sprite(part.Sprite, imageX, imageY, imageWidth, imageHeight, spriteRank));
					spriteRank += 1;
				}

				break;
			}
		}
	}

	return elements;
}

LookElement Rect(LookPart part, int x, int y, int width, int height, int rank)
{
	return LookElement { Sprite = null, Color = part.Color, Front = part.Front, X = x, Y = y, Width = width, Height = height, Rank = rank };
}

LookElement Sprite(string name, int x, int y, int width, int height, int rank)
{
	return LookElement { Sprite = name, Color = new LookColor(), Front = false, X = x, Y = y, Width = width, Height = height, Rank = rank };
}

SpriteSize SizeOrZero(SpriteSizes sizes, string name)
{
	if (sizes.Get(name) is SpriteSize size)
		return size;

	return SpriteSize { Width = 0, Height = 0 };
}

void AddSprite(List<LookElement> elements, SpriteSizes sizes, string name, int x, int y, int rank)
{
	if (sizes.Get(name) is SpriteSize size)
		elements.Add(Sprite(name, x, y, size.Width, size.Height, rank));
}

void PlaceBorder(List<LookElement> elements, BorderSprites border, int x, int y, int width, int height, SpriteSizes sizes, int rank)
{
	var topLeft = SizeOrZero(sizes, border.TopLeft);
	var topRight = SizeOrZero(sizes, border.TopRight);
	var bottomLeft = SizeOrZero(sizes, border.BottomLeft);
	var bottomRight = SizeOrZero(sizes, border.BottomRight);

	// the edges first, the corners on top of the ends of the edges
	if (sizes.Get(border.Top) is SpriteSize top)
	{
		foreach (var tileX in Steps(x + topLeft.Width, width - topLeft.Width - topRight.Width, top.Width))
			AddSprite(elements, sizes, border.Top, tileX, y, rank);
	}

	if (sizes.Get(border.Bottom) is SpriteSize bottom)
	{
		foreach (var tileX in Steps(x + bottomLeft.Width, width - bottomLeft.Width - bottomRight.Width, bottom.Width))
			AddSprite(elements, sizes, border.Bottom, tileX, y + height - bottom.Height, rank);
	}

	if (sizes.Get(border.Left) is SpriteSize left)
	{
		foreach (var tileY in Steps(y + topLeft.Height, height - topLeft.Height - bottomLeft.Height, left.Height))
			AddSprite(elements, sizes, border.Left, x, tileY, rank);
	}

	if (sizes.Get(border.Right) is SpriteSize right)
	{
		foreach (var tileY in Steps(y + topRight.Height, height - topRight.Height - bottomRight.Height, right.Height))
			AddSprite(elements, sizes, border.Right, x + width - right.Width, tileY, rank);
	}

	AddSprite(elements, sizes, border.TopLeft, x, y, rank);
	AddSprite(elements, sizes, border.TopRight, x + width - topRight.Width, y, rank);
	AddSprite(elements, sizes, border.BottomLeft, x, y + height - bottomLeft.Height, rank);
	AddSprite(elements, sizes, border.BottomRight, x + width - bottomRight.Width, y + height - bottomRight.Height, rank);
}

/// Start positions of pieces of the given length which cover a stretch: from the start on, the last piece ends at the end of
/// the stretch (it overlaps the one before it when the stretch is not a multiple of the length).
int[] Steps(int start, int length, int piece)
{
	if (length <= 0 || piece <= 0)
		return new int[0];

	int count = (length + piece - 1) / piece;
	var result = new int[count];

	for (var i = 0; i < count; i += 1)
		result[i] = i == count - 1 ? start + length - piece : start + i * piece;

	return result;
}

int Align(string align, bool horizontal, int area, int size)
{
	bool low = horizontal ? align.Contains("left") : align.Contains("top");
	bool high = horizontal ? align.Contains("right") : align.Contains("bottom");

	return low ? 0 : (high ? area - size : (area - size) / 2);
}
