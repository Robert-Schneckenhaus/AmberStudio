namespace Amber.Player.Graphics;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Tiled;

int Clamp255(int value)
{
	return value < 0 ? 0 : value > 255 ? 255 : value;
}

/// The pictures of the tileset images by path (every image is read once).
Dictionary<string, Image> TilesetSheets = Dictionary<string, Image>.Create();

/// The images which could not be read (reported once, placeholder tiles instead).
Dictionary<string, bool> BrokenSheets = Dictionary<string, bool>.Create();

/// A frame of an animated tile as a raw tile ID with its duration.
struct RawFrame
{
	uint32 Raw;
	int DurationMs;
}

/// Turns Tiled tile IDs (including flip flags) into pictures (C#: TileTextures). A tile whose tileset or image is not
/// installed gets a placeholder: a square of the map's tile size in a color of its ID. A handle.
struct TileImages
{
	TiledMap Map;
	Dictionary<uint32, Image> _cache;
	Dictionary<int64, Image> _placeholders;
	Dictionary<uint32, RawFrame[]> _animations;

	static TileImages Create(TiledMap map)
	{
		return TileImages
		{
			Map = map, _cache = Dictionary<uint32, Image>.Create(), _placeholders = Dictionary<int64, Image>.Create(), _animations = Dictionary<uint32, RawFrame[]>.Create()
		};
	}

	/// The picture of a tile; an empty picture for the empty tile. The role (0 ground, 1 decor, 2 objects, 3 over) only
	/// decides the look of a placeholder.
	Image Get(uint32 raw, int role)
	{
		uint32 gid = GidOf(raw);

		if (gid == 0)
			return Image.Empty();

		if (_cache.TryGet(raw) is Image cached)
			return cached;

		if (Installed(raw))
		{
			var image = Create(raw);

			_cache.Set(raw, image);

			return image;
		}

		int64 key = (int64)gid * 8 + (int64)role;

		if (_placeholders.TryGet(key) is Image placeholder)
			return placeholder;

		var created = Placeholder(gid, role);

		_placeholders.Set(key, created);

		return created;
	}

	/// True if the picture of the tile is installed.
	bool Installed(uint32 raw)
	{
		if (Map.FindTileset((int)GidOf(raw)) is TiledTilesetReference reference)
		{
			if (!reference.Tileset.Missing && reference.Tileset.ImagePath != null)
				return Sheet(reference.Tileset.ImagePath) is Image;
		}

		return false;
	}

	Image Create(uint32 raw)
	{
		uint32 gid = GidOf(raw);
		uint32 flip = FlipOf(raw);

		if (Map.FindTileset((int)gid) is TiledTilesetReference reference)
		{
			var tileset = reference.Tileset;

			if (!tileset.Missing && tileset.ImagePath != null && Sheet(tileset.ImagePath) is Image sheet)
			{
				int localId = (int)gid - reference.FirstGid;
				int columns = tileset.Columns > 0 ? tileset.Columns : 1;
				var tile = sheet.Slice(localId % columns * tileset.TileWidth, localId / columns * tileset.TileHeight, tileset.TileWidth, tileset.TileHeight);

				return tile.Transform((flip & FlipHorizontal) != 0, (flip & FlipVertical) != 0, (flip & FlipDiagonal) != 0);
			}
		}

		return Placeholder(gid, 0);
	}

	/// A placeholder in the color of its layer (ground green, decoration brown, objects dark green, canopy a checkerboard),
	/// a little lighter or darker by the tile ID so that neighboring tiles are told apart.
	Image Placeholder(uint32 gid, int role)
	{
		int width = Map.TileWidth;
		int height = Map.TileHeight;

		if (Map.FindTileset((int)gid) is TiledTilesetReference reference)
		{
			width = reference.Tileset.TileWidth;
			height = reference.Tileset.TileHeight;
		}

		var image = Image.Create(width, height);
		uint32 mixed = unchecked(gid * (uint32)2654435761);
		int shade = (int)(mixed >> 24) % 25 - 12;

		if (role == 1)
			image.FillRect(3, 3, width - 6, height - 6, Color.OfAlpha(Clamp255(140 + shade), Clamp255(118 + shade), Clamp255(78 + shade), 170));
		else if (role == 2)
		{
			var fill = Color.Of(Clamp255(52 + shade), Clamp255(92 + shade), Clamp255(52 + shade));

			image.FillRect(0, 0, width, height, fill);
			image.FillRect(0, height - 1, width, 1, Color.Of(30, 50, 30));
			image.FillRect(width - 1, 0, 1, height, Color.Of(30, 50, 30));
		}
		else if (role == 3)
		{
			// every other pixel: tiles are drawn opaque or not at all, so a checkerboard makes the canopy see-through
			var canopy = Color.Of(Clamp255(34 + shade), Clamp255(66 + shade), Clamp255(38 + shade));

			for (var y = 0; y < height; y += 1)
			{
				for (var x = (y % 2); x < width; x += 2)
					image.Set(x, y, canopy);
			}
		}
		else
			image.FillRect(0, 0, width, height, Color.Of(Clamp255(82 + shade), Clamp255(132 + shade), Clamp255(66 + shade)));

		return image;
	}

	/// The frames of an animated tile as raw IDs with durations, or no value.
	Optional<RawFrame[]> Animation(uint32 raw)
	{
		if (_animations.TryGet(raw) is RawFrame[] cached)
			return cached.Length == 0 ? null : cached;

		uint32 gid = GidOf(raw);
		var frames = new RawFrame[0];

		if (Map.FindTileset((int)gid) is TiledTilesetReference reference)
		{
			if (reference.Tileset.Animations.TryGet((int)gid - reference.FirstGid) is TileFrame[] tileFrames)
			{
				frames = new RawFrame[tileFrames.Length];

				for (var i = 0; i < tileFrames.Length; i += 1)
					frames[i] = RawFrame { Raw = (uint32)(reference.FirstGid + tileFrames[i].TileId) | FlipOf(raw), DurationMs = tileFrames[i].DurationMs };
			}
		}

		_animations.Set(raw, frames);

		return frames.Length == 0 ? null : frames;
	}

	/// The tile of an animated tile at the time, or the tile itself.
	uint32 CurrentFrame(uint32 raw, int64 timeMs)
	{
		if (Animation(raw) is RawFrame[] frames)
		{
			int64 total = 0;

			foreach (var frame in frames)
				total += (int64)frame.DurationMs;

			int64 time = timeMs % (total > 0 ? total : 1);

			foreach (var frame in frames)
			{
				if (time < (int64)frame.DurationMs)
					return frame.Raw;

				time -= (int64)frame.DurationMs;
			}
		}

		return raw;
	}

	/// True if the map has animated tiles (the view is redrawn every frame then).
	bool HasAnimations()
	{
		foreach (var reference in Map.Tilesets)
		{
			if (reference.Tileset.Animations.Count() > 0)
				return true;
		}

		return false;
	}
}

/// The picture of a tileset image, or no value if it cannot be read.
Optional<Image> Sheet(string path)
{
	if (TilesetSheets.TryGet(path) is Image cached)
		return cached;

	if (BrokenSheets.ContainsKey(path))
		return null;

	var loaded = LoadPng(path);

	if (loaded is Image image)
	{
		TilesetSheets.Set(path, image);

		return image;
	}

	Console.WriteErrorLine("tileset image " + path + ": " + loaded.Message + " (placeholder tiles are drawn)");
	BrokenSheets.Set(path, true);

	return null;
}
