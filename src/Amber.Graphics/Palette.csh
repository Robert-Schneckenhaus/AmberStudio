// Palettes: every picture of a game is palette indices, the colors come from a palette that the
// game swaps (another map, day and night, effects) without touching the pictures, like Ambermoon. Index 0 is
// transparent, the last eight entries belong to the user interface (frames and everything else that is always visible),
// the entries between them are the art of the maps, tiles and sprites. Palettes are stored as GIMP palettes (.gpl), which
// Aseprite, GIMP, Krita and GrafX2 read and write.

namespace Amber.Graphics;

using System;
using Amber.Base;

/// The entries at the end of every palette that belong to the user interface.
const int UiColorCount = 8;

/// The part of a palette a picture may use.
enum PaletteRange : int32
{
	/// The art entries: 1 up to the first UI entry.
	Art = 0,
	/// The eight UI entries at the end.
	Ui = 1,
	/// Art and UI (everything but the transparent entry 0).
	All = 2
}

/// The name of an entry nobody uses yet (in the .gpl file); it can be filled later without moving the other entries.
const string UnusedEntryName = "unused";

const string TransparentEntryName = "transparent";

/// A palette of 16, 32, 64, 128 or 256 colors (32 for the old Amigas, 256 for AGA and the PC). Copies share the entries.
struct Palette
{
	int Size;
	/// Three bytes per entry (red, green, blue).
	uint8[] Rgb;
	bool[] Used;
	string Name;

	static Palette Create(int size, string name)
	{
		var used = new bool[size];

		used[0] = true;

		return Palette { Size = size, Rgb = new uint8[size * 3], Used = used, Name = name };
	}

	int FirstUi()
	{
		return Size - UiColorCount;
	}

	/// The first entry of the range.
	int Start(PaletteRange range)
	{
		return range == PaletteRange.Ui ? FirstUi() : 1;
	}

	/// The entry after the last one of the range.
	int End(PaletteRange range)
	{
		return range == PaletteRange.Art ? FirstUi() : Size;
	}

	/// The color of an entry as 0xRRGGBB.
	uint32 ColorAt(int index)
	{
		return ((uint32)Rgb[index * 3] << 16) | ((uint32)Rgb[index * 3 + 1] << 8) | (uint32)Rgb[index * 3 + 2];
	}

	void Set(int index, uint32 rgb)
	{
		Rgb[index * 3] = (uint8)((rgb >> 16) & 0xFF);
		Rgb[index * 3 + 1] = (uint8)((rgb >> 8) & 0xFF);
		Rgb[index * 3 + 2] = (uint8)(rgb & 0xFF);
		Used[index] = true;
	}

	int UsedCount(PaletteRange range)
	{
		int count = 0;

		for (var i = Start(range); i < End(range); i += 1)
		{
			if (Used[i])
				count += 1;
		}

		return count;
	}

	Palette Clone()
	{
		var copy = Create(Size, Name);

		for (var i = 0; i < Size * 3; i += 1)
			copy.Rgb[i] = Rgb[i];

		for (var i = 0; i < Size; i += 1)
			copy.Used[i] = Used[i];

		return copy;
	}

	/// The flags for the tRNS chunk of a palette PNG: only entry 0 is transparent.
	bool[] TransparentEntries()
	{
		var transparent = new bool[Size];

		transparent[0] = true;

		return transparent;
	}
}

bool IsPaletteSize(int size)
{
	return size == 16 || size == 32 || size == 64 || size == 128 || size == 256;
}

/// One color line of a .gpl file.
struct PaletteEntry
{
	uint32 Rgb;
	string Name;
}

/// The palette as a GIMP palette. The entry names say what an entry is for (transparent, ui 0..7, unused).
string PaletteToGpl(Palette palette)
{
	var builder = StringBuilder.Create();

	builder.AppendLine("GIMP Palette");
	builder.AppendLine("Name: " + palette.Name);
	builder.AppendLine("Columns: 16");
	builder.AppendLine("# Amber palette: entry 0 transparent, the last " + UiColorCount + " entries user interface, entries named '"
		+ UnusedEntryName + "' are free");

	for (var i = 0; i < palette.Size; i += 1)
	{
		uint32 rgb = palette.ColorAt(i);
		string name = i == 0 ? TransparentEntryName : !palette.Used[i] ? UnusedEntryName
			: i >= palette.FirstUi() ? "ui " + (i - palette.FirstUi()) : "color " + i;

		builder.AppendLine(PadLeft("" + ((rgb >> 16) & 0xFF), 3) + " " + PadLeft("" + ((rgb >> 8) & 0xFF), 3) + " "
			+ PadLeft("" + (rgb & 0xFF), 3) + "\t" + name);
	}

	return builder.ToString();
}

