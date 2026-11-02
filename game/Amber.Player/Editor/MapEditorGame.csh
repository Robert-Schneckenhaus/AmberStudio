// The map editor for the visual layers of a Tiled map (ground, decoration, objects, canopy) and the collision layer. It runs
// in the same window and with the same renderer as the game, at a virtual screen of 640x400. Start it with --edit [map].
// The result is written as TMX and can be opened in Tiled as well.

namespace Amber.Player.Editor;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Game;
using Amber.Player.Game.Ui;
using Amber.Player.Graphics;
using Amber.Player.Platform;
using Amber.Player.Tiled;

/// The tools of the map editor.
enum EditorTool : int32
{
	/// Places the selected tile on the selected layer.
	Paint,
	/// Paints a terrain (dirt, grass, water ...) on the ground; the ground tiles are chosen from the wang set.
	Terrain,
	/// Removes the tile under the mouse from the selected layer.
	Erase,
	/// Takes the tile under the mouse as the selected tile.
	Pick
}

const int EditorWidth = 640;
const int EditorHeight = 400;
const int TopBar = 32;
const int StatusBar = 16;
const int PanelWidth = 208;
const int EditorTileSize = 16;
const int MapViewWidth = EditorWidth - PanelWidth;
const int MapViewHeight = EditorHeight - TopBar - StatusBar;
const int PanelX = MapViewWidth;

struct Swatch
{
	string Name;
	Color Color;
	int X;
	int Y;
}

Swatch SwatchOf(string name, Color color)
{
	return Swatch { Name = name, Color = color, X = 0, Y = 0 };
}

Swatch[] TerrainSwatches = new Swatch[]
{
	SwatchOf("dirt", Color.Of(150, 108, 70)), SwatchOf("light grass", Color.Of(140, 170, 60)), SwatchOf("dark grass", Color.Of(60, 100, 62)),
	SwatchOf("cobblestone", Color.Of(176, 164, 140)), SwatchOf("shallow water", Color.Of(70, 170, 210)), SwatchOf("deep water", Color.Of(20, 50, 120))
};

Color SwatchColor(string name)
{
	foreach (var swatch in TerrainSwatches)
	{
		if (swatch.Name == name)
			return swatch.Color;
	}

	return Color.Of(128, 128, 128);
}

struct EditorValues
{
	bool QuitRequested;
	EditorTool Tool;
	int CameraX;
	int CameraY;
	int LayerIndex;
	int TerrainColor;
	int BrushSize;
	bool ShowGrid;
	bool ShowCollision;
	bool Painting;
	bool HasLastCell;
	EditorCell LastCell;
	bool HasLastVertex;
	EditorCell LastVertex;
	int MessageTicks;
	string MessageText;
	bool QuitArmed;
	bool PaletteVisible;
	int64 AnimationMs;
}

/// The editor; a handle (copies share the state).
struct MapEditorGame
{
	EditorValues[] _s;
	MapDocument Document;
	EditorPalette Palette;
	TileImages Images;
	List<EditorButton> Buttons;
	List<Swatch> Swatches;
	/// The index of the collision layer, or -1.
	int CollisionLayer;
	/// The first ID of the collision tileset (the marker the collision layer is painted with), or 0.
	uint32 CollisionGid;
	/// The layers hidden with Shift+number.
	Dictionary<int, bool> HiddenLayers;
	/// The layers the view does not draw (the hidden ones and the collision layer while it is not shown).
	Dictionary<int, bool> ViewHidden;
	/// The grid lines and the cursor outline of the last update.
	List<DrawItem> Overlay;
	/// The texts of the last update (title, panel texts, status line, message).
	List<DrawItem> Texts;

	bool QuitRequested()
	{
		return _s[0].QuitRequested;
	}

	EditorTool Tool()
	{
		return _s[0].Tool;
	}

