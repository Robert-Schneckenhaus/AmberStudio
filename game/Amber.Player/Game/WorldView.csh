namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Game.Ui;
using Amber.Player.Graphics;
using Amber.Player.Tiled;

/// How a tile layer is drawn relative to the actors.
enum LayerRole : int32
{
	/// Behind everything (ground).
	Ground,
	/// Flat decoration on top of the ground, still behind everything else.
	Decor,
	/// Sorted with the actors by the bottom edge of each tile (trees, rocks, bushes).
	Objects,
	/// In front of the actors (canopy).
	Over,
	/// Not drawn (collision data).
	Hidden
}

LayerRole RoleOf(TiledLayer layer)
{
	if (layer.Properties.TryGet("role") is string role)
	{
		string value = role.ToLower();

		if (value == "ground")
			return LayerRole.Ground;

		if (value == "decor")
			return LayerRole.Decor;

		if (value == "objects")
			return LayerRole.Objects;

		if (value == "over")
			return LayerRole.Over;

		if (value == "hidden")
			return LayerRole.Hidden;
	}

	string name = layer.Name.ToLower();

	if (name.Contains("collision") || !layer.Visible)
		return LayerRole.Hidden;

	if (name.Contains("decor"))
		return LayerRole.Decor;

	if (name.Contains("over"))
		return LayerRole.Over;

	if (name.Contains("object"))
		return LayerRole.Objects;

	return LayerRole.Ground;
}

/// Objects in the same row get an extra sorting offset by their order in the row, below the actors' 8.
const int MaxRowOrder = 7;

/// Draws the visible part of a Tiled map (C#: TileMapView): ground and decor tiles on their own planes, objects and canopy
/// on the world plane where they are sorted with the actors by their bottom edge. Hidden layers (SetLayerVisible, the
/// editor) are not drawn; the layer overLayer (or -1) is drawn as canopy whatever its role (the editor's collision layer).
void DrawTileMap(DrawList list, TiledMap map, TileImages images, Dictionary<int, bool> hiddenLayers, int overLayer, int cameraX, int cameraY, int viewWidth, int viewHeight,
	int64 animationMs)
{
	DrawTiles(list, map, images, hiddenLayers, overLayer, cameraX, cameraY, viewWidth, viewHeight, animationMs, false, new MapLook());
}

