// Developer tool --map-palette: the palette of one or more Tiled maps, built from the colors of the
// tiles they use (with the frames of animated tiles) or of every tile of their tilesets. Several maps that share
// tilesets get one palette, so the palette pictures of the tilesets fit all of them. The options are those of
// 'amberpal extract'.

namespace Amber.Player.Tools;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Game;
using Amber.Player.Graphics;
using Amber.Player.Tiled;

const string MapPaletteUsage = "--map-palette <map.tmx>... --out <palette.gpl> [--size <n>] [--bits 8|4] [--ui <ui.gpl>] [--base <palette.gpl>] "
	+ "[--all-tiles] [--name <name>] [--swatch <swatch.png>]";

Error<void> CreateMapPalette(string[] args)
{
	var maps = List<string>.Create();
	string output = null;
	string uiPath = null;
	string basePath = null;
	string name = null;
	string swatch = null;
	int size = 256;
	int bits = 8;
	bool allTiles = false;

	for (var i = 1; i < args.Length; i += 1)
	{
		string argument = args[i];
		string value = i + 1 < args.Length ? args[i + 1] : null;

		if (argument == "--all-tiles")
			allTiles = true;
		else if (!argument.StartsWith("--"))
			maps.Add(argument);
		else if (value == null)
			return error(argument + " needs a value\nUsage: " + MapPaletteUsage, (int)ErrorKind.Argument);
		else
		{
			i += 1;

			if (argument == "--out")
				output = value;
			else if (argument == "--ui")
				uiPath = value;
			else if (argument == "--base")
				basePath = value;
			else if (argument == "--name")
				name = value;
			else if (argument == "--swatch")
				swatch = value;
			else if (argument == "--size")
				size = TryParseInt(value) ?? -1;
			else if (argument == "--bits")
				bits = TryParseInt(value) ?? -1;
			else if (argument != "--root" && argument != "--content")
				return error("unknown option " + argument + "\nUsage: " + MapPaletteUsage, (int)ErrorKind.Argument);
		}
	}

	if (maps.Count() == 0 || output == null)
		return error("Usage: " + MapPaletteUsage, (int)ErrorKind.Argument);

	if (bits != 8 && bits != 4)
		return error("--bits is 8 or 4", (int)ErrorKind.Argument);

	var histogram = ColorHistogram.Create();
	int tiles = 0;

	foreach (var path in maps)
		tiles += try AddMapTiles(ref histogram, path, allTiles, bits);

	var options = PaletteOptions.Create(size, name != null ? name : Path.GetStem(output).ToString());

	options.Bits = bits;

	if (basePath != null)
	{
		options.HasBase = true;
		options.Base = try LoadPalette(basePath);
	}

	if (uiPath != null)
	{
		options.HasUiColors = true;
		options.UiColors = try LoadUiColors(uiPath);
	}

	var build = try BuildPalette(histogram, options);

	try SavePalette(output, build.Palette);
	Console.WriteLine("Maps: " + maps.Count() + ", tiles: " + tiles + (allTiles ? " (all tiles of the tilesets)" : " (used by the maps, with animation frames)"));
	Console.WriteLine(DescribeBuild(build, histogram, PaletteRange.Art));
	Console.WriteLine("Wrote " + output);

	if (swatch != null)
	{
		try SavePicture(PaletteSwatch(build.Palette, 12), swatch);
		Console.WriteLine("Wrote " + swatch);
	}

	return;
}

/// Adds the pixels of the tiles of the map (each tile once, flips do not matter for colors); the number of tiles.
Error<int> AddMapTiles(ref ColorHistogram histogram, string path, bool allTiles, int bits)
{
	var map = try TiledLoader.Load(path);

	foreach (var reference in map.Tilesets)
	{
		if (reference.Tileset.Missing || reference.Tileset.ImagePath == null)
			return error(path + ": the tileset '" + reference.Tileset.Name + "' is not installed (the palette needs the real tiles)", (int)ErrorKind.Io);
	}

	var images = TileImages.Create(map);
	var gids = List<uint32>.Create();
	var seen = Dictionary<uint32, bool>.Create();

	if (allTiles)
	{
		// every tile of the tilesets the visible layers use (not the collision tileset)
		foreach (var reference in map.Tilesets)
		{
			if (!UsedByVisibleLayer(map, reference))
				continue;

			for (var id = 0; id < reference.Tileset.TileCount; id += 1)
				AddGid(gids, seen, (uint32)(reference.FirstGid + id));
		}
	}
	else
	{
		foreach (var layer in map.Layers)
		{
			if (RoleOf(layer) == LayerRole.Hidden)
				continue;

			for (var i = 0; i < layer.Data.Length; i += 1)
			{
				uint32 gid = GidOf(layer.Data[i]);

				if (gid == 0)
					continue;

				AddGid(gids, seen, gid);

				if (images.Animation(gid) is RawFrame[] frames)
				{
					foreach (var frame in frames)
						AddGid(gids, seen, GidOf(frame.Raw));
				}
			}
		}
	}

	foreach (var gid in gids)
		histogram.AddImage(images.Get(gid, 0), bits);

	return gids.Count();
}

bool UsedByVisibleLayer(TiledMap map, TiledTilesetReference reference)
{
	foreach (var layer in map.Layers)
	{
		if (RoleOf(layer) == LayerRole.Hidden)
			continue;

		for (var i = 0; i < layer.Data.Length; i += 1)
		{
			if (reference.Contains((int)GidOf(layer.Data[i])))
				return true;
		}
	}

	return false;
}

void AddGid(List<uint32> gids, Dictionary<uint32, bool> seen, uint32 gid)
{
	if (seen.TryGet(gid) is bool)
		return;

	seen.Set(gid, true);
	gids.Add(gid);
}