	static Error<MapEditorGame> Load(LaunchOptions options)
	{
		var document = try MapDocument.Open(ResolveTarget(options.EditTarget));
		var map = document.Map;
		int collisionLayer = -1;

		for (var i = 0; i < map.Layers.Count(); i += 1)
		{
			if (map.Layers.Get(i).Name.ToLower() == "collision")
			{
				collisionLayer = i;

				break;
			}
		}

		uint32 collisionGid = 0;

		foreach (var reference in map.Tilesets)
		{
			if (reference.Tileset.Name.ToLower().Contains("collision"))
			{
				collisionGid = (uint32)reference.FirstGid;

				break;
			}
		}

		// the ground terrain comes from the wang tileset (terrain brush); the collision marker has its own layer. A wang
		// tileset which is not installed has no wang set, it is recognized by its name then.
		var paletteTilesets = List<TiledTilesetReference>.Create();

		for (var i = 0; i < map.Tilesets.Count(); i += 1)
		{
			var reference = map.Tilesets.Get(i);
			string name = reference.Tileset.Name.ToLower();
			bool wangTileset = i == document.WangIndex || (reference.Tileset.Missing && name.Contains("wang"));

			if (!wangTileset && !name.Contains("collision"))
				paletteTilesets.Add(reference);
		}

		var state = new EditorValues[1];

		state[0].Tool = EditorTool.Paint;
		state[0].TerrainColor = 2;
		state[0].BrushSize = 1;
		state[0].ShowGrid = true;
		state[0].MessageText = "";
		state[0].PaletteVisible = true;

		var editor = MapEditorGame
		{
			_s = state, Document = document, Palette = EditorPalette.Create(paletteTilesets, PanelX + 4, TopBar + 24, PanelWidth - 8, MapViewHeight - 24 - 46),
			Images = TileImages.Create(map), Buttons = List<EditorButton>.Create(), Swatches = List<Swatch>.Create(), CollisionLayer = collisionLayer,
			CollisionGid = collisionGid, HiddenLayers = Dictionary<int, bool>.Create(), ViewHidden = Dictionary<int, bool>.Create(), Overlay = List<DrawItem>.Create(),
			Texts = List<DrawItem>.Create()
		};

		if (collisionLayer >= 0)
			editor.SetLayerVisible(collisionLayer, false);

		editor.BuildInterface();
		editor.ShowMessage("Editing " + document.Name() + ": WASD scroll, right click picks a tile, Ctrl+S saves", 400);

		return editor;
	}

	void BuildInterface()
	{
		var map = Document.Map;

		// row 1: layers and view options
		int x = 4;

		for (var i = 0; i < map.Layers.Count() && i < 9; i += 1)
			x = AddButton(EditorButton.Create("" + (i + 1) + " " + map.Layers.Get(i).Name, x, 2, ButtonAction.Layer, i, ButtonGroup.Always, 0), x);

		x += 8;
		x = AddButton(EditorButton.Create("Grid", x, 2, ButtonAction.Grid, 0, ButtonGroup.Always, 0), x);
		x = AddButton(EditorButton.Create("Collision", x, 2, ButtonAction.Collision, 0, ButtonGroup.Always, 0), x);

		// row 2: tools, history, save
		x = 4;
		x = AddButton(EditorButton.Create("Paint", x, 17, ButtonAction.Tool, (int)EditorTool.Paint, ButtonGroup.Always, 0), x);
		x = AddButton(EditorButton.Create("Terrain", x, 17, ButtonAction.Tool, (int)EditorTool.Terrain, ButtonGroup.Always, 0), x);
		x = AddButton(EditorButton.Create("Erase", x, 17, ButtonAction.Tool, (int)EditorTool.Erase, ButtonGroup.Always, 0), x);
		x = AddButton(EditorButton.Create("Pick", x, 17, ButtonAction.Tool, (int)EditorTool.Pick, ButtonGroup.Always, 0), x);
		x += 8;
		x = AddButton(EditorButton.Create("Undo", x, 17, ButtonAction.Undo, 0, ButtonGroup.Always, 0), x);
		x = AddButton(EditorButton.Create("Redo", x, 17, ButtonAction.Redo, 0, ButtonGroup.Always, 0), x);
		x = AddButton(EditorButton.Create("Save", x, 17, ButtonAction.Save, 0, ButtonGroup.Always, 0), x);

		// side panel: tile tools
		int panelInner = PanelWidth - 8;

		Buttons.Add(EditorButton.Create("<", PanelX + 4, TopBar + 4, ButtonAction.Tileset, -1, ButtonGroup.Tiles, 16));
		Buttons.Add(EditorButton.Create(">", PanelX + PanelWidth - 20, TopBar + 4, ButtonAction.Tileset, 1, ButtonGroup.Tiles, 16));

		// side panel: terrain tools
		if (Document.Wang() is WangSet wang)
		{
			for (var i = 0; i < wang.ColorNames.Count(); i += 1)
			{
				int y = TopBar + 24 + i * 18;
				string name = wang.ColorNames.Get(i);

				Buttons.Add(EditorButton.Create(name, PanelX + 4, y, ButtonAction.TerrainColor, i + 1, ButtonGroup.Terrain, panelInner));
				Swatches.Add(Swatch { Name = name, Color = SwatchColor(name), X = PanelX + 8, Y = y + 2 });
			}

			for (var size = 1; size <= 3; size += 1)
			{
				Buttons.Add(EditorButton.Create("Brush " + size, PanelX + 4 + (size - 1) * 68, TopBar + 24 + wang.ColorNames.Count() * 18 + 8, ButtonAction.Brush, size,
					ButtonGroup.Terrain, 64));
			}
		}
	}

