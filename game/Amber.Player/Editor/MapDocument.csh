// The map being edited: the Tiled map, its file, the terrain (colors on the corner grid, derived from the wang tiles of the
// ground layer) and the undo history. Every change of a tile goes through SetTile so it can be undone.

namespace Amber.Player.Editor;

using System;
using Amber.Base;
using Amber.Player.Game;
using Amber.Player.Tiled;

/// A cell of the map (or a vertex of the corner grid).
struct EditorCell
{
	int X;
	int Y;

	static EditorCell Of(int x, int y)
	{
		return EditorCell { X = x, Y = y };
	}

	bool Same(EditorCell other)
	{
		return X == other.X && Y == other.Y;
	}
}

struct TileChange
{
	int Layer;
	int X;
	int Y;
	uint32 Before;
	uint32 After;
}

struct VertexChange
{
	int X;
	int Y;
	int Before;
	int After;
}

/// A group of changes which is undone as one step (a mouse stroke). Copies share the lists.
struct Stroke
{
	List<TileChange> Tiles;
	List<VertexChange> Vertices;

	static Stroke Create()
	{
		return Stroke { Tiles = List<TileChange>.Create(), Vertices = List<VertexChange>.Create() };
	}

	bool IsEmpty()
	{
		return Tiles.Count() == 0 && Vertices.Count() == 0;
	}
}

struct DocumentValues
{
	bool Dirty;
	bool HasStroke;
	Stroke Current;
}

/// The document; a handle (copies share the state).
struct MapDocument
{
	DocumentValues[] _s;
	string Path;
	TiledMap Map;
	/// The index of the tileset with the wang set in Map.Tilesets, or -1.
	int WangIndex;
	/// The index of the ground layer in Map.Layers.
	int Ground;
	/// The terrain colors (1-based wang color index, 0 = none) on the corner grid, (width + 1) x (height + 1), row by row.
	int[] Vertices;
	List<Stroke> _undo;
	List<Stroke> _redo;

	static Error<MapDocument> Open(string path)
	{
		var map = try TiledLoader.Load(path);
		int wangIndex = -1;

		for (var i = 0; i < map.Tilesets.Count(); i += 1)
		{
			if (map.Tilesets.Get(i).Tileset.Wang is WangSet)
			{
				wangIndex = i;

				break;
			}
		}

		if (map.Layers.Count() == 0)
			return error("The map has no tile layers: " + path, (int)ErrorKind.InvalidData);

		int ground = 0;

		for (var i = 0; i < map.Layers.Count(); i += 1)
		{
			if (map.Layers.Get(i).Name.ToLower() == "ground")
			{
				ground = i;

				break;
			}
		}

		var document = MapDocument
		{
			_s = new DocumentValues[1], Path = path, Map = map, WangIndex = wangIndex, Ground = ground, Vertices = new int[(map.Width + 1) * (map.Height + 1)],
			_undo = List<Stroke>.Create(), _redo = List<Stroke>.Create()
		};

		document.BuildVertices();

		return document;
	}

	bool Dirty()
	{
		return _s[0].Dirty;
	}

	bool CanUndo()
	{
		return _undo.Count() > 0;
	}

	bool CanRedo()
	{
		return _redo.Count() > 0;
	}

	string Name()
	{
		return System.Path.GetStem(Path);
	}

	TiledLayer GroundLayer()
	{
		return Map.Layers.Get(Ground);
	}

	/// The wang set used by the terrain brush, or no value.
	Optional<WangSet> Wang()
	{
		if (WangIndex < 0)
			return null;

		return Map.Tilesets.Get(WangIndex).Tileset.Wang;
	}

	int Vertex(int x, int y)
	{
		return Vertices[y * (Map.Width + 1) + x];
	}

	void SetVertex(int x, int y, int color)
	{
		Vertices[y * (Map.Width + 1) + x] = color;
	}

