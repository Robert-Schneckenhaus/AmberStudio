// How a map looks (spec 5.7 and the change note of 2026-10-23): the tiles and figures of a map
// are palette pictures, their colors come from the map's palette. The host blends between the day and the night palette
// by the clock (unless the map has daylight off); set_palette and fade_palette put a palette of their own in front of
// that until they release it, flash tints the art entries for a moment. The user interface entries never change.

namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Graphics;
using Amber.Player.Tiled;

/// Without set_palette: the palette of the map by the clock.
const int NoPaletteOverride = 0xFFFF;

struct MapLookValues
{
	/// A palette of a script (set_palette, fade_palette) is in front of day and night.
	bool HasOverride;
	Palette Override;
	/// A fade: from these colors (what was visible when it started) to the target in FadeTicks ticks.
	bool Fading;
	bool FadeToClock;
	uint8[] FadeFrom;
	int FadeTicks;
	int FadeElapsed;
	/// The thread that waits for the end of the fade, or -1.
	int FadeThread;
	uint32 FlashColor;
	int FlashTicks;
	int FlashElapsed;
	/// The night weight of the last update (0 day, 256 night).
	int NightWeight;
}

/// The palette and the palette pictures of one map. A handle: the view, the host and the session share it.
struct MapLook
{
	MapLookValues[] _s;
	Palette Day;
	Palette Night;
	bool Daylight;
	/// The colors of this frame; the draw items of the frame refer to it.
	uint8[] Active;
	Dictionary<int64, uint8[]> _tiles;
	Dictionary<string, uint8[]> _figures;
	/// Scratch for the colors by the clock.
	uint8[] _clock;

	static MapLook Create(Palette day, Palette night, bool daylight)
	{
		var state = new MapLookValues[1];

		state[0].FadeThread = -1;

		var look = MapLook
		{
			_s = state, Day = day, Night = night, Daylight = daylight, Active = new uint8[day.Size * 3], _tiles = Dictionary<int64, uint8[]>.Create(),
			_figures = Dictionary<string, uint8[]>.Create(), _clock = new uint8[day.Size * 3]
		};

		look.Update(9 * 60);

		return look;
	}

	/// The palette indices of a tile picture (computed once per tile and role).
	uint8[] TileIndices(uint32 raw, int role, Image picture)
	{
		int64 key = (int64)raw * 8 + (int64)role;

		if (_tiles.TryGet(key) is uint8[] cached)
			return cached;

		var indices = IndicesOf(picture);

		_tiles.Set(key, indices);

		return indices;
	}

	/// The palette indices of a figure's picture (the frame key of Actor.CurrentFrameKey, computed once per figure and frame).
	uint8[] FigureIndices(string figure, int frameKey, Image picture)
	{
		string key = figure + "#" + frameKey;

		if (_figures.TryGet(key) is uint8[] cached)
			return cached;

		var indices = IndicesOf(picture);

		_figures.Set(key, indices);

		return indices;
	}

	uint8[] IndicesOf(Image picture)
	{
		var indexed = IndexImage(picture, Day, PaletteRange.Art, 8);

		if (indexed is IndexedPicture result)
			return result.Indices;

		// a palette without art colors: everything transparent
		return new uint8[picture.Width * picture.Height];
	}

	/// The colors for the minute of the day: day and night palettes mixed, a script palette or fade in front, a flash on top.
	void Update(int minuteOfDay)
	{
		int weight = Daylight ? NightWeightAt(minuteOfDay) : 0;

		_s[0].NightWeight = weight;
		BlendPalettes(Day, Night, weight, _clock);

		if (_s[0].Fading)
		{
			var target = _s[0].FadeToClock ? _clock : _s[0].Override.Rgb;
			int t = _s[0].FadeTicks <= 0 ? 256 : _s[0].FadeElapsed * 256 / _s[0].FadeTicks;

			for (var i = 0; i < Active.Length; i += 1)
				Active[i] = (uint8)(((int)_s[0].FadeFrom[i] * (256 - t) + (int)target[i] * t) >> 8);

			// the user interface entries stay as they are
			CopyUi(_clock, Active, Day.Size);
		}
		else if (_s[0].HasOverride)
		{
			for (var i = 0; i < Active.Length; i += 1)
				Active[i] = _s[0].Override.Rgb[i];

			CopyUi(_clock, Active, Day.Size);
		}
		else
		{
			for (var i = 0; i < Active.Length; i += 1)
				Active[i] = _clock[i];
		}

		if (_s[0].FlashTicks > 0)
		{
			// up and down again: strongest in the middle of the flash
			int half = Max(1, _s[0].FlashTicks / 2);
			int distance = _s[0].FlashElapsed < half ? _s[0].FlashElapsed : _s[0].FlashTicks - _s[0].FlashElapsed;

			TintPalette(Active, Day.Size, _s[0].FlashColor, Clamp(distance * 256 / half, 0, 256));
		}
	}

	/// One game tick of the fade and the flash. Returns the thread to resume when a fade ends, or -1.
	int Tick()
	{
		int resume = -1;

		if (_s[0].FlashTicks > 0)
		{
			_s[0].FlashElapsed += 1;

			if (_s[0].FlashElapsed >= _s[0].FlashTicks)
				_s[0].FlashTicks = 0;
		}

		if (_s[0].Fading)
		{
			_s[0].FadeElapsed += 1;

			if (_s[0].FadeElapsed >= _s[0].FadeTicks)
			{
				_s[0].Fading = false;
				resume = _s[0].FadeThread;
				_s[0].FadeThread = -1;
			}
		}

		return resume;
	}

