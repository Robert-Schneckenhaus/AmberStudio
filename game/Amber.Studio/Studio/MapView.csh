// The map area: a Tiled map of the project, drawn by the renderer of the game (the same picture as in the game), with
// the tools of the map editor of the prototype (MapDocument: tiles, terrain from the wang set, undo by strokes, TMX
// writing). The tools, the layers and the tiles of a tileset are in the panel on the right.

namespace Amber.Studio;

using System;
using System.Image;
using System.Ui;
using Amber.Base;
using Amber.Player.Editor;
using Amber.Player.Graphics;
using Amber.Player.Tiled;

struct MapViewValues
{
	int Layer;
	EditorTool Tool;
	uint32 Gid;
	/// The terrain color (1-based index of the wang colors) and the size of the terrain brush.
	int Terrain;
	int Brush;
	int Zoom;
	bool Grid;
	bool ShowCollision;
	bool Painting;
	bool HasLast;
	int LastX;
	int LastY;
	/// The changes of the map (the picture is made again when Rendered differs).
	int Version;
	int Rendered;
	bool Hover;
	int HoverX;
	int HoverY;
	/// The palette: the index into PaletteSets of the tileset shown.
	int Tileset;
	string Message;
	/// Where the map was drawn in the last frame (pixels of the frame), for the tests.
	Rect Canvas;
}

/// A map that is open; a handle.
struct MapView
{
	MapViewValues[] _s;
	string Name;
	MapDocument Doc;
	TileImages Images;
	/// The index of the collision layer (-1 none) and the first ID of the collision tileset (its marker), 0 none.
	int CollisionLayer;
	uint32 CollisionGid;
	/// The tilesets of the palette (indices into Map.Tilesets): not the wang tileset, not the collision tileset.
	List<int> PaletteSets;
	Dictionary<int, bool> Hidden;
	Image[] _frame;
	Dictionary<int, Image> _sheets;

	static Error<MapView> Open(string name, string path)
	{
		var doc = try MapDocument.Open(path);
		var map = doc.Map;
		int collision = -1;

		for (var i = 0; i < map.Layers.Count(); i += 1)
		{
			if (map.Layers.Get(i).Name.ToLower() == "collision")
				collision = i;
		}

		uint32 collisionGid = 0;
		var sets = List<int>.Create();

		for (var i = 0; i < map.Tilesets.Count(); i += 1)
		{
			var reference = map.Tilesets.Get(i);
			string lower = reference.Tileset.Name.ToLower();

			if (lower.Contains("collision"))
			{
				if (collisionGid == 0)
					collisionGid = (uint32)reference.FirstGid;
			}
			else if (i != doc.WangIndex && !(reference.Tileset.Missing && lower.Contains("wang")))
				sets.Add(i);
		}

		var values = new MapViewValues[1];

		values[0].Layer = doc.Ground;
		values[0].Tool = EditorTool.Paint;
		values[0].Terrain = 2;
		values[0].Brush = 1;
		values[0].Zoom = 2;
		values[0].Grid = false;
		values[0].Rendered = -1;
		values[0].Message = "";

		if (sets.Count() > 0)
			values[0].Gid = (uint32)map.Tilesets.Get(sets.Get(0)).FirstGid;

		return MapView
		{
			_s = values, Name = name, Doc = doc, Images = TileImages.Create(map), CollisionLayer = collision, CollisionGid = collisionGid, PaletteSets = sets,
			Hidden = Dictionary<int, bool>.Create(), _frame = new Image[1], _sheets = Dictionary<int, Image>.Create()
		};
	}

	bool IsOpen()
	{
		return _s.Length > 0;
	}

	TiledMap Map()
	{
		return Doc.Map;
	}

	string Message()
	{
		return _s[0].Message;
	}

	Rect CanvasRect()
	{
		return _s[0].Canvas;
	}

	int Zoom()
	{
		return _s[0].Zoom;
	}

	/// The cell under the mouse in the last frame (false: the mouse is not over the map).
	bool Hovered(ref int x, ref int y)
	{
		x = _s[0].HoverX;
		y = _s[0].HoverY;

		return _s[0].Hover;
	}

	void Changed()
	{
		_s[0].Version += 1;
	}

	void SetTool(EditorTool tool)
	{
		_s[0].Tool = tool;
	}

	EditorTool Tool()
	{
		return _s[0].Tool;
	}

