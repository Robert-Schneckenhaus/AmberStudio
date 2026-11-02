// From RGBA pictures to palette pictures: collect the colors of many pictures (all tiles of a map, a sprite sheet ...),
// build a palette from them (exact if they fit, otherwise median cut) and turn every picture into palette indices.
// Everything is deterministic: the same pictures give the same palette.

namespace Amber.Graphics;

using System;
using Amber.Base;

/// Pixels with less alpha are transparent (entry 0), the others opaque. Palette pictures have no partial alpha.
const int AlphaThreshold = 128;

/// The colors of pictures with their pixel counts, in the order they were first seen.
struct ColorHistogram
{
	Dictionary<uint32, int64> Counts;
	List<uint32> Colors;
	int64 Opaque;
	int64 Transparent;
	/// Pixels that are neither fully transparent nor fully opaque (they lose their alpha).
	int64 SemiTransparent;

	static ColorHistogram Create()
	{
		return ColorHistogram { Counts = Dictionary<uint32, int64>.Create(), Colors = List<uint32>.Create() };
	}

	void AddColor(uint32 rgb, int64 count)
	{
		if (Counts.TryGet(rgb) is int64 old)
			Counts.Set(rgb, old + count);
		else
		{
			Counts.Set(rgb, count);
			Colors.Add(rgb);
		}

		Opaque += count;
	}

	/// Adds the pixels of the picture, with 'bits' bits per channel (8, or 4 for the old Amigas).
	void AddImage(Image image, int bits)
	{
		for (var i = 0; i < image.Width * image.Height; i += 1)
		{
			int alpha = (int)image.Data[i * 4 + 3];

			if (alpha > 0 && alpha < 255)
				SemiTransparent += 1;

			if (alpha < AlphaThreshold)
			{
				Transparent += 1;

				continue;
			}

			AddColor(ReduceColor(PixelColor(image, i), bits), 1);
		}
	}

	int ColorCount()
	{
		return Colors.Count();
	}
}

uint32 PixelColor(Image image, int pixel)
{
	return ((uint32)image.Data[pixel * 4] << 16) | ((uint32)image.Data[pixel * 4 + 1] << 8) | (uint32)image.Data[pixel * 4 + 2];
}

/// How a palette is built.
struct PaletteOptions
{
	int Size;
	/// Bits per channel: 8, or 4 for the 12-bit colors of the old Amigas.
	int Bits;
	/// Art (maps, tiles, sprites) or Ui (the eight colors at the end).
	PaletteRange Range;
	/// An existing palette: its used entries keep their place, new colors go into its free entries.
	bool HasBase;
	Palette Base;
	/// The user interface colors (up to eight) for the end of the palette; without them the UI entries stay as they are
	/// (from the base palette, or free).
	bool HasUiColors;
	List<uint32> UiColors;
	string Name;

	static PaletteOptions Create(int size, string name)
	{
		return PaletteOptions { Size = size, Bits = 8, Range = PaletteRange.Art, HasBase = false, Base = Palette.Create(size, name), HasUiColors = false, UiColors = List<uint32>.Create(), Name = name };
	}
}

/// A built palette and what happened on the way.
struct PaletteBuild
{
	Palette Palette;
	/// The different colors of the pictures that were not in the palette yet.
	int NewColors;
	/// The entries that were filled.
	int FilledEntries;
	/// True if there were more new colors than free entries (median cut merged them).
	bool Reduced;
}

