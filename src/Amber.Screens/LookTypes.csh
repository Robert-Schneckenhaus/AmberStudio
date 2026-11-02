namespace Amber.Screens;

using System;
using Amber.Base;

/// One drawn element of a look: a colored rectangle or a sprite at a position. Sprite is null for a colored rectangle;
/// Front (colored rectangles only): above the sprites instead of below; Rank: the order among the elements of the same kind
/// (0 is the lowest).
struct LookElement
{
	string Sprite;
	LookColor Color;
	bool Front;
	int X;
	int Y;
	int Width;
	int Height;
	int Rank;

	bool IsSprite()
	{
		return Sprite != null;
	}

	bool Same(LookElement other)
	{
		return Sprite == other.Sprite && Color.Same(other.Color) && Front == other.Front && X == other.X && Y == other.Y && Width == other.Width
			&& Height == other.Height && Rank == other.Rank;
	}
}

struct SpriteSize
{
	int Width;
	int Height;
}

/// The sizes of the sprites a layout may use (C#: the function Func<string, (int Width, int Height)?> spriteSize). A sprite
/// without a size is unknown and left out, unless a default size is set.
struct SpriteSizes
{
	Dictionary<string, SpriteSize> _sizes;
	bool _hasDefault;
	SpriteSize _default;

	static SpriteSizes Create()
	{
		return SpriteSizes { _sizes = Dictionary<string, SpriteSize>.Create(), _hasDefault = false };
	}

	/// Every sprite has this size unless Set gives it another.
	static SpriteSizes WithDefault(int width, int height)
	{
		return SpriteSizes { _sizes = Dictionary<string, SpriteSize>.Create(), _hasDefault = true, _default = SpriteSize { Width = width, Height = height } };
	}

	void Set(string name, int width, int height)
	{
		_sizes.Set(name, SpriteSize { Width = width, Height = height });
	}

	Optional<SpriteSize> Get(string name)
	{
		if (name == null)
			return null;

		if (_sizes.TryGet(name) is SpriteSize size)
			return size;

		if (_hasDefault)
			return _default;

		return null;
	}
}