	int AddButton(EditorButton button, int x)
	{
		Buttons.Add(button);

		return x + button.Width + 4;
	}

	bool CollisionSelected()
	{
		return CollisionLayer >= 0 && _s[0].LayerIndex == CollisionLayer;
	}

	TiledLayer CurrentLayer()
	{
		return Document.Map.Layers.Get(_s[0].LayerIndex);
	}

	void SelectLayer(int index)
	{
		_s[0].LayerIndex = Clamp(index, 0, Document.Map.Layers.Count() - 1);

		// the collision layer is shown while it is being edited
		if (CollisionSelected())
			SetCollisionVisible(true);
	}

	void ToggleCollision()
	{
		SetCollisionVisible(!_s[0].ShowCollision);
	}

	void SetCollisionVisible(bool visible)
	{
		_s[0].ShowCollision = visible;

		if (CollisionLayer >= 0)
			SetLayerVisible(CollisionLayer, visible);
	}

	void SetLayerVisible(int layer, bool visible)
	{
		if (visible)
			ViewHidden.Remove(layer);
		else
			ViewHidden.Set(layer, true);
	}

	void SetTool(EditorTool tool)
	{
		_s[0].Tool = tool;

		// the terrain brush always works on the ground layer
		if (tool == EditorTool.Terrain)
			_s[0].LayerIndex = Document.Ground;
	}

	void Undo()
	{
		Document.Undo();
	}

	void Redo()
	{
		Document.Redo();
	}

	Error<void> Save()
	{
		try Document.Save();
		ShowMessage("Saved " + System.Path.GetFileName(Document.Path) + " (backup: .bak)", 200);
		_s[0].QuitArmed = false;

		return;
	}

	void ShowMessage(string text, int ticks)
	{
		_s[0].MessageTicks = ticks;
		_s[0].MessageText = text;
	}

	Error<void> Click(EditorButton button)
	{
		var action = button.Action;

		if (action == ButtonAction.Layer)
			SelectLayer(button.Argument);
		else if (action == ButtonAction.Grid)
			_s[0].ShowGrid = !_s[0].ShowGrid;
		else if (action == ButtonAction.Collision)
			ToggleCollision();
		else if (action == ButtonAction.Tool)
			SetTool((EditorTool)button.Argument);
		else if (action == ButtonAction.Undo)
			Undo();
		else if (action == ButtonAction.Redo)
			Redo();
		else if (action == ButtonAction.Save)
			try Save();
		else if (action == ButtonAction.Tileset)
			Palette.SelectTileset(button.Argument);
		else if (action == ButtonAction.TerrainColor)
			_s[0].TerrainColor = button.Argument;
		else if (action == ButtonAction.Brush)
			_s[0].BrushSize = button.Argument;

		return;
	}

	bool IsActive(EditorButton button)
	{
		var action = button.Action;

		if (action == ButtonAction.Layer)
			return _s[0].LayerIndex == button.Argument;

		if (action == ButtonAction.Grid)
			return _s[0].ShowGrid;

		if (action == ButtonAction.Collision)
			return _s[0].ShowCollision;

		if (action == ButtonAction.Tool)
			return (int)_s[0].Tool == button.Argument;

		if (action == ButtonAction.TerrainColor)
			return _s[0].TerrainColor == button.Argument;

		if (action == ButtonAction.Brush)
			return _s[0].BrushSize == button.Argument;

		return false;
	}

	bool IsEnabled(EditorButton button)
	{
		if (button.Action == ButtonAction.Undo)
			return Document.CanUndo();

		if (button.Action == ButtonAction.Redo)
			return Document.CanRedo();

		if (button.Action == ButtonAction.Save)
			return Document.Dirty();

		return true;
	}