	void SetLayer(int layer)
	{
		if (layer >= 0 && layer < Doc.Map.Layers.Count())
			_s[0].Layer = layer;
	}

	int Layer()
	{
		return _s[0].Layer;
	}

	void SelectGid(uint32 gid)
	{
		_s[0].Gid = gid;

		for (var i = 0; i < PaletteSets.Count(); i += 1)
		{
			var reference = Doc.Map.Tilesets.Get(PaletteSets.Get(i));

			if ((int)gid >= reference.FirstGid && (int)gid < reference.FirstGid + reference.Tileset.TileCount)
				_s[0].Tileset = i;
		}
	}

	uint32 Gid()
	{
		return _s[0].Gid;
	}

	bool Undo()
	{
		bool done = Doc.Undo();

		if (done)
			Changed();

		return done;
	}

	bool Redo()
	{
		bool done = Doc.Redo();

		if (done)
			Changed();

		return done;
	}

	Error<void> Save()
	{
		try Doc.Save();
		OfferDownload(Doc.Path);
		_s[0].Message = Name + ".tmx gespeichert";

		return;
	}

	bool CollisionSelected()
	{
		return _s[0].Layer == CollisionLayer && CollisionLayer >= 0;
	}

	/// The tool at a cell (or at the corner of the terrain grid next to the point), as one step of the stroke.
	void Apply(int cellX, int cellY, int vertexX, int vertexY)
	{
		var tool = _s[0].Tool;

		if (tool == EditorTool.Terrain)
		{
			if (_s[0].HasLast && _s[0].LastX == vertexX && _s[0].LastY == vertexY)
				return;

			_s[0].HasLast = true;
			_s[0].LastX = vertexX;
			_s[0].LastY = vertexY;

			string problem = Doc.PaintTerrain(vertexX, vertexY, _s[0].Terrain, _s[0].Brush);

			if (problem != null)
				_s[0].Message = problem;

			Changed();

			return;
		}

		if (_s[0].HasLast && _s[0].LastX == cellX && _s[0].LastY == cellY)
			return;

		_s[0].HasLast = true;
		_s[0].LastX = cellX;
		_s[0].LastY = cellY;

		int layer = _s[0].Layer;

		if (tool == EditorTool.Paint)
		{
			uint32 gid = CollisionSelected() ? CollisionGid : _s[0].Gid;

			if (gid != 0 && Doc.SetTile(layer, cellX, cellY, gid))
				Changed();
		}
		else if (tool == EditorTool.Erase)
		{
			if (Doc.FindTileAt(layer, cellX, cellY) is EditorCell anchor)
			{
				if (Doc.SetTile(layer, anchor.X, anchor.Y, 0))
					Changed();
			}
		}
		else if (tool == EditorTool.Pick)
			Pick(cellX, cellY);
	}

	/// The tile under the point on the selected layer, else on the layers above, becomes the tile to paint with.
	void Pick(int x, int y)
	{
		for (var index = _s[0].Layer; index < Doc.Map.Layers.Count(); index += 1)
		{
			if (index == CollisionLayer)
				continue;

			if (Doc.FindTileAt(index, x, y) is EditorCell anchor)
			{
				var layer = Doc.Map.Layers.Get(index);
				uint32 gid = GidOf(layer.Get(anchor.X, anchor.Y));

				if (gid != 0)
				{
					SelectGid(gid);
					_s[0].Layer = index;
					_s[0].Tool = EditorTool.Paint;
					_s[0].Message = "Kachel " + gid + " von " + layer.Name + " genommen";
				}

				return;
			}
		}
	}

	void BeginStroke()
	{
		Doc.BeginStroke();
		_s[0].Painting = true;
		_s[0].HasLast = false;
	}

	void EndStroke()
	{
		if (_s[0].Painting)
			Doc.EndStroke();

		_s[0].Painting = false;
	}

	Image Frame()
	{
		if (_s[0].Rendered != _s[0].Version || _frame[0].Width == 0)
		{
			var hidden = Dictionary<int, bool>.Create();

			foreach (var key in Hidden.Keys())
			{
				if (Hidden.GetOrDefault(key, false))
					hidden.Set(key, true);
			}

			if (!_s[0].ShowCollision && CollisionLayer >= 0)
				hidden.Set(CollisionLayer, true);

			_frame[0] = RenderMapImage(Doc.Map, Images, hidden, CollisionLayer);
			_s[0].Rendered = _s[0].Version;
		}

		return _frame[0];
	}