/// The same with palette pictures (the game): the tiles are drawn with the colors of the map's look.
void DrawTiles(DrawList list, TiledMap map, TileImages images, Dictionary<int, bool> hiddenLayers, int overLayer, int cameraX, int cameraY, int viewWidth, int viewHeight,
	int64 animationMs, bool indexed, MapLook look)
{
	int tileWidth = map.TileWidth;
	int tileHeight = map.TileHeight;
	int biggestWidth = tileWidth;
	int biggestHeight = tileHeight;

	foreach (var reference in map.Tilesets)
	{
		biggestWidth = Max(biggestWidth, reference.Tileset.TileWidth);
		biggestHeight = Max(biggestHeight, reference.Tileset.TileHeight);
	}

	// the biggest tile decides how far cells outside the view can still reach into it: tiles are anchored at their bottom
	// left cell and extend up and to the right
	int extraColumns = (biggestWidth + tileWidth - 1) / tileWidth - 1;
	int extraRows = (biggestHeight + tileHeight - 1) / tileHeight - 1;
	int firstColumn = Max(0, cameraX / tileWidth - extraColumns);
	int firstRow = Max(0, cameraY / tileHeight);
	int lastColumn = Min(map.Width - 1, (cameraX + viewWidth) / tileWidth);
	int lastRow = Min(map.Height - 1, (cameraY + viewHeight) / tileHeight + extraRows);

	if (lastRow < firstRow)
		return;

	// Objects in the same row have the same bottom edge. So that they are drawn like in the map editor (the one further right
	// in front), each gets a small extra offset by its order in the row.
	var objectsInRow = new int[lastRow - firstRow + 1];

	for (var layerIndex = 0; layerIndex < map.Layers.Count(); layerIndex += 1)
	{
		var layer = map.Layers.Get(layerIndex);
		var role = layerIndex == overLayer ? LayerRole.Over : RoleOf(layer);

		if (role == LayerRole.Hidden || hiddenLayers.ContainsKey(layerIndex))
			continue;

		var plane = role == LayerRole.Ground ? DrawPlane.Ground : role == LayerRole.Decor ? DrawPlane.Decor : DrawPlane.World;

		for (var row = firstRow; row <= lastRow; row += 1)
		{
			for (var column = firstColumn; column <= lastColumn; column += 1)
			{
				uint32 raw = layer.Get(column, row);

				if (GidOf(raw) == 0)
					continue;

				uint32 frameRaw = images.CurrentFrame(raw, animationMs);
				var picture = images.Get(frameRaw, (int)role);

				if (picture.IsEmpty())
					continue;

				int x = column * tileWidth - cameraX;
				int y = (row + 1) * tileHeight - picture.Height - cameraY;
				int baseLine = 0;

				if (role == LayerRole.Over)
					baseLine = 1000;
				else if (role == LayerRole.Objects)
				{
					baseLine = Min(objectsInRow[row - firstRow], MaxRowOrder);
					objectsInRow[row - firstRow] += 1;
				}

				int layerValue = plane == DrawPlane.World ? y + picture.Height + baseLine : 0;

				if (indexed)
					list.Add(IndexedItem(plane, layerValue, look.TileIndices(frameRaw, (int)role, picture), picture.Width, picture.Height, look.Active, x, y));
				else
					list.Add(PictureItem(plane, layerValue, picture, x, y, 0, 0));
			}
		}
	}
}

struct ViewValues
{
	int CameraX;
	int CameraY;
	int64 AnimationMs;
	bool HasWorld;
	MapRuntime Map;
	/// The 3D view: the party's position in cells (fixed point) and its angle, and the cell, facing and map they belong to
	/// (when a script, a warp or a savegame moves the party, the view starts again in the middle of the new cell).
	int PartyX;
	int PartyY;
	int Angle;
	int SyncX;
	int SyncY;
	int SyncFacing;
	int SyncMap;
	/// The palette indices of the last 3D frame (the draw item refers to them).
	uint8[] Frame;
}

/// Draws the current world: ground, decoration, and the sorted plane with objects, actors and canopy. Follows the player.
/// A handle.
struct WorldView
{
	ViewValues[] _s;
	Dictionary<int, TileImages> _images;
	/// The shade tables of the 3D maps by map handle.
	Dictionary<int, uint8[]> _shades;
	/// The actors the 3D view neither draws nor bumps into (the companions: they are the party).
	List<Actor> _hidden;

	static WorldView Create()
	{
		var state = new ViewValues[1];

		state[0].SyncMap = -1;
		state[0].Frame = new uint8[View3DWidth * View3DHeight];

		return WorldView { _s = state, _images = Dictionary<int, TileImages>.Create(), _shades = Dictionary<int, uint8[]>.Create(), _hidden = List<Actor>.Create() };
	}

	/// True when the current map is shown from the inside.
	bool Is3D()
	{
		return _s[0].HasWorld && _s[0].Map.Settings.View3D;
	}

	int PartyX()
	{
		return _s[0].PartyX;
	}

	int PartyY()
	{
		return _s[0].PartyY;
	}

	int Angle()
	{
		return _s[0].Angle;
	}

	void SetHiddenActors(List<Actor> actors)
	{
		_hidden = actors;
	}

	bool IsHidden(Actor actor)
	{
		foreach (var hidden in _hidden)
		{
			if (hidden.Same(actor))
				return true;
		}

		return false;
	}