	/// set_palette: the palette from now on (NoPaletteOverride: back to the palette of the map by the clock).
	void SetPalette(bool release, Palette palette)
	{
		_s[0].Fading = false;
		_s[0].HasOverride = !release;

		if (!release)
			_s[0].Override = Fitted(palette);
	}

	/// fade_palette: from what is visible now to the palette (or back to the clock) in 'ticks' ticks. A thread that waits
	/// is resumed by Tick at the end; a fade that was running ends at once (its thread is returned to be resumed).
	int FadePalette(bool release, Palette palette, int ticks, int waitingThread)
	{
		int previous = _s[0].Fading ? _s[0].FadeThread : -1;
		var from = new uint8[Active.Length];

		for (var i = 0; i < Active.Length; i += 1)
			from[i] = Active[i];

		_s[0].Fading = ticks > 0;
		_s[0].FadeToClock = release;
		_s[0].FadeFrom = from;
		_s[0].FadeTicks = ticks;
		_s[0].FadeElapsed = 0;
		_s[0].FadeThread = ticks > 0 ? waitingThread : -1;
		_s[0].HasOverride = !release;

		if (!release)
			_s[0].Override = Fitted(palette);

		return previous;
	}

	/// flash: the art entries go to the color and back in 'ticks' ticks.
	void Flash(uint32 color, int ticks)
	{
		_s[0].FlashColor = color;
		_s[0].FlashTicks = Max(1, ticks);
		_s[0].FlashElapsed = 0;
	}

	/// Leaving the map releases a palette of a script (spec 5.7: it belongs to the owner map). Returns a thread that
	/// waited for a fade, or -1.
	int Release()
	{
		int thread = _s[0].Fading ? _s[0].FadeThread : -1;

		_s[0].Fading = false;
		_s[0].HasOverride = false;
		_s[0].FadeThread = -1;
		_s[0].FlashTicks = 0;

		return thread;
	}

	bool IsNight()
	{
		return _s[0].NightWeight >= 128;
	}

	/// A palette of another size is cut or filled to the size of the map's palette.
	Palette Fitted(Palette palette)
	{
		if (palette.Size == Day.Size)
			return palette;

		var fitted = Day.Clone();

		for (var i = 1; i < Min(palette.Size, Day.Size) - UiColorCount; i += 1)
		{
			fitted.Rgb[i * 3] = palette.Rgb[i * 3];
			fitted.Rgb[i * 3 + 1] = palette.Rgb[i * 3 + 1];
			fitted.Rgb[i * 3 + 2] = palette.Rgb[i * 3 + 2];
		}

		return fitted;
	}
}

void CopyUi(uint8[] from, uint8[] to, int size)
{
	for (var i = (size - UiColorCount) * 3; i < size * 3; i += 1)
		to[i] = from[i];

	to[0] = from[0];
	to[1] = from[1];
	to[2] = from[2];
}

/// How much night there is (0 day, 256 night): dawn from 5 to 7, dusk from 19 to 21.
int NightWeightAt(int minuteOfDay)
{
	if (minuteOfDay >= 7 * 60 && minuteOfDay < 19 * 60)
		return 0;

	if (minuteOfDay >= 5 * 60 && minuteOfDay < 7 * 60)
		return 256 - (minuteOfDay - 5 * 60) * 256 / 120;

	if (minuteOfDay >= 19 * 60 && minuteOfDay < 21 * 60)
		return (minuteOfDay - 19 * 60) * 256 / 120;

	return 256;
}

/// Adds the colors of the tiles of a map: the tiles its visible layers use (with the frames of animated tiles) or every
/// tile of the tilesets those layers use. Flips do not change colors, so every tile counts once per role (placeholders
/// differ by role). Returns the number of tiles.
int AddTileColors(ref ColorHistogram histogram, TiledMap map, TileImages images, bool allTiles, int bits)
{
	var seen = Dictionary<int64, bool>.Create();
	int count = 0;

	for (var layerIndex = 0; layerIndex < map.Layers.Count(); layerIndex += 1)
	{
		var layer = map.Layers.Get(layerIndex);
		var role = RoleOf(layer);

		if (role == LayerRole.Hidden)
			continue;

		var gids = List<uint32>.Create();

		if (allTiles)
		{
			foreach (var reference in map.Tilesets)
			{
				if (UsesTileset(layer, reference))
				{
					for (var id = 0; id < reference.Tileset.TileCount; id += 1)
						gids.Add((uint32)(reference.FirstGid + id));
				}
			}
		}
		else
		{
			for (var i = 0; i < layer.Data.Length; i += 1)
			{
				uint32 gid = GidOf(layer.Data[i]);

				if (gid == 0)
					continue;

				gids.Add(gid);

				if (images.Animation(gid) is RawFrame[] frames)
				{
					foreach (var frame in frames)
						gids.Add(GidOf(frame.Raw));
				}
			}
		}

		foreach (var gid in gids)
		{
			int64 key = (int64)gid * 8 + (int64)role;

			if (seen.TryGet(key) is bool)
				continue;

			seen.Set(key, true);
			histogram.AddImage(images.Get(gid, (int)role), bits);
			count += 1;
		}
	}

	return count;
}

bool UsesTileset(TiledLayer layer, TiledTilesetReference reference)
{
	for (var i = 0; i < layer.Data.Length; i += 1)
	{
		if (reference.Contains((int)GidOf(layer.Data[i])))
			return true;
	}

	return false;
}

/// Adds the colors of every picture of a figure.
void AddFigureColors(ref ColorHistogram histogram, ActorArt art)
{
	foreach (var picture in art.Stand)
		histogram.AddImage(picture, 8);

	foreach (var picture in art.Walk)
		histogram.AddImage(picture, 8);

	foreach (var picture in art.Run)
		histogram.AddImage(picture, 8);
}