	void BuildVertices()
	{
		if (WangIndex < 0)
			return;

		var reference = Map.Tilesets.Get(WangIndex);

		if (reference.Tileset.Wang is WangSet wang)
		{
			int fallback = Max(1, wang.ColorIndex("light grass"));
			var ground = GroundLayer();

			for (var y = 0; y < Map.Height; y += 1)
			{
				for (var x = 0; x < Map.Width; x += 1)
				{
					int gid = (int)GidOf(ground.Get(x, y));

					if (gid == 0 || !reference.Contains(gid))
						continue;

					if (wang.CornersOf(gid - reference.FirstGid) is WangCorners corners)
					{
						SetVertex(x, y, corners.TopLeft);
						SetVertex(x + 1, y, corners.TopRight);
						SetVertex(x + 1, y + 1, corners.BottomRight);
						SetVertex(x, y + 1, corners.BottomLeft);
					}
				}
			}

			// cells with other tiles (flowers ...) have no known terrain: assume the base grass
			for (var i = 0; i < Vertices.Length; i += 1)
			{
				if (Vertices[i] == 0)
					Vertices[i] = fallback;
			}
		}
	}

	/// Starts a group of changes which is undone as one step (a mouse stroke).
	void BeginStroke()
	{
		if (!_s[0].HasStroke)
		{
			_s[0].Current = Stroke.Create();
			_s[0].HasStroke = true;
		}
	}

	void EndStroke()
	{
		if (_s[0].HasStroke && !_s[0].Current.IsEmpty())
		{
			_undo.Add(_s[0].Current);
			_redo.Clear();
		}

		_s[0].HasStroke = false;
	}

	/// Sets a tile. Returns false if the cell is outside the map or already has the value.
	bool SetTile(int layerIndex, int x, int y, uint32 raw)
	{
		var layer = Map.Layers.Get(layerIndex);

		if (x < 0 || y < 0 || x >= layer.Width || y >= layer.Height)
			return false;

		uint32 before = layer.Get(x, y);

		if (before == raw)
			return false;

		layer.Set(x, y, raw);
		_s[0].Dirty = true;

		bool ownStroke = !_s[0].HasStroke;

		BeginStroke();
		_s[0].Current.Tiles.Add(TileChange { Layer = layerIndex, X = x, Y = y, Before = before, After = raw });

		if (ownStroke)
			EndStroke();

		return true;
	}

	/// Paints a terrain color on a square of vertices (the corner grid) and replaces the ground tiles around them by the
	/// matching wang tiles. Returns null, or the reason why a combination of corners has no tile; nothing changes then.
	string PaintTerrain(int vertexX, int vertexY, int color, int size)
	{
		if (WangIndex < 0)
			return "This map has no wang tileset.";

		var reference = Map.Tilesets.Get(WangIndex);
		var changes = List<VertexChange>.Create();
		int first = size / 2;

		for (var dy = 0; dy < size; dy += 1)
		{
			for (var dx = 0; dx < size; dx += 1)
			{
				int x = vertexX - first + dx;
				int y = vertexY - first + dy;

				if (x >= 0 && y >= 0 && x <= Map.Width && y <= Map.Height && Vertex(x, y) != color)
					changes.Add(VertexChange { X = x, Y = y, Before = Vertex(x, y), After = color });
			}
		}

		if (changes.Count() == 0)
			return null;

		if (reference.Tileset.Wang is WangSet wang)
		{
			foreach (var change in changes)
				SetVertex(change.X, change.Y, change.After);

			// all cells which touch a changed vertex, in the order they are found
			var cells = List<EditorCell>.Create();
			var seen = Dictionary<int, bool>.Create();

			foreach (var change in changes)
			{
				for (var dy = -1; dy <= 0; dy += 1)
				{
					for (var dx = -1; dx <= 0; dx += 1)
					{
						int x = change.X + dx;
						int y = change.Y + dy;

						if (x >= 0 && y >= 0 && x < Map.Width && y < Map.Height && !seen.ContainsKey(y * Map.Width + x))
						{
							seen.Set(y * Map.Width + x, true);
							cells.Add(EditorCell.Of(x, y));
						}
					}
				}
			}

			var tiles = List<TileChange>.Create();

			foreach (var cell in cells)
			{
				int x = cell.X;
				int y = cell.Y;
				int variant = unchecked(x * 73856093 ^ y * 19349663) & 0x7FFFFFFF;
				int tile = wang.Find(Vertex(x, y), Vertex(x + 1, y), Vertex(x + 1, y + 1), Vertex(x, y + 1), variant);

				if (tile < 0)
				{
					string firstName = wang.ColorNames.Get(Vertex(x, y) - 1);
					string second = wang.ColorNames.Get(Vertex(x + 1, y) - 1);

					foreach (var undo in changes)
						SetVertex(undo.X, undo.Y, undo.Before);

					return "No tile for " + firstName + " next to " + second + ": paint a transition terrain first.";
				}

				tiles.Add(TileChange { Layer = Ground, X = x, Y = y, After = (uint32)(reference.FirstGid + tile) });
			}

			bool ownStroke = !_s[0].HasStroke;

			BeginStroke();

			foreach (var change in changes)
				_s[0].Current.Vertices.Add(change);

			foreach (var tile in tiles)
				SetTile(Ground, tile.X, tile.Y, tile.After);

			if (ownStroke)
				EndStroke();

			_s[0].Dirty = true;

			return null;
		}

		return "This map has no wang tileset.";
	}