	/// Follows a move of the party that the view did not make (teleport, warp, set_dir, loading a game).
	void Sync3D()
	{
		var player = _s[0].Map.World.Player;

		if (player.TileX() != _s[0].SyncX || player.TileY() != _s[0].SyncY || _s[0].SyncMap != _s[0].Map.Handle)
		{
			_s[0].PartyX = player.TileX() * Fixed + Fixed / 2;
			_s[0].PartyY = player.TileY() * Fixed + Fixed / 2;
			_s[0].Angle = (int)player.Facing() * (AngleSteps / 4);
		}
		else if ((int)player.Facing() != _s[0].SyncFacing)
			_s[0].Angle = (int)player.Facing() * (AngleSteps / 4);

		Remember3D();
	}

	void Remember3D()
	{
		var player = _s[0].Map.World.Player;

		_s[0].SyncX = player.TileX();
		_s[0].SyncY = player.TileY();
		_s[0].SyncFacing = (int)player.Facing();
		_s[0].SyncMap = _s[0].Map.Handle;
	}

	/// A cell the party cannot stand in: outside the map, a wall, the collision layer or a blocking figure.
	bool Blocked3D(int x, int y)
	{
		var world = _s[0].Map.World;

		if (world.Map.IsBlocked(x, y) || GidOf(world.Map.GetTile("objects", x, y)) != 0)
			return true;

		foreach (var actor in world.Actors)
		{
			if (!actor.Same(world.Player) && actor.Visible() && actor.Blocking() && !IsHidden(actor) && actor.TileX() == x && actor.TileY() == y)
				return true;
		}

		return false;
	}

	/// Whether the party (a circle of PartyRadius) fits at a point.
	bool Fits3D(int x, int y)
	{
		int left = (x - PartyRadius) >> 16;
		int right = (x + PartyRadius) >> 16;
		int top = (y - PartyRadius) >> 16;
		int bottom = (y + PartyRadius) >> 16;

		for (var cellY = top; cellY <= bottom; cellY += 1)
		{
			for (var cellX = left; cellX <= right; cellX += 1)
			{
				if (Blocked3D(cellX, cellY))
					return false;
			}
		}

		return true;
	}

	/// Walks and turns the party freely: forward and sideways in steps of 1/65536 cell, turn in angle steps. The party slides
	/// along walls (each axis on its own). Crossing into another cell moves the player actor there, which fires the triggers.
	void Move3D(int forward, int sideways, int turn)
	{
		Sync3D();

		var player = _s[0].Map.World.Player;

		_s[0].Angle = (_s[0].Angle + turn) & (AngleSteps - 1);

		int forwardX = SinOf(_s[0].Angle);
		int forwardY = -CosOf(_s[0].Angle);
		int moveX = FixMul(forwardX, forward) - FixMul(forwardY, sideways);
		int moveY = FixMul(forwardY, forward) + FixMul(forwardX, sideways);

		if (moveX != 0 && Fits3D(_s[0].PartyX + moveX, _s[0].PartyY))
			_s[0].PartyX += moveX;

		if (moveY != 0 && Fits3D(_s[0].PartyX, _s[0].PartyY + moveY))
			_s[0].PartyY += moveY;

		int cellX = _s[0].PartyX >> 16;
		int cellY = _s[0].PartyY >> 16;

		if (cellX != player.TileX() || cellY != player.TileY())
			player.MoveToCell(cellX, cellY);

		player.SetFacing((Direction)(((_s[0].Angle + AngleSteps / 8) / (AngleSteps / 4)) & 3));
		Remember3D();
	}

	/// The cell the party looks at, for examine, speak and interact: the next cell along the view.
	TilePoint CellAhead()
	{
		Sync3D();

		int forwardX = SinOf(_s[0].Angle);
		int forwardY = -CosOf(_s[0].Angle);
		int cellX = _s[0].PartyX >> 16;
		int cellY = _s[0].PartyY >> 16;

		for (var distance = Fixed / 2; distance <= Fixed * 5 / 4; distance += Fixed / 8)
		{
			int x = (_s[0].PartyX + FixMul(forwardX, distance)) >> 16;
			int y = (_s[0].PartyY + FixMul(forwardY, distance)) >> 16;

			if (x != cellX || y != cellY)
				return TilePoint { X = x, Y = y };
		}

		var player = _s[0].Map.World.Player;

		return TilePoint { X = cellX + DeltaX(player.Facing()), Y = cellY + DeltaY(player.Facing()) };
	}