	Error<void> Update(InputState input)
	{
		int mouseX = input.MouseX();
		int mouseY = input.MouseY();
		bool overMap = mouseX < MapViewWidth && mouseY >= TopBar && mouseY < TopBar + MapViewHeight;
		bool control = input.IsDown(Key.ControlLeft) || input.IsDown(Key.ControlRight);
		bool shift = input.IsDown(Key.ShiftLeft) || input.IsDown(Key.ShiftRight);

		try HandleKeys(input, control, shift);

		// buttons and palette
		bool consumed = false;
		var hovering = new bool[Buttons.Count()];

		for (var i = 0; i < Buttons.Count(); i += 1)
		{
			var button = Buttons.Get(i);

			hovering[i] = button.Contains(mouseX, mouseY);

			if (hovering[i] && input.MousePressed(MouseButton.Left) && IsEnabled(button))
			{
				try Click(button);
				consumed = true;
			}
		}

		bool paletteVisible = _s[0].Tool != EditorTool.Terrain && !CollisionSelected();

		Palette.SetVisible(paletteVisible);
		_s[0].PaletteVisible = paletteVisible;

		if (paletteVisible && Palette.Contains(mouseX, mouseY))
		{
			if (input.MousePressed(MouseButton.Left) && Palette.TryPick(mouseX, mouseY))
				consumed = true;

			if (input.Wheel() != 0.0f)
				Palette.Scroll(-RoundHalfEven((double)input.Wheel()) * 2);
		}

		for (var i = 0; i < Buttons.Count(); i += 1)
		{
			var button = Buttons.Get(i);

			if (button.Group == ButtonGroup.Tiles)
				button.Visible = paletteVisible;
			else if (button.Group == ButtonGroup.Terrain)
				button.Visible = !paletteVisible;

			button.Hover = hovering[i];
			button.Active = IsActive(button);
			button.Enabled = IsEnabled(button);
			Buttons.Set(i, button);
		}

		if (overMap && !consumed)
			HandleMap(input, mouseX, mouseY);
		else if (input.MouseReleased(MouseButton.Left) || (!input.MouseIsDown(MouseButton.Left) && _s[0].Painting))
			EndStroke();

		HandleCamera(input, shift, overMap);
		_s[0].AnimationMs += 20;
		Palette.Update();
		UpdateOverlay(mouseX, mouseY, overMap);
		UpdateTexts(mouseX, mouseY, overMap);

		return;
	}

	Error<void> HandleKeys(InputState input, bool control, bool shift)
	{
		if (input.Pressed(Key.Escape))
		{
			if (!Document.Dirty() || _s[0].QuitArmed)
			{
				_s[0].QuitRequested = true;

				return;
			}

			_s[0].QuitArmed = true;
			ShowMessage("Unsaved changes: Esc again to quit without saving, Ctrl+S to save.", 300);
		}

		if (control && input.Pressed(Key.S))
			try Save();
		else if (control && input.Pressed(Key.Z))
			Undo();
		else if (control && input.Pressed(Key.Y))
			Redo();

		if (control)
			return;

		if (input.Pressed(Key.B))
			SetTool(EditorTool.Paint);
		else if (input.Pressed(Key.T))
			SetTool(EditorTool.Terrain);
		else if (input.Pressed(Key.E))
			SetTool(EditorTool.Erase);
		else if (input.Pressed(Key.I))
			SetTool(EditorTool.Pick);
		else if (input.Pressed(Key.G))
			_s[0].ShowGrid = !_s[0].ShowGrid;
		else if (input.Pressed(Key.C))
			ToggleCollision();
		else if (input.Pressed(Key.LeftBracket))
			Palette.SelectTileset(-1);
		else if (input.Pressed(Key.RightBracket))
			Palette.SelectTileset(1);
		else if (input.Pressed(Key.PageUp))
			Palette.Scroll(-6);
		else if (input.Pressed(Key.PageDown))
			Palette.Scroll(6);

		for (var i = 0; i < 9 && i < Document.Map.Layers.Count(); i += 1)
		{
			if (!input.Pressed((Key)((int)Key.Number1 + i)))
				continue;

			if (shift)
				ToggleLayerVisibility(i);
			else
				SelectLayer(i);
		}

		return;
	}

	void ToggleLayerVisibility(int layer)
	{
		bool hide = !HiddenLayers.ContainsKey(layer);

		if (hide)
			HiddenLayers.Set(layer, true);
		else
			HiddenLayers.Remove(layer);

		if (layer == CollisionLayer)
			_s[0].ShowCollision = !hide;

		SetLayerVisible(layer, !hide);
		ShowMessage("Layer " + Document.Map.Layers.Get(layer).Name + " " + (hide ? "hidden" : "shown"), 200);
	}