/// The color lines of a .gpl file in their order.
Error<List<PaletteEntry>> ParseGplEntries(string text, string source)
{
	var entries = List<PaletteEntry>.Create();
	var lines = text.Replace("\r\n", "\n").Split('\n');
	int number = 0;

	foreach (var raw in lines)
	{
		number += 1;
		string line = raw.Trim().ToString();

		if (number == 1)
		{
			if (line != "GIMP Palette")
				return error(source + ": not a GIMP palette (the first line must be 'GIMP Palette')", (int)ErrorKind.InvalidData);

			continue;
		}

		if (line.Length == 0 || line.StartsWith("#") || line.StartsWith("Name:") || line.StartsWith("Columns:"))
			continue;

		var words = SplitWhitespace(line);

		if (words.Length < 3)
			return error(source + ":" + number + ": expected 'red green blue name'", (int)ErrorKind.InvalidData);

		var red = TryParseInt(words[0]);
		var green = TryParseInt(words[1]);
		var blue = TryParseInt(words[2]);

		if (red is int r && green is int g && blue is int b && r >= 0 && r <= 255 && g >= 0 && g <= 255 && b >= 0 && b <= 255)
		{
			var name = List<string>.Create();

			for (var i = 3; i < words.Length; i += 1)
				name.Add(words[i]);

			entries.Add(PaletteEntry { Rgb = ((uint32)r << 16) | ((uint32)g << 8) | (uint32)b, Name = JoinList(" ", name) });
		}
		else
			return error(source + ":" + number + ": the color values are 0 to 255", (int)ErrorKind.InvalidData);
	}

	return entries;
}

/// A whole palette from a .gpl file: 16, 32, 64, 128 or 256 entries; entries named 'unused' stay free.
Error<Palette> ParsePaletteGpl(string text, string source)
{
	var entries = try ParseGplEntries(text, source);
	int size = entries.Count();

	if (!IsPaletteSize(size))
		return error(source + ": a palette has 16, 32, 64, 128 or 256 entries, this one has " + size, (int)ErrorKind.InvalidData);

	var name = Path.GetStem(source);

	foreach (var raw in text.Replace("\r\n", "\n").Split('\n'))
	{
		string line = raw.Trim().ToString();

		if (line.StartsWith("Name:"))
			name = line.Substring(5).Trim().ToString();
	}

	var palette = Palette.Create(size, name);

	for (var i = 1; i < size; i += 1)
	{
		var entry = entries.Get(i);

		if (entry.Name != UnusedEntryName)
			palette.Set(i, entry.Rgb);
	}

	return palette;
}

Error<Palette> LoadPalette(string path)
{
	var text = File.ReadAllText(path);

	if (text is string content)
		return ParsePaletteGpl(content, path);

	return error("cannot read '" + path + "': " + text.Message, (int)ErrorKind.Io);
}

/// The eight user interface colors from a .gpl file: either a list of up to eight colors, or a whole palette whose last
/// eight entries are taken.
Error<List<uint32>> LoadUiColors(string path)
{
	var text = File.ReadAllText(path);

	if (text is string content)
	{
		var entries = try ParseGplEntries(content, path);
		var colors = List<uint32>.Create();
		int count = entries.Count();
		int start = count <= UiColorCount ? 0 : count - UiColorCount;

		if (count > UiColorCount && !IsPaletteSize(count))
			return error(path + ": the user interface has " + UiColorCount + " colors, the file has " + count, (int)ErrorKind.InvalidData);

		for (var i = start; i < count; i += 1)
		{
			if (entries.Get(i).Name != UnusedEntryName)
				colors.Add(entries.Get(i).Rgb);
		}

		return colors;
	}

	return error("cannot read '" + path + "': " + text.Message, (int)ErrorKind.Io);
}

Error<void> SavePalette(string path, Palette palette)
{
	return File.WriteAllText(path, PaletteToGpl(palette));
}

/// The color with fewer bits per channel, spread back to 0..255 (4 bits: the 12-bit colors of the old Amigas).
uint32 ReduceColor(uint32 rgb, int bits)
{
	if (bits >= 8)
		return rgb;

	return (ReduceChannel((int)((rgb >> 16) & 0xFF), bits) << 16) | (ReduceChannel((int)((rgb >> 8) & 0xFF), bits) << 8)
		| ReduceChannel((int)(rgb & 0xFF), bits);
}