	int CameraX()
	{
		return _s[0].CameraX;
	}

	int CameraY()
	{
		return _s[0].CameraY;
	}

	void AddWorld(MapRuntime map)
	{
		_images.Set(map.Handle, TileImages.Create(map.World.Map.Tiled));
	}

	/// The tile pictures of a map (for its palette).
	TileImages ImagesOf(MapRuntime map)
	{
		if (_images.TryGet(map.Handle) is TileImages images)
			return images;

		return TileImages.Create(map.World.Map.Tiled);
	}

	/// Shows another world.
	void SetWorld(MapRuntime map)
	{
		_s[0].HasWorld = true;
		_s[0].Map = map;
	}

	/// The tiles are read from the map every frame, so a change is visible at once (C#: redraws the tile sprites).
	void InvalidateTiles()
	{
	}

	void Update()
	{
		if (!_s[0].HasWorld)
			return;

		var world = _s[0].Map.World;
		var player = world.Player;
		var map = world.Map;

		_s[0].CameraX = Clamp(player.CenterX() - VirtualWidth / 2, 0, Max(0, map.Width() * map.TileSize() - VirtualWidth));
		_s[0].CameraY = Clamp(player.CenterY() - VirtualHeight / 2, 0, Max(0, map.Height() * map.TileSize() - VirtualHeight));
		_s[0].AnimationMs += 20;
	}

	void Draw(DrawList list)
	{
		if (!_s[0].HasWorld)
			return;

		if (Is3D())
		{
			Draw3D(list);

			return;
		}

		var runtime = _s[0].Map;
		var world = runtime.World;
		int cameraX = _s[0].CameraX;
		int cameraY = _s[0].CameraY;

		if (_images.TryGet(runtime.Handle) is TileImages images)
			DrawTiles(list, world.Map.Tiled, images, Dictionary<int, bool>.Create(), -1, cameraX, cameraY, VirtualWidth, VirtualHeight, _s[0].AnimationMs, true, runtime.Look);

		foreach (var actor in world.Actors)
		{
			if (!actor.Visible())
				continue;

			var picture = actor.CurrentImage();
			int x = actor.PixelX() - cameraX;
			int y = actor.PixelY() - cameraY;

			var indices = runtime.Look.FigureIndices(actor.Name, actor.CurrentFrameKey(), picture);

			list.Add(IndexedItem(DrawPlane.World, y + picture.Height + ActorBaseLine - actor.Art().FootMargin, indices, picture.Width, picture.Height, runtime.Look.Active, x, y));
		}
	}

	/// The 3D view: the raycaster draws the map from the party's eyes into the view window, the panel beside it shows the
	/// compass and the map around the party.
	void Draw3D(DrawList list)
	{
		Sync3D();

		var runtime = _s[0].Map;
		var world = runtime.World;
		var images = ImagesOf(runtime);
		var look = runtime.Look;
		var scene = BuildScene(runtime, images, look);
		var camera = RayCamera { X = _s[0].PartyX, Y = _s[0].PartyY, Angle = _s[0].Angle };

		RenderScene(scene, camera, _s[0].Frame, View3DWidth, View3DHeight);

		list.Add(RectItem(DrawPlane.Ground, 0, 0, 0, VirtualWidth, VirtualHeight, Color.Of(24, 20, 30)));
		list.Add(RectItem(DrawPlane.Ground, 1, View3DX - 2, View3DY - 2, View3DWidth + 4, View3DHeight + 4, Color.Of(150, 120, 70)));
		list.Add(IndexedItem(DrawPlane.Ground, 2, _s[0].Frame, View3DWidth, View3DHeight, look.Active, View3DX, View3DY));
		DrawCompass(list);
		DrawMiniMap(list, world);
	}

