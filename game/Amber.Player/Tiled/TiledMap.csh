namespace Amber.Player.Tiled;

using System;
using Amber.Base;

/// Flags in the upper bits of a Tiled global tile ID.
const uint32 FlipDiagonal = 0x20000000;
const uint32 FlipVertical = 0x40000000;
const uint32 FlipHorizontal = 0x80000000;
const uint32 FlipMask = 0xE0000000;

uint32 GidOf(uint32 raw)
{
	return raw & 0x0FFFFFFF;
}

uint32 FlipOf(uint32 raw)
{
	return raw & FlipMask;
}

struct TileFrame
{
	int TileId;
	int DurationMs;
}

/// The corner colors of a wang tile (1-based color indices, 0 = none).
struct WangCorners : IEquatable<WangCorners>, IHashable
{
	int TopLeft;
	int TopRight;
	int BottomRight;
	int BottomLeft;

	static WangCorners Of(int topLeft, int topRight, int bottomRight, int bottomLeft)
	{
		return WangCorners { TopLeft = topLeft, TopRight = topRight, BottomRight = bottomRight, BottomLeft = bottomLeft };
	}

	bool Equals(WangCorners other)
	{
		return TopLeft == other.TopLeft && TopRight == other.TopRight && BottomRight == other.BottomRight && BottomLeft == other.BottomLeft;
	}

	int GetHashCode()
	{
		return unchecked(((TopLeft * 31 + TopRight) * 31 + BottomRight) * 31 + BottomLeft);
	}
}

/// A Tiled corner wang set: which tile shows which combination of corner colors. Copies share the tables.
struct WangSet
{
	Dictionary<WangCorners, List<int>> _tiles;
	Dictionary<int, WangCorners> _corners;
	List<string> ColorNames;

	static WangSet Create()
	{
		return WangSet { _tiles = Dictionary<WangCorners, List<int>>.Create(), _corners = Dictionary<int, WangCorners>.Create(), ColorNames = List<string>.Create() };
	}

	int TileCount()
	{
		return _corners.Count();
	}

	void Add(int tileId, int topLeft, int topRight, int bottomRight, int bottomLeft)
	{
		var key = WangCorners.Of(topLeft, topRight, bottomRight, bottomLeft);

		if (!_tiles.ContainsKey(key))
			_tiles.Set(key, List<int>.Create());

		if (_tiles.TryGet(key) is List<int> list)
			list.Add(tileId);

		_corners.Set(tileId, key);
	}

	/// A tile for the corner colors, or -1. With several candidates the variant is chosen with the given number.
	int Find(int topLeft, int topRight, int bottomRight, int bottomLeft, int variant)
	{
		if (_tiles.TryGet(WangCorners.Of(topLeft, topRight, bottomRight, bottomLeft)) is List<int> list)
		{
			if (list.Count() > 0)
				return list.Get(variant % list.Count());
		}

		return -1;
	}

	/// The corner colors of a tile of the wang set, or no value if the tile does not belong to it.
	Optional<WangCorners> CornersOf(int tileId)
	{
		return _corners.TryGet(tileId);
	}

	int ColorIndex(string name)
	{
		return IndexOfText(ColorNames, name) + 1;
	}
}

/// A tileset. Missing is true when the TSX file is not installed (the third party packs are not in the repository): the
/// game then draws placeholder tiles. ImagePath is null when the picture is missing.
struct TiledTileset
{
	string Name;
	int TileWidth;
	int TileHeight;
	int TileCount;
	int Columns;
	string ImagePath;
	bool Missing;
	Dictionary<int, TileFrame[]> Animations;
	Optional<WangSet> Wang;
}

struct TiledTilesetReference
{
	/// The source attribute of the tileset in the TMX (relative path of the TSX file), null for embedded tilesets.
	string Source;
	int FirstGid;
	TiledTileset Tileset;

	bool Contains(int gid)
	{
		return gid >= FirstGid && gid < FirstGid + Tileset.TileCount;
	}
}

/// A tile layer; copies share the tiles.
struct TiledLayer
{
	string Name;
	int Width;
	int Height;
	/// Raw tile IDs including flip flags, row by row.
	uint32[] Data;
	bool Visible;
	Dictionary<string, string> Properties;

	uint32 Get(int x, int y)
	{
		if (x < 0 || y < 0 || x >= Width || y >= Height)
			return 0;

		return Data[y * Width + x];
	}

	void Set(int x, int y, uint32 value)
	{
		if (x >= 0 && y >= 0 && x < Width && y < Height)
			Data[y * Width + x] = value;
	}
}

struct TiledObject
{
	string Name;
	string Type;
	float X;
	float Y;
	float Width;
	float Height;
	Dictionary<string, string> Properties;
}

struct TiledObjectLayer
{
	string Name;
	List<TiledObject> Objects;
}

/// A Tiled map (TMX). Copies share the lists and the tiles.
struct TiledMap
{
	int Width;
	int Height;
	int TileWidth;
	int TileHeight;
	List<TiledTilesetReference> Tilesets;
	List<TiledLayer> Layers;
	List<TiledObjectLayer> ObjectLayers;
	Dictionary<string, string> Properties;
	/// The file the map was read from, or null.
	string Path;

	static TiledMap Create(int width, int height, int tileWidth, int tileHeight)
	{
		return TiledMap
		{
			Width = width, Height = height, TileWidth = tileWidth, TileHeight = tileHeight, Tilesets = List<TiledTilesetReference>.Create(),
			Layers = List<TiledLayer>.Create(), ObjectLayers = List<TiledObjectLayer>.Create(), Properties = Dictionary<string, string>.Create(), Path = null
		};
	}

	Optional<TiledTilesetReference> FindTileset(int gid)
	{
		foreach (var reference in Tilesets)
		{
			if (reference.Contains(gid))
				return reference;
		}

		return null;
	}

	/// The layer with the name (case does not matter).
	Optional<TiledLayer> FindLayer(string name)
	{
		string lower = name.ToLower();

		foreach (var layer in Layers)
		{
			if (layer.Name.ToLower() == lower)
				return layer;
		}

		return null;
	}

	/// True if any tileset of the map is not installed.
	bool HasMissingTilesets()
	{
		foreach (var reference in Tilesets)
		{
			if (reference.Tileset.Missing || reference.Tileset.ImagePath == null)
				return true;
		}

		return false;
	}
}