	/// The map in the middle: as large as the zoom says, in an area that scrolls both ways, `height` pixels high (at
	/// scale 1).
	void DrawCanvas(Ui ui, int height)
	{
		var map = Doc.Map;
		var frame = Frame();
		int tileWidth = Math.Max(1, map.TileWidth);
		int tileHeight = Math.Max(1, map.TileHeight);
		int zoom = _s[0].Zoom;
		var theme = ui.GetTheme();

		_s[0].Hover = false;

		using (ui.ScrollArea("map:" + Name, 0, height))
		{
			var r = ui.Area("canvas:" + Name, frame.Width * zoom, frame.Height * zoom);

			_s[0].Canvas = r;
			ui.DrawImage(frame, Rect.Create(0, 0, frame.Width, frame.Height), r);

			// a cell in pixels of the frame
			int cellW = Math.Max(1, r.Width * tileWidth / Math.Max(1, frame.Width));
			int cellH = Math.Max(1, r.Height * tileHeight / Math.Max(1, frame.Height));

			if (_s[0].Grid)
			{
				var line = Color.FromArgb(70, 255, 255, 255);

				for (var x = 0; x <= map.Width; x += 1)
					ui.FillRect(Rect.Create(r.X + x * r.Width / map.Width, r.Y, 1, r.Height), line);

				for (var y = 0; y <= map.Height; y += 1)
					ui.FillRect(Rect.Create(r.X, r.Y + y * r.Height / map.Height, r.Width, 1), line);
			}

			var input = ui.Input();
			bool hovered = ui.Hovered();
			bool held = ui.Held();
			bool right = ui.RightClicked();

			if (hovered || held)
			{
				int px = (input.MouseX - r.X) * frame.Width / Math.Max(1, r.Width);
				int py = (input.MouseY - r.Y) * frame.Height / Math.Max(1, r.Height);
				int cellX = Clamp(px / tileWidth, 0, map.Width - 1);
				int cellY = Clamp(py / tileHeight, 0, map.Height - 1);
				int vertexX = Clamp((px + tileWidth / 2) / tileWidth, 0, map.Width);
				int vertexY = Clamp((py + tileHeight / 2) / tileHeight, 0, map.Height);

				_s[0].Hover = hovered;
				_s[0].HoverX = cellX;
				_s[0].HoverY = cellY;
				ui.SetCursor(Cursor.Crosshair);

				if (right)
					Pick(cellX, cellY);
				else if (held)
				{
					if (!_s[0].Painting)
						BeginStroke();

					Apply(cellX, cellY, vertexX, vertexY);
				}

				// the cell (or the corner) under the mouse
				int ox = r.X + cellX * cellW;
				int oy = r.Y + cellY * cellH;

				if (_s[0].Tool == EditorTool.Terrain)
				{
					ox = r.X + vertexX * cellW - cellW / 2;
					oy = r.Y + vertexY * cellH - cellH / 2;
				}

				Outline(ui, Rect.Create(ox, oy, cellW, cellH), theme.Focus);
			}

			if (!held && _s[0].Painting)
				EndStroke();

			// Ctrl and the wheel zoom
			if (hovered && input.Ctrl && input.Wheel != 0)
				_s[0].Zoom = Clamp(zoom + (input.Wheel > 0 ? 1 : -1), 1, 6);
		}
	}

	/// The panel on the right: tools, layers, terrain or tiles.
	void DrawPanel(Ui ui, int height)
	{
		var map = Doc.Map;

		ui.Label("Werkzeug");

		int tool = (int)_s[0].Tool;

		using (ui.Columns(2))
		{
			ui.Radio("Malen", ref tool, (int)EditorTool.Paint);
			ui.Radio("Radieren", ref tool, (int)EditorTool.Erase);
			ui.Radio("Pipette", ref tool, (int)EditorTool.Pick);

			if (Doc.WangIndex >= 0)
				ui.Radio("Gelände", ref tool, (int)EditorTool.Terrain);
		}

		_s[0].Tool = (EditorTool)tool;

		using (ui.Row())
		{
			ui.Checkbox("Raster", ref _s[0].Grid);

			if (CollisionLayer >= 0 && ui.Checkbox("Kollision", ref _s[0].ShowCollision))
				Changed();
		}

		using (ui.Row())
		{
			ui.Label("Zoom");
			ui.Slider("zoom", ref _s[0].Zoom, 1, 6);
		}

		ui.Separator();
		ui.Label("Ebenen");

		for (var i = 0; i < map.Layers.Count(); i += 1)
		{
			var layer = map.Layers.Get(i);

			using (ui.Id(i))
			{
				using (ui.Row())
				{
					bool visible = !Hidden.GetOrDefault(i, false);

					if (ui.Checkbox("##visible", ref visible))
					{
						Hidden.Set(i, !visible);
						Changed();
					}

					ui.Tooltip("Ebene zeigen");

					if (ui.ListItem(layer.Name + "##layer", _s[0].Layer == i))
						_s[0].Layer = i;
				}
			}
		}

		ui.Separator();

		if (_s[0].Tool == EditorTool.Terrain)
			DrawTerrain(ui);
		else if (CollisionSelected())
			ui.Note("Die Kollisionsebene malt mit ihrer Markierung.");
		else
			DrawTiles(ui, height - 300);
	}