	/// The scene of the current map: walls from the layer objects, floor from ground, ceiling from decor, billboards from over
	/// and the figures.
	RayScene BuildScene(MapRuntime runtime, TileImages images, MapLook look)
	{
		var world = runtime.World;
		var map = world.Map;
		var tiled = map.Tiled;
		int count = tiled.Width * tiled.Height;
		var textures = List<RayTexture>.Create();
		var slots = Dictionary<int64, int>.Create();
		var walls = new int[count];
		var floors = new int[count];
		var ceilings = new int[count];
		var billboards = List<Billboard>.Create();

		for (var y = 0; y < tiled.Height; y += 1)
		{
			for (var x = 0; x < tiled.Width; x += 1)
			{
				int cell = y * tiled.Width + x;

				walls[cell] = TextureSlot(textures, slots, images, look, map.GetTile("objects", x, y), (int)LayerRole.Objects);
				floors[cell] = TextureSlot(textures, slots, images, look, map.GetTile("ground", x, y), (int)LayerRole.Ground);
				ceilings[cell] = TextureSlot(textures, slots, images, look, map.GetTile("decor", x, y), (int)LayerRole.Decor);

				int over = TextureSlot(textures, slots, images, look, map.GetTile("over", x, y), (int)LayerRole.Over);

				if (over >= 0)
					billboards.Add(Billboard { X = x * Fixed + Fixed / 2, Y = y * Fixed + Fixed / 2, Texture = over, Texel = TexelFixed });
			}
		}

		foreach (var actor in world.Actors)
		{
			if (actor.Same(world.Player) || !actor.Visible() || IsHidden(actor))
				continue;

			var picture = actor.CurrentImage();

			if (picture.IsEmpty())
				continue;

			textures.Add(RayTexture { Pixels = look.FigureIndices(actor.Name, actor.CurrentFrameKey(), picture), Width = picture.Width, Height = picture.Height });
			billboards.Add(Billboard
			{
				X = actor.CenterX() * Fixed / TileSize, Y = actor.CenterY() * Fixed / TileSize, Texture = textures.Count() - 1, Texel = FigureHeightFixed / picture.Height
			});
		}

		var settings = runtime.Settings;
		var shades = ShadesOf(runtime);
		var palette = look.Day;
		var sky = new uint8[View3DHeight];

		if (settings.Sky)
		{
			for (var row = 0; row < View3DHeight; row += 1)
			{
				int t = Min(256, row * 512 / View3DHeight);

				sky[row] = (uint8)NearestEntry(palette, 70 + 110 * t / 256, 120 + 90 * t / 256, 200 + 40 * t / 256);
			}
		}

		return RayScene
		{
			Width = tiled.Width, Height = tiled.Height, Walls = walls, Floors = floors, Ceilings = ceilings, Textures = textures, Billboards = billboards,
			Shades = shades, Light = settings.Light, Falloff = settings.Sky ? Fixed / 3 : Fixed * 3 / 2, FlatFloor = settings.FlatFloor, FlatCeiling = settings.FlatCeiling,
			Sky = settings.Sky, FloorColor = (uint8)NearestEntry(palette, 90, 80, 70), CeilingColor = (uint8)NearestEntry(palette, 60, 55, 60),
			Background = (uint8)NearestEntry(palette, 0, 0, 0), SkyRows = sky
		};
	}

	/// The shade tables of a map's palette (made once).
	uint8[] ShadesOf(MapRuntime runtime)
	{
		if (_shades.TryGet(runtime.Handle) is uint8[] cached)
			return cached;

		var tables = MakeShadeTables(runtime.Look.Day);

		_shades.Set(runtime.Handle, tables);

		return tables;
	}