	void HandleCamera(InputState input, bool shift, bool overMap)
	{
		int speed = shift ? 8 : 3;

		if (input.IsDown(Key.W) || input.IsDown(Key.Up))
			_s[0].CameraY -= speed;

		if (input.IsDown(Key.S) || input.IsDown(Key.Down))
			_s[0].CameraY += speed;

		if (input.IsDown(Key.A) || input.IsDown(Key.Left))
			_s[0].CameraX -= speed;

		if (input.IsDown(Key.D) || input.IsDown(Key.Right))
			_s[0].CameraX += speed;

		if (overMap && input.Wheel() != 0.0f)
		{
			if (shift)
				_s[0].CameraX -= RoundHalfEven((double)input.Wheel()) * 32;
			else
				_s[0].CameraY -= RoundHalfEven((double)input.Wheel()) * 32;
		}

		_s[0].CameraX = Clamp(_s[0].CameraX, 0, Max(0, Document.Map.Width * EditorTileSize - MapViewWidth));
		_s[0].CameraY = Clamp(_s[0].CameraY, 0, Max(0, Document.Map.Height * EditorTileSize - MapViewHeight));
	}

	EditorCell CellAt(int mouseX, int mouseY)
	{
		return EditorCell.Of((mouseX + _s[0].CameraX) / EditorTileSize, (mouseY - TopBar + _s[0].CameraY) / EditorTileSize);
	}

	EditorCell VertexAt(int mouseX, int mouseY)
	{
		return EditorCell.Of(RoundHalfEven((double)(mouseX + _s[0].CameraX) / (double)EditorTileSize),
			RoundHalfEven((double)(mouseY - TopBar + _s[0].CameraY) / (double)EditorTileSize));
	}

	void HandleMap(InputState input, int mouseX, int mouseY)
	{
		var cell = CellAt(mouseX, mouseY);
		var vertex = VertexAt(mouseX, mouseY);

		if (input.MousePressed(MouseButton.Right))
		{
			Pick(cell);

			return;
		}

		bool pressed = input.MousePressed(MouseButton.Left);
		bool held = input.MouseIsDown(MouseButton.Left) || pressed;

		if (pressed)
		{
			_s[0].Painting = true;
			_s[0].HasLastCell = false;
			_s[0].HasLastVertex = false;
			Document.BeginStroke();
		}

		if (_s[0].Painting && held)
		{
			if (_s[0].Tool == EditorTool.Terrain)
			{
				if (!_s[0].HasLastVertex || !_s[0].LastVertex.Same(vertex))
				{
					_s[0].HasLastVertex = true;
					_s[0].LastVertex = vertex;

					string problem = Document.PaintTerrain(vertex.X, vertex.Y, _s[0].TerrainColor, _s[0].BrushSize);

					if (problem != null)
						ShowMessage(problem, 250);
				}
			}
			else if (!_s[0].HasLastCell || !_s[0].LastCell.Same(cell))
			{
				_s[0].HasLastCell = true;
				_s[0].LastCell = cell;
				ApplyToCell(cell);
			}
		}

		if (input.MouseReleased(MouseButton.Left) || (_s[0].Painting && !input.MouseIsDown(MouseButton.Left) && !pressed))
			EndStroke();
	}

	void EndStroke()
	{
		Document.EndStroke();
		_s[0].Painting = false;
	}

	void ApplyToCell(EditorCell cell)
	{
		int layer = _s[0].LayerIndex;
		var tool = _s[0].Tool;

		if (tool == EditorTool.Paint)
		{
			uint32 gid = CollisionSelected() ? CollisionGid : (uint32)Palette.SelectedGid();

			if (gid != 0)
				Document.SetTile(layer, cell.X, cell.Y, gid);
		}
		else if (tool == EditorTool.Erase)
		{
			if (Document.FindTileAt(layer, cell.X, cell.Y) is EditorCell anchor)
				Document.SetTile(layer, anchor.X, anchor.Y, 0);
		}
		else if (tool == EditorTool.Pick)
			Pick(cell);
	}

	void Pick(EditorCell cell)
	{
		if (CollisionSelected())
			return;

		// the tile under the mouse on the selected layer, else on the layers above (objects are drawn over the ground)
		for (var index = _s[0].LayerIndex; index < Document.Map.Layers.Count(); index += 1)
		{
			if (index == CollisionLayer)
				continue;

			if (Document.FindTileAt(index, cell.X, cell.Y) is EditorCell anchor)
			{
				var layer = Document.Map.Layers.Get(index);
				int gid = (int)GidOf(layer.Get(anchor.X, anchor.Y));

				if (gid != 0 && Palette.HasTilesets())
				{
					Palette.Select(gid);
					_s[0].LayerIndex = index;
					_s[0].Tool = EditorTool.Paint;
					ShowMessage("Picked tile " + gid + " from " + layer.Name, 200);
				}

				return;
			}
		}
	}