Error<PaletteBuild> BuildPalette(ColorHistogram histogram, PaletteOptions options)
{
	if (!IsPaletteSize(options.Size))
		return error("a palette has 16, 32, 64, 128 or 256 entries, not " + options.Size, (int)ErrorKind.Argument);

	if (options.Range == PaletteRange.All)
		return error("a palette is built for the art or for the user interface, not for both", (int)ErrorKind.Argument);

	if (options.HasBase && options.Base.Size != options.Size)
		return error("the base palette has " + options.Base.Size + " entries, not " + options.Size, (int)ErrorKind.Argument);

	var palette = options.HasBase ? options.Base.Clone() : Palette.Create(options.Size, options.Name);

	palette.Name = options.Name;

	if (options.HasUiColors)
	{
		if (options.UiColors.Count() > UiColorCount)
			return error("the user interface has " + UiColorCount + " colors, not " + options.UiColors.Count(), (int)ErrorKind.Argument);

		for (var i = 0; i < options.UiColors.Count(); i += 1)
			palette.Set(palette.FirstUi() + i, ReduceColor(options.UiColors.Get(i), options.Bits));
	}

	PaletteRange range = options.Range;
	var known = Dictionary<uint32, bool>.Create();

	for (var i = palette.Start(range); i < palette.End(range); i += 1)
	{
		if (palette.Used[i])
			known.Set(palette.ColorAt(i), true);
	}

	var colors = List<uint32>.Create();
	var weights = List<int64>.Create();

	foreach (var rgb in histogram.Colors)
	{
		if (known.TryGet(rgb) is bool)
			continue;

		colors.Add(rgb);
		weights.Add(histogram.Counts.TryGet(rgb) is int64 count ? count : 0);
	}

	int free = palette.End(range) - palette.Start(range) - palette.UsedCount(range);
	bool reduced = colors.Count() > free;
	var chosen = reduced ? MedianCut(colors.ToArray(), weights.ToArray(), free, options.Bits) : colors.ToArray();
	var ordered = SortForPalette(chosen);
	int next = palette.Start(range);

	foreach (var rgb in ordered)
	{
		while (palette.Used[next])
			next += 1;

		palette.Set(next, rgb);
	}

	return PaletteBuild { Palette = palette, NewColors = colors.Count(), FilledEntries = ordered.Length, Reduced = reduced };
}

/// A color with its place in the palette order.
struct SortedColor
{
	uint32 Rgb;
	int64 Key;
}

int CompareSortedColors(SortedColor a, SortedColor b)
{
	return a.Key < b.Key ? -1 : a.Key > b.Key ? 1 : 0;
}

/// The colors in palette order: grays first, then twelve hue groups, inside a group from dark to bright. Neighbouring
/// entries look alike, which makes the palette easy to read and to edit (ramps for day and night).
uint32[] SortForPalette(uint32[] colors)
{
	var items = new SortedColor[colors.Length];

	for (var i = 0; i < colors.Length; i += 1)
		items[i] = SortedColor { Rgb = colors[i], Key = PaletteOrderKey(colors[i]) };

	Func<SortedColor, SortedColor, int> compare = CompareSortedColors;
	var sorted = SortArray(items, compare);
	var result = new uint32[colors.Length];

	for (var i = 0; i < colors.Length; i += 1)
		result[i] = sorted[i].Rgb;

	return result;
}

int64 PaletteOrderKey(uint32 rgb)
{
	int r = (int)((rgb >> 16) & 0xFF);
	int g = (int)((rgb >> 8) & 0xFF);
	int b = (int)(rgb & 0xFF);
	int max = Math.Max(r, Math.Max(g, b));
	int min = Math.Min(r, Math.Min(g, b));
	int64 group = 0;

	if (max - min >= 24)
	{
		int delta = max - min;
		int hue;

		if (max == r)
			hue = 60 * (g - b) / delta;
		else if (max == g)
			hue = 120 + 60 * (b - r) / delta;
		else
			hue = 240 + 60 * (r - g) / delta;

		if (hue < 0)
			hue += 360;

		group = 1 + (int64)(hue * 12 / 360);
	}

	int64 luminance = (int64)(299 * r + 587 * g + 114 * b);

	return group * 1000000000 + luminance * 1000 + (int64)(rgb % 1000);
}

/// A box of the median cut: the colors in it (indices into the color array).
struct ColorBox
{
	List<int> Members;
}