uint32 ReduceChannel(int value, int bits)
{
	int levels = (1 << bits) - 1;
	int level = (value * levels + 127) / 255;

	return (uint32)((level * 255 + levels / 2) / levels);
}

/// The distance of two colors, weighted for the eye (green counts most, blue least).
int64 ColorDistance(uint32 a, uint32 b)
{
	int64 red = (int64)((a >> 16) & 0xFF) - (int64)((b >> 16) & 0xFF);
	int64 green = (int64)((a >> 8) & 0xFF) - (int64)((b >> 8) & 0xFF);
	int64 blue = (int64)(a & 0xFF) - (int64)(b & 0xFF);

	return 3 * red * red + 4 * green * green + 2 * blue * blue;
}

/// A picture of the palette: 16 entries per row, 'cell' pixels per entry, free entries crossed out.
Image PaletteSwatch(Palette palette, int cell)
{
	int rows = (palette.Size + 15) / 16;
	var image = Image.Create(16 * cell, rows * cell);

	for (var i = 0; i < palette.Size; i += 1)
	{
		uint32 rgb = palette.ColorAt(i);
		int x = (i % 16) * cell;
		int y = (i / 16) * cell;

		image.FillRect(x, y, cell, cell, Color.Of((int)((rgb >> 16) & 0xFF), (int)((rgb >> 8) & 0xFF), (int)(rgb & 0xFF)));

		if (i == 0 || !palette.Used[i])
		{
			for (var d = 0; d < cell; d += 1)
			{
				image.Set(x + d, y + d, Color.Of(255, 0, 255));
				image.Set(x + cell - 1 - d, y + d, Color.Of(255, 0, 255));
			}
		}
	}

	return image;
}

/// The colors of two palettes mixed: weight 0 gives 'from', 256 gives 'to'. Only the art entries are mixed, entry 0 and
/// the user interface entries keep the colors of 'from' (Ziele Z4: palette effects never touch the user interface).
/// Writes into 'target' (Size * 3 bytes), so a frame needs no new array.
void BlendPalettes(Palette from, Palette to, int weight, uint8[] target)
{
	int w = weight < 0 ? 0 : weight > 256 ? 256 : weight;

	for (var i = 0; i < from.Size * 3; i += 1)
		target[i] = from.Rgb[i];

	int end = Math.Min(from.FirstUi(), to.FirstUi());

	for (var i = 3; i < end * 3; i += 1)
		target[i] = (uint8)(((int)from.Rgb[i] * (256 - w) + (int)to.Rgb[i] * w) >> 8);
}

/// The art entries of the colors mixed towards one color (flash, lightning): weight 0 none, 256 all of it.
void TintPalette(uint8[] rgb, int size, uint32 color, int weight)
{
	int w = weight < 0 ? 0 : weight > 256 ? 256 : weight;
	int end = size - UiColorCount;

	for (var i = 1; i < end; i += 1)
	{
		for (var channel = 0; channel < 3; channel += 1)
		{
			int value = (int)((color >> (16 - 8 * channel)) & 0xFF);
			int at = i * 3 + channel;

			rgb[at] = (uint8)(((int)rgb[at] * (256 - w) + value * w) >> 8);
		}
	}
}

/// A night palette made from a day palette: the art entries darker and bluer, the user interface entries unchanged. For
/// maps without a night palette of their own.
Palette NightOf(Palette day)
{
	var night = day.Clone();

	night.Name = day.Name + "_night";

	for (var i = 1; i < day.FirstUi(); i += 1)
	{
		if (!day.Used[i])
			continue;

		int r = (int)day.Rgb[i * 3];
		int g = (int)day.Rgb[i * 3 + 1];
		int b = (int)day.Rgb[i * 3 + 2];
		int gray = (r * 30 + g * 59 + b * 11) / 100;

		// less saturation, less light, a blue cast (moonlight)
		r = (r + gray) / 2;
		g = (g + gray) / 2;
		b = (b + gray) / 2;
		night.Rgb[i * 3] = (uint8)(r * 30 / 100 + 4);
		night.Rgb[i * 3 + 1] = (uint8)(g * 36 / 100 + 8);
		night.Rgb[i * 3 + 2] = (uint8)Math.Min(255, b * 52 / 100 + 22);
	}

	return night;
}