	void DrawCompass(DrawList list)
	{
		int x = View3DX + View3DWidth + 12;
		int y = View3DY;

		list.Add(RectItem(DrawPlane.Panels, 0, x, y, 64, 20, Color.Of(40, 34, 50)));

		string[] names = new string[] { "N", "E", "S", "W" };
		int quarter = ((_s[0].Angle + AngleSteps / 8) / (AngleSteps / 4)) & 3;

		list.Add(TextItem(0, "View " + names[quarter], x + 6, y + 6, TextColor.Yellow));
	}

	/// The cells around the party from above: walls, blocked cells and figures, with the party in the middle.
	void DrawMiniMap(DrawList list, GameWorld world)
	{
		int cellSize = 4;
		int radius = 7;
		int left = View3DX + View3DWidth + 12;
		int top = View3DY + 28;
		var player = world.Player;

		list.Add(RectItem(DrawPlane.Panels, 0, left, top, (2 * radius + 1) * cellSize, (2 * radius + 1) * cellSize, Color.Of(16, 14, 20)));

		for (var dy = -radius; dy <= radius; dy += 1)
		{
			for (var dx = -radius; dx <= radius; dx += 1)
			{
				int x = player.TileX() + dx;
				int y = player.TileY() + dy;

				if (x < 0 || y < 0 || x >= world.Map.Width() || y >= world.Map.Height())
					continue;

				bool wall = GidOf(world.Map.GetTile("objects", x, y)) != 0;
				bool blocked = world.Map.IsBlocked(x, y);
				var color = wall ? Color.Of(170, 160, 140) : blocked ? Color.Of(90, 80, 70) : Color.Of(50, 45, 55);

				list.Add(RectItem(DrawPlane.Panels, 1, left + (dx + radius) * cellSize, top + (dy + radius) * cellSize, cellSize, cellSize, color));
			}
		}

		foreach (var actor in world.Actors)
		{
			int dx = actor.TileX() - player.TileX();
			int dy = actor.TileY() - player.TileY();

			if (actor.Same(player) || !actor.Visible() || IsHidden(actor) || Abs(dx) > radius || Abs(dy) > radius)
				continue;

			list.Add(RectItem(DrawPlane.Panels, 2, left + (dx + radius) * cellSize, top + (dy + radius) * cellSize, cellSize, cellSize, Color.Of(220, 90, 70)));
		}

		// the party: a dot and a short line towards the view
		int centerX = left + radius * cellSize + cellSize / 2;
		int centerY = top + radius * cellSize + cellSize / 2;

		for (var step = 0; step <= 3; step += 1)
		{
			int px = centerX + FixMul(SinOf(_s[0].Angle), step * Fixed * 2);
			int py = centerY - FixMul(CosOf(_s[0].Angle), step * Fixed * 2);

			list.Add(RectItem(DrawPlane.Panels, 3, px - 1, py - 1, 2, 2, Color.Of(255, 222, 90)));
		}
	}
}

/// The window of the 3D view on the 320x200 screen (the 3D design: 224x144, the panel beside it).
const int View3DX = 8;
const int View3DY = 22;
const int View3DWidth = 224;
const int View3DHeight = 144;

/// The radius of the party in the 3D view (fixed point cells): it slides along walls and fits through a one cell door.
const int PartyRadius = 13107;

/// How tall a figure stands in the 3D view, in cells (fixed point).
const int FigureHeightFixed = 36045;

/// The texture slot of a tile (added once per frame), -1 for the empty tile.
int TextureSlot(List<RayTexture> textures, Dictionary<int64, int> slots, TileImages images, MapLook look, uint32 raw, int role)
{
	if (GidOf(raw) == 0)
		return -1;

	int64 key = (int64)raw * 8 + (int64)role;

	if (slots.TryGet(key) is int slot)
		return slot;

	var picture = images.Get(raw, role);

	if (picture.IsEmpty())
		return -1;

	textures.Add(RayTexture { Pixels = look.TileIndices(raw, role, picture), Width = picture.Width, Height = picture.Height });
	slots.Set(key, textures.Count() - 1);

	return textures.Count() - 1;
}