/// At most 'count' colors that stand for all the colors (weighted by their pixels): the box with the widest channel is
/// split at its weighted median until there are enough boxes, every box gives its weighted average.
uint32[] MedianCut(uint32[] colors, int64[] weights, int count, int bits)
{
	var boxes = List<ColorBox>.Create();

	if (count <= 0 || colors.Length == 0)
		return new uint32[0];

	var all = List<int>.Create();

	for (var i = 0; i < colors.Length; i += 1)
		all.Add(i);

	boxes.Add(ColorBox { Members = all });

	while (boxes.Count() < count)
	{
		int best = -1;
		int bestChannel = 0;
		int64 bestScore = 0;

		for (var i = 0; i < boxes.Count(); i += 1)
		{
			var box = boxes.Get(i);

			if (box.Members.Count() < 2)
				continue;

			for (var channel = 0; channel < 3; channel += 1)
			{
				int width = ChannelMax(colors, box, channel) - ChannelMin(colors, box, channel);
				// wide boxes with many pixels first; green counts most for the eye
				int64 score = (int64)width * (int64)ChannelWeight(channel) * (1 + BoxWeight(weights, box) / 16);

				if (score > bestScore)
				{
					bestScore = score;
					best = i;
					bestChannel = channel;
				}
			}
		}

		if (best < 0)
			break;

		var split = SplitBox(colors, weights, boxes.Get(best), bestChannel);

		boxes.Set(best, split.Left);
		boxes.Add(split.Right);
	}

	var result = List<uint32>.Create();
	var seen = Dictionary<uint32, bool>.Create();

	foreach (var box in boxes)
	{
		uint32 rgb = ReduceColor(BoxAverage(colors, weights, box), bits);

		if (seen.TryGet(rgb) is bool)
			continue;

		seen.Set(rgb, true);
		result.Add(rgb);
	}

	return result.ToArray();
}

int ChannelWeight(int channel)
{
	return channel == 1 ? 4 : channel == 0 ? 3 : 2;
}

int Channel(uint32 rgb, int channel)
{
	return (int)((rgb >> (16 - 8 * channel)) & 0xFF);
}

int ChannelMin(uint32[] colors, ColorBox box, int channel)
{
	int min = 255;

	foreach (var member in box.Members)
		min = Math.Min(min, Channel(colors[member], channel));

	return min;
}

int ChannelMax(uint32[] colors, ColorBox box, int channel)
{
	int max = 0;

	foreach (var member in box.Members)
		max = Math.Max(max, Channel(colors[member], channel));

	return max;
}

int64 BoxWeight(int64[] weights, ColorBox box)
{
	int64 total = 0;

	foreach (var member in box.Members)
		total += weights[member];

	return total;
}

struct BoxSplit
{
	ColorBox Left;
	ColorBox Right;
}

/// Splits the box at the weighted median of the channel; both halves keep at least one color.
BoxSplit SplitBox(uint32[] colors, int64[] weights, ColorBox box, int channel)
{
	var perValue = new int64[256];
	int64 total = 0;

	foreach (var member in box.Members)
	{
		perValue[Channel(colors[member], channel)] += weights[member] + 1;
		total += weights[member] + 1;
	}

	int min = ChannelMin(colors, box, channel);
	int max = ChannelMax(colors, box, channel);
	int64 sum = 0;
	int cut = min;

	for (var value = min; value <= max; value += 1)
	{
		sum += perValue[value];
		cut = value;

		if (sum * 2 >= total)
			break;
	}

	cut = Math.Min(cut, max - 1);

	var left = List<int>.Create();
	var right = List<int>.Create();

	foreach (var member in box.Members)
	{
		if (Channel(colors[member], channel) <= cut)
			left.Add(member);
		else
			right.Add(member);
	}

	return BoxSplit { Left = ColorBox { Members = left }, Right = ColorBox { Members = right } };
}

uint32 BoxAverage(uint32[] colors, int64[] weights, ColorBox box)
{
	int64 red = 0;
	int64 green = 0;
	int64 blue = 0;
	int64 total = 0;

	foreach (var member in box.Members)
	{
		int64 weight = weights[member] + 1;

		red += (int64)Channel(colors[member], 0) * weight;
		green += (int64)Channel(colors[member], 1) * weight;
		blue += (int64)Channel(colors[member], 2) * weight;
		total += weight;
	}

	return ((uint32)((red + total / 2) / total) << 16) | ((uint32)((green + total / 2) / total) << 8) | (uint32)((blue + total / 2) / total);
}

/// A picture as palette indices and how well the palette fits it.
struct IndexedPicture
{
	int Width;
	int Height;
	uint8[] Indices;
	/// Opaque pixels whose color is in the palette.
	int64 Exact;
	/// Opaque pixels that got the nearest color instead.
	int64 Approximated;
	/// The largest distance of such a pixel to its palette color (ColorDistance).
	int64 WorstDistance;
	int64 SemiTransparent;
}