	/// Size in cells of the tile that would be placed (for the cursor outline).
	EditorCell StampSize()
	{
		if (_s[0].Tool != EditorTool.Paint || CollisionSelected())
			return EditorCell.Of(1, 1);

		if (Document.Map.FindTileset(Palette.SelectedGid()) is TiledTilesetReference reference)
			return EditorCell.Of((reference.Tileset.TileWidth + EditorTileSize - 1) / EditorTileSize, (reference.Tileset.TileHeight + EditorTileSize - 1) / EditorTileSize);

		return EditorCell.Of(1, 1);
	}

	void UpdateOverlay(int mouseX, int mouseY, bool overMap)
	{
		Overlay.Clear();
		UpdateGrid();

		int x = 0;
		int y = 0;
		int width = EditorTileSize;
		int height = EditorTileSize;

		if (overMap && _s[0].Tool == EditorTool.Terrain)
		{
			var vertex = VertexAt(mouseX, mouseY);
			int brush = _s[0].BrushSize;
			int size = brush * EditorTileSize;

			x = vertex.X * EditorTileSize - _s[0].CameraX - (brush / 2) * EditorTileSize - 2;
			y = TopBar + vertex.Y * EditorTileSize - _s[0].CameraY - (brush / 2) * EditorTileSize - 2;
			width = size + 4;
			height = size + 4;
		}
		else if (overMap)
		{
			var cell = CellAt(mouseX, mouseY);
			var stamp = StampSize();

			x = cell.X * EditorTileSize - _s[0].CameraX;
			y = TopBar + (cell.Y - stamp.Y + 1) * EditorTileSize - _s[0].CameraY;
			width = stamp.X * EditorTileSize;
			height = stamp.Y * EditorTileSize;
		}

		// keep the outline out of the bars
		int top = Max(y, TopBar);

		if (!overMap || y + height <= TopBar || x >= MapViewWidth)
			return;

		int clippedHeight = y + height - top;

		PlaceCursor(x, top, width, 1, y >= TopBar);
		PlaceCursor(x, y + height - 1, width, 1, true);
		PlaceCursor(x, top, 1, clippedHeight, true);
		PlaceCursor(x + width - 1, top, 1, clippedHeight, true);
	}

	void PlaceCursor(int x, int y, int width, int height, bool visible)
	{
		if (!visible)
			return;

		int clippedWidth = Min(width, MapViewWidth - x);

		Overlay.Add(RectItem(DrawPlane.Panels, 30, x, y, Max(1, clippedWidth), height, Color.Of(255, 230, 90)));
	}

	void UpdateGrid()
	{
		if (!_s[0].ShowGrid)
			return;

		int cameraX = _s[0].CameraX;
		int cameraY = _s[0].CameraY;
		int mapPixelWidth = Document.Map.Width * EditorTileSize;
		int mapPixelHeight = Document.Map.Height * EditorTileSize;
		int right = Min(MapViewWidth, mapPixelWidth - cameraX);
		int bottom = Min(TopBar + MapViewHeight, TopBar + mapPixelHeight - cameraY);
		var color = Color.OfAlpha(255, 255, 255, 56);

		for (var gx = cameraX / EditorTileSize; gx * EditorTileSize - cameraX < right; gx += 1)
		{
			int x = gx * EditorTileSize - cameraX;

			if (x >= 0)
				Overlay.Add(RectItem(DrawPlane.Panels, 6, x, TopBar, 1, bottom - TopBar, color));
		}

		for (var gy = cameraY / EditorTileSize; TopBar + gy * EditorTileSize - cameraY < bottom; gy += 1)
		{
			int y = TopBar + gy * EditorTileSize - cameraY;

			if (y >= TopBar)
				Overlay.Add(RectItem(DrawPlane.Panels, 6, 0, y, right, 1, color));
		}
	}

