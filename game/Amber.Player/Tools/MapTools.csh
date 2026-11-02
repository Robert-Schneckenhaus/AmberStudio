// What the map generators share (C#: the internal parts of MapGenerator): the terrain colors of the wang set, the tilesets
// of the Mana Seed sample map, the corner grid with its painting functions, the layers of a generated map and the TMX
// writer of the generators.

namespace Amber.Player.Tools;

using System;
using Amber.Base;
using Amber.Player.Tiled;

const int GeneratorTileSize = 16;

// terrain colors of the wang set
const int Dirt = 1;
const int LightGrass = 2;
const int DarkGrass = 3;
const int Cobble = 4;
const int Shallow = 5;
const int Deep = 6;

// first IDs of the tilesets (see GeneratorTilesets)
const int ForestTiles = 2049;
const int Objects32 = 2801;
const int TreeTiles = 2808;
const int TallTiles = 2811;
const int BridgeTiles = 2817;
const int CollisionTile = 2818;
const int SparkleTiles = 2946;
const int Objects48 = 2958;

struct GeneratorTileset
{
	int FirstGid;
	string File;
	int Count;
}

GeneratorTileset TilesetOf(int firstGid, string file, int count)
{
	return GeneratorTileset { FirstGid = firstGid, File = file, Count = count };
}

/// The tilesets in the order (and with the first IDs) of the Mana Seed sample map.
GeneratorTileset[] GeneratorTilesets = new GeneratorTileset[]
{
	TilesetOf(1, "summer forest wang tiles.tsx", 2048),
	TilesetOf(2049, "summer forest.tsx", 672),
	TilesetOf(2721, "summer waterfall B.tsx", 80),
	TilesetOf(2801, "summer 32x32.tsx", 7),
	TilesetOf(2808, "summer trees 80x112.tsx", 3),
	TilesetOf(2811, "summer 16x32.tsx", 6),
	TilesetOf(2817, "bonus bridge.tsx", 1),
	TilesetOf(2818, "collision & alpha.tsx", 128),
	TilesetOf(2946, "summer water sparkles.tsx", 12),
	TilesetOf(2958, "summer 48x32.tsx", 3)
};

string[] GeneratedLayerNames = new string[] { "ground", "decor", "objects", "over", "collision" };

/// A named point (cell coordinates) for NPC routines ("walk_to name").
struct Waypoint
{
	string Name;
	int X;
	int Y;
}

Waypoint WaypointOf(string name, int x, int y)
{
	return Waypoint { Name = name, X = x, Y = y };
}

/// A cell (or a position) of a map.
struct Cell
{
	int X;
	int Y;
	/// A tile number that belongs to the cell (sparkles, stones), or 0.
	int Tile;
}

Cell CellOf(int x, int y)
{
	return Cell { X = x, Y = y, Tile = 0 };
}

Cell TileCell(int x, int y, int tile)
{
	return Cell { X = x, Y = y, Tile = tile };
}

/// The terrain colors on the corners of the cells ((width + 1) x (height + 1) values). Copies share the values.
struct CornerGrid
{
	int Width;
	int Height;
	int[] Values;

	static CornerGrid Create(int width, int height)
	{
		return CornerGrid { Width = width, Height = height, Values = new int[width * height] };
	}

	int Get(int x, int y)
	{
		return Values[x * Height + y];
	}

	void Set(int x, int y, int color)
	{
		Values[x * Height + y] = color;
	}

	void Fill(int color)
	{
		for (var i = 0; i < Values.Length; i += 1)
			Values[i] = color;
	}

	void Rect(int x0, int y0, int x1, int y1, int color)
	{
		int right = x1 < Width - 1 ? x1 : Width - 1;
		int bottom = y1 < Height - 1 ? y1 : Height - 1;

		for (var x = x0 > 0 ? x0 : 0; x <= right; x += 1)
		{
			for (var y = y0 > 0 ? y0 : 0; y <= bottom; y += 1)
				Set(x, y, color);
		}
	}

	void Ellipse(double centerX, double centerY, double radiusX, double radiusY, int color)
	{
		for (var x = 0; x < Width; x += 1)
		{
			for (var y = 0; y < Height; y += 1)
			{
				double dx = ((double)x - centerX) / radiusX;
				double dy = ((double)y - centerY) / radiusY;

				if (dx * dx + dy * dy <= 1.0)
					Set(x, y, color);
			}
		}
	}
}