/// The picture with the entries of the palette range: transparent pixels get entry 0, the others the nearest used entry.
Error<IndexedPicture> IndexImage(Image image, Palette palette, PaletteRange range, int bits)
{
	var entries = List<int>.Create();

	for (var i = palette.Start(range); i < palette.End(range); i += 1)
	{
		if (palette.Used[i])
			entries.Add(i);
	}

	if (entries.Count() == 0)
		return error("the palette '" + palette.Name + "' has no colors in that range", (int)ErrorKind.InvalidData);

	var result = IndexedPicture { Width = image.Width, Height = image.Height, Indices = new uint8[image.Width * image.Height] };
	var nearest = Dictionary<uint32, int>.Create();

	for (var pixel = 0; pixel < image.Width * image.Height; pixel += 1)
	{
		int alpha = (int)image.Data[pixel * 4 + 3];

		if (alpha > 0 && alpha < 255)
			result.SemiTransparent += 1;

		if (alpha < AlphaThreshold)
			continue;

		uint32 rgb = ReduceColor(PixelColor(image, pixel), bits);
		int index;

		if (nearest.TryGet(rgb) is int cached)
			index = cached;
		else
		{
			index = NearestEntry(palette, entries, rgb);
			nearest.Set(rgb, index);
		}

		int64 distance = ColorDistance(rgb, palette.ColorAt(index));

		if (distance == 0)
			result.Exact += 1;
		else
		{
			result.Approximated += 1;
			result.WorstDistance = Math.Max(result.WorstDistance, distance);
		}

		result.Indices[pixel] = (uint8)index;
	}

	return result;
}

int NearestEntry(Palette palette, List<int> entries, uint32 rgb)
{
	int best = entries.Get(0);
	int64 bestDistance = ColorDistance(rgb, palette.ColorAt(best));

	foreach (var entry in entries)
	{
		int64 distance = ColorDistance(rgb, palette.ColorAt(entry));

		if (distance < bestDistance)
		{
			best = entry;
			bestDistance = distance;
		}
	}

	return best;
}

/// The palette picture as a PNG with the colors of the palette (entry 0 transparent).
uint8[] EncodePalettePng(int width, int height, uint8[] indices, Palette palette)
{
	return EncodeIndexedPng(width, height, indices, palette.Rgb, palette.Size, palette.TransparentEntries());
}

/// The RGBA picture of palette indices with the colors of a palette (to look at a palette swap).
Image RenderIndexed(int width, int height, uint8[] indices, Palette palette)
{
	var image = Image.Create(width, height);

	for (var pixel = 0; pixel < width * height; pixel += 1)
	{
		int index = (int)indices[pixel];

		if (index == 0 || index >= palette.Size)
			continue;

		image.Data[pixel * 4] = palette.Rgb[index * 3];
		image.Data[pixel * 4 + 1] = palette.Rgb[index * 3 + 1];
		image.Data[pixel * 4 + 2] = palette.Rgb[index * 3 + 2];
		image.Data[pixel * 4 + 3] = 255;
	}

	return image;
}

/// What building a palette did, in a few lines (for the tools).
string DescribeBuild(PaletteBuild build, ColorHistogram histogram, PaletteRange range)
{
	var palette = build.Palette;
	string text = "Palette '" + palette.Name + "': " + palette.Size + " entries, " + palette.UsedCount(PaletteRange.Art) + " of "
		+ (palette.FirstUi() - 1) + " art entries and " + palette.UsedCount(PaletteRange.Ui) + " of " + UiColorCount + " UI entries used\n";

	text = text + "Pictures: " + histogram.ColorCount() + " colors in " + histogram.Opaque + " opaque pixels, " + histogram.Transparent
		+ " transparent\n";
	text = text + "New colors: " + build.NewColors + ", entries filled: " + build.FilledEntries + " (" + (range == PaletteRange.Ui ? "UI" : "art") + ")";

	if (build.Reduced)
		text = text + "\nMore colors than free entries: merged with median cut (see the report of 'index' for how far off the pixels are)";

	if (histogram.SemiTransparent > 0)
		text = text + "\nWarning: " + histogram.SemiTransparent + " pixels are partly transparent; below alpha " + AlphaThreshold
			+ " they become transparent, above opaque";

	return text;
}