	void UpdateTexts(int mouseX, int mouseY, bool overMap)
	{
		Texts.Clear();

		string title = Document.Name() + (Document.Dirty() ? " *" : "");

		Texts.Add(TextItem(60, title, EditorWidth - 4 - TextLength(title) * CellWidth, 6, TextColor.Cyan));

		if (_s[0].Tool == EditorTool.Terrain)
		{
			Texts.Add(TextItem(60, "Terrain brush (ground)", PanelX + 8, TopBar + 6, TextColor.Yellow));
			Texts.Add(TextItem(60, "Left: paint the terrain\nBrush 1-3: size\nOnly terrains which have\ntransition tiles can touch.\nT: terrain  B: tiles", PanelX + 8,
				TopBar + MapViewHeight - 62, TextColor.Gray));
		}
		else if (CollisionSelected())
		{
			Texts.Add(TextItem(60, "Collision (blocked cells)", PanelX + 8, TopBar + 7, TextColor.Yellow));
			Texts.Add(TextItem(60, "Paint: block a cell\nErase: unblock it\nC: show or hide the red\ncells. 1-4: other layers", PanelX + 8, TopBar + 24, TextColor.Gray));
		}
		else
		{
			string tilesetName = Palette.TilesetName();

			Texts.Add(TextItem(60, TextLength(tilesetName) > 26 ? TextPrefix(tilesetName, 26) : tilesetName, PanelX + 24, TopBar + 7, TextColor.Yellow));
			Texts.Add(TextItem(60, "Layer " + (_s[0].LayerIndex + 1) + ": " + CurrentLayer().Name + "\nWheel: scroll  [ ]: tileset\nRight click: pick tile", PanelX + 8,
				TopBar + MapViewHeight - 42, TextColor.Gray));
		}

		if (_s[0].MessageTicks > 0)
		{
			_s[0].MessageTicks -= 1;

			if (_s[0].MessageTicks == 0)
				_s[0].MessageText = "";
		}

		string left = "";

		if (overMap)
		{
			var cell = CellAt(mouseX, mouseY);
			var parts = List<string>.Create();

			foreach (var layer in Document.Map.Layers)
				parts.Add(TextPrefix(layer.Name, 1) + ":" + GidOf(layer.Get(cell.X, cell.Y)));

			left = "" + cell.X + "," + cell.Y + "  " + JoinList(" ", parts);
		}

		Texts.Add(TextItem(60, left, 4, EditorHeight - StatusBar + 4, TextColor.White));

		if (_s[0].MessageTicks > 0)
		{
			string message = _s[0].MessageText;
			int textWidth = TextLength(message) * CellWidth;

			Texts.Add(TextItem(60, message, Max(150, EditorWidth - 4 - textWidth), EditorHeight - StatusBar + 4, TextColor.Yellow));
		}
	}

	void Draw(DrawList list)
	{
		var map = Document.Map;

		DrawTileMap(list, map, Images, ViewHidden, CollisionLayer, _s[0].CameraX, _s[0].CameraY - TopBar, MapViewWidth, MapViewHeight + TopBar, _s[0].AnimationMs);

		// the bars and the side panel
		var frames = List<DrawItem>.Create();

		EditorFrame(frames, 0, 0, EditorWidth, TopBar);
		EditorFrame(frames, PanelX, TopBar, PanelWidth, MapViewHeight);
		EditorFrame(frames, 0, EditorHeight - StatusBar, EditorWidth, StatusBar);
		list.AddAll(frames);
		list.AddAll(Overlay);
		Palette.Draw(list, Images);

		foreach (var button in Buttons)
			button.Draw(list);

		if (!_s[0].PaletteVisible)
		{
			foreach (var swatch in Swatches)
				list.Add(RectItem(DrawPlane.Panels, 46, swatch.X, swatch.Y, 20, 10, swatch.Color));
		}

		list.AddAll(Texts);
	}

	/// Commands of input scripts: select, tool, layer, camera, terrain, expect.
	Error<void> Debug(string command)
	{
		var parts = SplitWhitespace(command);

		if (parts.Length == 0)
			return;

		if (parts[0] == "select")
			Palette.Select(try DebugNumber(parts, 1));
		else if (parts[0] == "tool")
		{
			string name = (try DebugText(parts, 1)).ToLower();

			if (name == "paint")
				SetTool(EditorTool.Paint);
			else if (name == "terrain")
				SetTool(EditorTool.Terrain);
			else if (name == "erase")
				SetTool(EditorTool.Erase);
			else if (name == "pick")
				SetTool(EditorTool.Pick);
			else
				return error("Unknown tool '" + parts[1] + "'.", (int)ErrorKind.Argument);
		}
		else if (parts[0] == "layer")
			SelectLayer(try DebugNumber(parts, 1) - 1);
		else if (parts[0] == "camera")
		{
			_s[0].CameraX = try DebugNumber(parts, 1);
			_s[0].CameraY = try DebugNumber(parts, 2);
		}
		else if (parts[0] == "terrain")
			_s[0].TerrainColor = try DebugNumber(parts, 1);
		else if (parts[0] == "expect")
			try Expect(parts, command);

		return;
	}

