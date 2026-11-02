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
}

/// Draws the current world: ground, decoration, and the sorted plane with objects, actors and canopy. Follows the player.
/// A handle.
struct WorldView
{
	ViewValues[] _s;
	Dictionary<int, TileImages> _images;

	static WorldView Create()
	{
		return WorldView { _s = new ViewValues[1], _images = Dictionary<int, TileImages>.Create() };
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
}