	void DrawTerrain(Ui ui)
	{
		ui.Label("Gelände");

		if (Doc.Wang() is WangSet wang)
		{
			for (var i = 0; i < wang.ColorNames.Count(); i += 1)
			{
				using (ui.Id(i))
				{
					if (ui.ListItem(wang.ColorNames.Get(i), _s[0].Terrain == i + 1))
						_s[0].Terrain = i + 1;
				}
			}
		}

		using (ui.Row())
		{
			ui.Label("Pinsel");
			ui.IntBox("brush", ref _s[0].Brush, 1, 5);
		}
	}

	void DrawTiles(Ui ui, int height)
	{
		if (PaletteSets.Count() == 0)
		{
			ui.Note("Die Karte hat keine Tilesets zum Malen.");

			return;
		}

		var names = List<string>.Create();

		foreach (var index in PaletteSets)
			names.Add(Doc.Map.Tilesets.Get(index).Tileset.Name);

		ui.ComboBox("tileset", ref _s[0].Tileset, names);

		int setIndex = PaletteSets.Get(Clamp(_s[0].Tileset, 0, PaletteSets.Count() - 1));
		var reference = Doc.Map.Tilesets.Get(setIndex);
		var tileset = reference.Tileset;

		if (tileset.Missing)
			ui.Note("Bilder nicht installiert (Platzhalter).");

		if (!_sheets.ContainsKey(setIndex))
			_sheets.Set(setIndex, RenderTileset(reference, Images));

		var sheet = _sheets.GetOrDefault(setIndex, Image.Create(1, 1));
		int columns = Math.Max(1, tileset.Columns);
		int cellW = Math.Max(1, tileset.TileWidth);
		int cellH = Math.Max(1, tileset.TileHeight);

		using (ui.ScrollArea("tiles", 0, Math.Max(80, height)))
		{
			var r = ui.Area("sheet", sheet.Width, sheet.Height);

			ui.DrawImage(sheet, Rect.Create(0, 0, sheet.Width, sheet.Height), r);

			int scaledW = Math.Max(1, r.Width * cellW / Math.Max(1, sheet.Width));
			int scaledH = Math.Max(1, r.Height * cellH / Math.Max(1, sheet.Height));
			int selected = (int)_s[0].Gid - reference.FirstGid;

			if (selected >= 0 && selected < tileset.TileCount)
				Outline(ui, Rect.Create(r.X + selected % columns * scaledW, r.Y + selected / columns * scaledH, scaledW, scaledH), ui.GetTheme().Accent);

			if (ui.Clicked())
			{
				var input = ui.Input();
				int index = (input.MouseY - r.Y) / scaledH * columns + (input.MouseX - r.X) / scaledW;

				if (index >= 0 && index < tileset.TileCount)
				{
					_s[0].Gid = (uint32)(reference.FirstGid + index);
					_s[0].Tool = EditorTool.Paint;
				}
			}
		}

		ui.Note("Kachel " + _s[0].Gid);
	}
}

/// The outline of a rectangle, 2 pixels wide.
void Outline(Ui ui, Rect r, Color color)
{
	ui.FillRect(Rect.Create(r.X, r.Y, r.Width, 2), color);
	ui.FillRect(Rect.Create(r.X, r.Y + r.Height - 2, r.Width, 2), color);
	ui.FillRect(Rect.Create(r.X, r.Y, 2, r.Height), color);
	ui.FillRect(Rect.Create(r.X + r.Width - 2, r.Y, 2, r.Height), color);
}

int Clamp(int value, int low, int high)
{
	return value < low ? low : value > high ? high : value;
}