	Error<void> Expect(string[] parts, string command)
	{
		string what = try DebugText(parts, 1);
		string actual = "";
		string expected = "";

		if (what == "tile" || what == "file")
		{
			// "file": the saved file, read again
			var map = Document.Map;

			if (what == "file")
				map = try TiledLoader.Load(Document.Path);

			int layer = try DebugNumber(parts, 2) - 1;

			if (layer < 0 || layer >= map.Layers.Count())
				return error("There is no layer " + (layer + 1) + ": " + command, (int)ErrorKind.Argument);

			actual = "" + GidOf(map.Layers.Get(layer).Get(try DebugNumber(parts, 3), try DebugNumber(parts, 4)));
			expected = try DebugText(parts, 5);
		}
		else if (what == "fileobjects")
		{
			// the number of points and shapes in the object layers of the saved file
			var saved = try TiledLoader.Load(Document.Path);
			int count = 0;

			foreach (var objectLayer in saved.ObjectLayers)
				count += objectLayer.Objects.Count();

			actual = "" + count;
			expected = try DebugText(parts, 2);
		}
		else if (what == "vertex")
		{
			int x = try DebugNumber(parts, 2);
			int y = try DebugNumber(parts, 3);

			if (x < 0 || y < 0 || x > Document.Map.Width || y > Document.Map.Height)
				return error("The vertex is outside the map: " + command, (int)ErrorKind.Argument);

			actual = "" + Document.Vertex(x, y);
			expected = try DebugText(parts, 4);
		}
		else if (what == "dirty")
		{
			actual = Document.Dirty() ? "1" : "0";
			expected = try DebugText(parts, 2);
		}
		else if (what == "tool")
		{
			actual = ToolName(_s[0].Tool);
			expected = try DebugText(parts, 2);
		}
		else if (what == "layer")
		{
			actual = "" + (_s[0].LayerIndex + 1);
			expected = try DebugText(parts, 2);
		}
		else if (what == "selected")
		{
			actual = "" + Palette.SelectedGid();
			expected = try DebugText(parts, 2);
		}
		else
			return error("Unknown expectation '" + command + "'.", (int)ErrorKind.InvalidOperation);

		if (actual != expected)
			return error("Expectation failed: " + command + " (actual: " + actual + ")", (int)ErrorKind.InvalidOperation);

		Console.WriteLine("ok: " + command);

		return;
	}
}

string ToolName(EditorTool tool)
{
	if (tool == EditorTool.Terrain)
		return "terrain";

	if (tool == EditorTool.Erase)
		return "erase";

	if (tool == EditorTool.Pick)
		return "pick";

	return "paint";
}

/// A bordered bar of the editor (C#: Frame on display layer 2).
void EditorFrame(List<DrawItem> items, int x, int y, int width, int height)
{
	items.Add(RectItem(DrawPlane.Panels, 2, x, y, width, height, UiBorder));
	items.Add(RectItem(DrawPlane.Panels, 3, x + 2, y + 2, width - 4, height - 4, UiBackground));
}

/// Rounds to the nearest whole number, halves to the even one (C#: Math.Round).
int RoundHalfEven(double value)
{
	int result = (int)value;

	// (int) cuts towards zero: step down to the next lower whole number for negative values
	if ((double)result > value)
		result -= 1;

	double fraction = value - (double)result;

	if (fraction > 0.5 || (fraction == 0.5 && result % 2 != 0))
		result += 1;

	return result;
}

/// The first map of content/maps (by name), "" if there is none.
string FirstMapName()
{
	foreach (var entry in Directory.GetEntries(Path.Combine(DefaultContent(), "maps")))
	{
		if (entry.EndsWith(".tmx") && !entry.StartsWith("edit_test"))
			return entry.Substring(0, entry.Length - 4);
	}

	return "";
}

/// The map file to edit: a TMX path, or a name of content/maps (default: the first map there).
string ResolveTarget(string target)
{
	string name = target != null ? target : FirstMapName();

	if (name.ToLower().EndsWith(".tmx") || File.Exists(name))
		return name;

	return Path.Combine(Path.Combine(DefaultContent(), "maps"), name + ".tmx");
}