/// The layers of a generated map (ground, decor, objects, over, collision), the corner grid of the terrain and the blocked
/// cells. Copies share everything.
struct GeneratedMap
{
	int Width;
	int Height;
	CornerGrid Vertex;
	uint32[] Ground;
	uint32[] Decor;
	uint32[] Objects;
	uint32[] Over;
	uint32[] Collision;
	bool[] Blocked;

	static GeneratedMap Create(int width, int height)
	{
		int count = width * height;

		return GeneratedMap
		{
			Width = width, Height = height, Vertex = CornerGrid.Create(width + 1, height + 1), Ground = new uint32[count], Decor = new uint32[count],
			Objects = new uint32[count], Over = new uint32[count], Collision = new uint32[count], Blocked = new bool[count]
		};
	}

	bool IsBlocked(int x, int y)
	{
		return Blocked[y * Width + x];
	}

	void SetBlocked(int x, int y, bool value)
	{
		Blocked[y * Width + x] = value;
	}

	uint32 ObjectAt(int x, int y)
	{
		return Objects[y * Width + x];
	}

	void SetObject(int x, int y, int gid)
	{
		Objects[y * Width + x] = (uint32)gid;
	}

	uint32 DecorAt(int x, int y)
	{
		return Decor[y * Width + x];
	}

	void SetDecor(int x, int y, int gid)
	{
		Decor[y * Width + x] = (uint32)gid;
	}

	/// The ground from the wang set: every cell gets a tile for its four corner colors (a random variant), or the tile of
	/// the color of its top left corner if the set has no tile for the combination. With blockWater cells with deep water
	/// or mostly shallow water are blocked.
	Error<void> PaintGround(WangSet wang, DotNetRandom random, bool blockWater)
	{
		for (var y = 0; y < Height; y += 1)
		{
			for (var x = 0; x < Width; x += 1)
			{
				int topLeft = Vertex.Get(x, y);
				int topRight = Vertex.Get(x + 1, y);
				int bottomRight = Vertex.Get(x + 1, y + 1);
				int bottomLeft = Vertex.Get(x, y + 1);
				int variant = random.Next(64);
				int tile = wang.Find(topLeft, topRight, bottomRight, bottomLeft, variant);

				if (tile < 0)
					tile = wang.Find(topLeft, topLeft, topLeft, topLeft, variant);

				if (tile < 0)
					return error("No wang tile for corners " + topLeft + "," + topRight + "," + bottomRight + "," + bottomLeft + " at " + x + "," + y + ".", (int)ErrorKind.InvalidData);

				Ground[y * Width + x] = (uint32)(1 + tile);

				if (blockWater)
				{
					int deep = CountColor(topLeft, topRight, bottomRight, bottomLeft, Deep);
					int shallow = CountColor(topLeft, topRight, bottomRight, bottomLeft, Shallow);

					if (deep > 0 || shallow >= 3)
						SetBlocked(x, y, true);
				}
			}
		}

		return;
	}

	/// A 32x32 sprite of the object sheet, anchored at the bottom left cell; blocks the two bottom cells.
	void Place32(int local, int anchorX, int anchorY, bool block)
	{
		SetObject(anchorX, anchorY, Objects32 + local);

		if (block)
		{
			SetBlocked(anchorX, anchorY, true);
			SetBlocked(anchorX + 1, anchorY, true);
		}
	}

	/// The collision layer: blocked cells and, with a margin, the cells near the border of the map.
	void FillCollision(int margin)
	{
		for (var y = 0; y < Height; y += 1)
		{
			for (var x = 0; x < Width; x += 1)
			{
				bool edge = x < margin || y < margin || x >= Width - margin || y >= Height - margin;

				if (IsBlocked(x, y) || edge)
					Collision[y * Width + x] = (uint32)CollisionTile;
			}
		}
	}
}

int CountColor(int a, int b, int c, int d, int color)
{
	int count = 0;

	if (a == color)
		count += 1;

	if (b == color)
		count += 1;

	if (c == color)
		count += 1;

	if (d == color)
		count += 1;

	return count;
}

/// The wang set of the wang tileset (the TSX of the tilesets folder).
Error<WangSet> LoadWangSet(string wangTsxPath)
{
	if (!File.Exists(wangTsxPath))
		return error("The wang tileset is not installed: " + wangTsxPath, (int)ErrorKind.Io);

	var tileset = try TiledLoader.LoadTileset(wangTsxPath, TiledMap.Create(1, 1, GeneratorTileSize, GeneratorTileSize));

	if (tileset.Wang is WangSet wang)
		return wang;

	return error("The wang tileset has no wang set.", (int)ErrorKind.InvalidData);
}