	bool Undo()
	{
		if (_undo.Count() == 0)
			return false;

		var stroke = _undo.Get(_undo.Count() - 1);

		_undo.RemoveAt(_undo.Count() - 1);

		for (var i = stroke.Tiles.Count() - 1; i >= 0; i -= 1)
		{
			var change = stroke.Tiles.Get(i);

			Map.Layers.Get(change.Layer).Set(change.X, change.Y, change.Before);
		}

		foreach (var change in stroke.Vertices)
			SetVertex(change.X, change.Y, change.Before);

		_redo.Add(stroke);
		_s[0].Dirty = true;

		return true;
	}

	bool Redo()
	{
		if (_redo.Count() == 0)
			return false;

		var stroke = _redo.Get(_redo.Count() - 1);

		_redo.RemoveAt(_redo.Count() - 1);

		foreach (var change in stroke.Tiles)
			Map.Layers.Get(change.Layer).Set(change.X, change.Y, change.After);

		foreach (var change in stroke.Vertices)
			SetVertex(change.X, change.Y, change.After);

		_undo.Add(stroke);
		_s[0].Dirty = true;

		return true;
	}

	/// The tile whose graphic covers the cell (tiles are anchored at their bottom left cell and extend up and to the right),
	/// preferring the one which is drawn in front. Returns the anchor cell or no value.
	Optional<EditorCell> FindTileAt(int layerIndex, int x, int y)
	{
		var layer = Map.Layers.Get(layerIndex);

		for (var anchorY = y + 8; anchorY >= y; anchorY -= 1)
		{
			for (var anchorX = x; anchorX >= x - 6; anchorX -= 1)
			{
				uint32 raw = layer.Get(anchorX, anchorY);

				if (GidOf(raw) == 0)
					continue;

				if (Map.FindTileset((int)GidOf(raw)) is TiledTilesetReference reference)
				{
					int columns = (reference.Tileset.TileWidth + Map.TileWidth - 1) / Map.TileWidth;
					int rows = (reference.Tileset.TileHeight + Map.TileHeight - 1) / Map.TileHeight;

					if (x < anchorX + columns && y > anchorY - rows)
						return EditorCell.Of(anchorX, anchorY);
				}
			}
		}

		return null;
	}

	/// Saves the map. The previous file is kept as name.tmx.bak.
	Error<void> Save()
	{
		if (File.Exists(Path))
			try File.WriteAllBytes(Path + ".bak", try File.ReadAllBytes(Path));

		try TiledWriter.Save(Map, Path);
		_s[0].Dirty = false;

		return;
	}
}