/// Writes a Tiled map with the layers ground, decor, objects, over, collision and an object layer of waypoints.
Error<void> WriteTmx(string outputPath, string tilesetDirectoryRelative, GeneratedMap map, Waypoint[] waypoints)
{
	var builder = StringBuilder.Create();
	int width = map.Width;
	int height = map.Height;

	builder.AppendLine("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
	builder.AppendLine("<map version=\"1.9\" tiledversion=\"1.9.1\" orientation=\"orthogonal\" renderorder=\"right-down\" width=\"" + width + "\" height=\"" + height
		+ "\" tilewidth=\"" + GeneratorTileSize + "\" tileheight=\"" + GeneratorTileSize + "\" infinite=\"0\" nextlayerid=\"7\" nextobjectid=\"20\">");

	foreach (var tileset in GeneratorTilesets)
		builder.AppendLine(" <tileset firstgid=\"" + tileset.FirstGid + "\" source=\"" + tilesetDirectoryRelative + "/" + tileset.File.Replace("&", "&amp;") + "\"/>");

	var layers = new uint32[][] { map.Ground, map.Decor, map.Objects, map.Over, map.Collision };

	for (var i = 0; i < layers.Length; i += 1)
	{
		builder.AppendLine(" <layer id=\"" + (i + 1) + "\" name=\"" + GeneratedLayerNames[i] + "\" width=\"" + width + "\" height=\"" + height + "\">");
		builder.AppendLine("  <data encoding=\"csv\">");

		for (var y = 0; y < height; y += 1)
		{
			for (var x = 0; x < width; x += 1)
			{
				if (x > 0)
					builder.Append(',');

				builder.Append("" + layers[i][y * width + x]);
			}

			builder.AppendLine(y < height - 1 ? "," : "");
		}

		builder.AppendLine("  </data>");
		builder.AppendLine(" </layer>");
	}

	builder.AppendLine(" <objectgroup id=\"6\" name=\"waypoints\">");

	int id = 1;

	foreach (var waypoint in waypoints)
	{
		builder.AppendLine("  <object id=\"" + id + "\" name=\"" + waypoint.Name + "\" x=\"" + (waypoint.X * GeneratorTileSize + GeneratorTileSize / 2) + "\" y=\""
			+ (waypoint.Y * GeneratorTileSize + GeneratorTileSize / 2) + "\"><point/></object>");
		id += 1;
	}

	builder.AppendLine(" </objectgroup>");
	builder.AppendLine("</map>");

	string directory = Path.GetDirectory(outputPath);

	if (directory.Length > 0 && !Directory.Exists(directory))
		Directory.Create(directory);

	try File.WriteAllText(outputPath, builder.ToString());
	Console.WriteLine("Map written: " + outputPath);

	return;
}

/// The path of a folder relative to another one (C#: Path.GetRelativePath with '/'). Both paths are taken relative to the
/// current folder or both absolute; the function works on the names only.
Error<string> RelativePath(string fromFolder, string toPath)
{
	var from = PathParts(fromFolder);
	var to = PathParts(toPath);
	int common = 0;

	while (common < from.Count() && common < to.Count() && from.Get(common) == to.Get(common))
		common += 1;

	var parts = List<string>.Create();

	for (var i = common; i < from.Count(); i += 1)
	{
		if (from.Get(i) == "..")
			return error("Cannot compute the path from " + fromFolder + " to " + toPath + ": give the folder inside the repository.", (int)ErrorKind.Argument);

		parts.Add("..");
	}

	for (var i = common; i < to.Count(); i += 1)
		parts.Add(to.Get(i));

	return parts.Count() == 0 ? "." : JoinList("/", parts);
}

/// The names of a path with "." and ".." resolved as far as possible (leading ".." stay).
List<string> PathParts(string path)
{
	var parts = List<string>.Create();
	string normalized = Path.Normalize(path);

	if (normalized.StartsWith("/"))
		parts.Add("");

	foreach (var part in normalized.Split("/"))
	{
		if (part == "" || part == ".")
			continue;

		if (part == ".." && parts.Count() > 0 && parts.Get(parts.Count() - 1) != "..")
			parts.RemoveAt(parts.Count() - 1);
		else
			parts.Add(part.ToString());
	}

	return parts;
}
