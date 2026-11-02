namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Graphics;

void RegisterPaletteTests(ref TestList tests)
{
	tests.Fact("Palette.EntryZeroIsTransparentAndTheUiColorsAreAtTheEnd", EntryZeroIsTransparentAndTheUiColorsAreAtTheEnd);
	tests.Fact("Palette.TheArtIsSortedGraysFirstThenByHueAndBrightness", TheArtIsSortedGraysFirstThenByHueAndBrightness);
	tests.Fact("Palette.TheGplFileKeepsFreeEntriesFree", TheGplFileKeepsFreeEntriesFree);
	tests.Fact("Palette.ABasePaletteKeepsItsEntriesInPlace", ABasePaletteKeepsItsEntriesInPlace);
	tests.Fact("Palette.TooManyColorsAreMergedIntoTheFreeEntries", TooManyColorsAreMergedIntoTheFreeEntries);
	tests.Fact("Palette.FourBitsGiveTheColorsOfTheOldAmigas", FourBitsGiveTheColorsOfTheOldAmigas);
	tests.Fact("Palette.APictureUsesOnlyTheEntriesOfItsRange", APictureUsesOnlyTheEntriesOfItsRange);
	tests.Fact("Palette.APalettePngKeepsTheIndices", APalettePngKeepsTheIndices);
	tests.Fact("Palette.AnotherPaletteChangesOnlyTheColors", AnotherPaletteChangesOnlyTheColors);
	tests.Fact("Palette.BlendingKeepsTheUserInterfaceEntries", BlendingKeepsTheUserInterfaceEntries);
	tests.Theory("Palette.MistakesAreNamed", PaletteMistakesAreNamed, "GIMP Palette\n1 2 3 a\n", "16, 32, 64, 128 or 256 entries");
	tests.Theory("Palette.MistakesAreNamed", PaletteMistakesAreNamed, "JASC-PAL\n", "not a GIMP palette");
	tests.Theory("Palette.MistakesAreNamed", PaletteMistakesAreNamed, "GIMP Palette\n1 2 300 a\n", "0 to 255");
	tests.Theory("Palette.MistakesAreNamed", PaletteMistakesAreNamed, "GIMP Palette\n1 2\n", "red green blue");
}

/// A picture with the colors in a row, each 'count' pixels wide (1 pixel high); a color with alpha 0 is transparent.
Image Strip(uint32[] colors, int[] alphas)
{
	var image = Image.Create(colors.Length, 1);

	for (var i = 0; i < colors.Length; i += 1)
		image.Set(i, 0, Color.OfAlpha((int)((colors[i] >> 16) & 0xFF), (int)((colors[i] >> 8) & 0xFF), (int)(colors[i] & 0xFF), alphas[i]));

	return image;
}

Image OpaqueStrip(uint32[] colors)
{
	var alphas = new int[colors.Length];

	for (var i = 0; i < colors.Length; i += 1)
		alphas[i] = 255;

	return Strip(colors, alphas);
}

ColorHistogram HistogramOf(Image image, int bits)
{
	var histogram = ColorHistogram.Create();

	histogram.AddImage(image, bits);

	return histogram;
}

List<uint32> UiColors()
{
	var colors = List<uint32>.Create();

	for (var i = 0; i < 8; i += 1)
		colors.Add((uint32)(0x101010 * (i + 1)));

	return colors;
}

Error<void> EntryZeroIsTransparentAndTheUiColorsAreAtTheEnd()
{
	var image = Strip(new uint32[] { 0xFF0000, 0x00FF00, 0x123456 }, new int[] { 255, 255, 0 });
	var options = PaletteOptions.Create(32, "test");

	options.HasUiColors = true;
	options.UiColors = UiColors();

	var build = try BuildPalette(HistogramOf(image, 8), options);
	var palette = build.Palette;

	try Assert.Equal(32, palette.Size);
	try Assert.Equal(2, build.NewColors);
	try Assert.Equal(2, palette.UsedCount(PaletteRange.Art));
	try Assert.Equal(8, palette.UsedCount(PaletteRange.Ui));
	try Assert.Equal(24, palette.FirstUi());
	try Assert.Equal((int64)0x101010, (int64)palette.ColorAt(24));
	try Assert.Equal((int64)0x808080, (int64)palette.ColorAt(31));
	try Assert.False(palette.Used[3]);

	// the transparent color is not in the palette
	for (var i = 1; i < 32; i += 1)
		try Assert.True(palette.ColorAt(i) != 0x123456 || !palette.Used[i], "the transparent color got entry " + i);

	return;
}

Error<void> TheArtIsSortedGraysFirstThenByHueAndBrightness()
{
	// red (hue 0), dark green, bright green (hue 120), gray, blue (hue 240)
	var image = OpaqueStrip(new uint32[] { 0x0000C0, 0x00FF00, 0x808080, 0x006000, 0xC00000 });
	var build = try BuildPalette(HistogramOf(image, 8), PaletteOptions.Create(16, "sorted"));
	var palette = build.Palette;

	try Assert.Equal((int64)0x808080, (int64)palette.ColorAt(1));
	try Assert.Equal((int64)0xC00000, (int64)palette.ColorAt(2));
	try Assert.Equal((int64)0x006000, (int64)palette.ColorAt(3));
	try Assert.Equal((int64)0x00FF00, (int64)palette.ColorAt(4));
	try Assert.Equal((int64)0x0000C0, (int64)palette.ColorAt(5));

	return;
}

Error<void> TheGplFileKeepsFreeEntriesFree()
{
	var image = OpaqueStrip(new uint32[] { 0xFF0000, 0x00FF00 });
	var options = PaletteOptions.Create(32, "roundtrip");

	options.HasUiColors = true;
	options.UiColors = UiColors();

	var palette = (try BuildPalette(HistogramOf(image, 8), options)).Palette;
	string text = PaletteToGpl(palette);

	try Assert.Contains("GIMP Palette", text);
	try Assert.Contains("Name: roundtrip", text);
	try Assert.Contains("transparent", text);
	try Assert.Contains("ui 7", text);
	try Assert.Contains("unused", text);

	var read = try ParsePaletteGpl(text, "roundtrip.gpl");

	try Assert.Equal("roundtrip", read.Name);
	try Assert.Equal(32, read.Size);

	for (var i = 0; i < 32; i += 1)
	{
		try Assert.Equal(palette.Used[i], read.Used[i]);
		try Assert.Equal((int64)palette.ColorAt(i), (int64)read.ColorAt(i));
	}

	return;
}

Error<void> ABasePaletteKeepsItsEntriesInPlace()
{
	var first = (try BuildPalette(HistogramOf(OpaqueStrip(new uint32[] { 0xC00000, 0x00C000 }), 8), PaletteOptions.Create(32, "base"))).Palette;
	var options = PaletteOptions.Create(32, "more");

	options.HasBase = true;
	options.Base = first;

	// the gray sorts before red and green, but they keep their entries
	var build = try BuildPalette(HistogramOf(OpaqueStrip(new uint32[] { 0x00C000, 0x808080, 0xC00000 }), 8), options);
	var palette = build.Palette;

	try Assert.Equal(1, build.NewColors);
	try Assert.Equal((int64)first.ColorAt(1), (int64)palette.ColorAt(1));
	try Assert.Equal((int64)first.ColorAt(2), (int64)palette.ColorAt(2));
	try Assert.Equal((int64)0x808080, (int64)palette.ColorAt(3));
	// the base itself did not change
	try Assert.False(first.Used[3]);

	return;
}

Error<void> TooManyColorsAreMergedIntoTheFreeEntries()
{
	var colors = new uint32[200];

	for (var i = 0; i < 200; i += 1)
		colors[i] = (uint32)((i * 1237) % 256) << 16 | (uint32)((i * 5) % 256) << 8 | (uint32)((i * 71) % 256);

	var image = OpaqueStrip(colors);
	var build = try BuildPalette(HistogramOf(image, 8), PaletteOptions.Create(32, "small"));

	try Assert.True(build.Reduced);
	try Assert.Equal(23, build.Palette.UsedCount(PaletteRange.Art));
	try Assert.Equal(0, build.Palette.UsedCount(PaletteRange.Ui));

	var picture = try IndexImage(image, build.Palette, PaletteRange.Art, 8);

	try Assert.Equal(200, picture.Exact + picture.Approximated);

	// the same pictures give the same palette
	var again = try BuildPalette(HistogramOf(image, 8), PaletteOptions.Create(32, "small"));

	try Assert.Equal(PaletteToGpl(build.Palette), PaletteToGpl(again.Palette));

	return;
}

Error<void> FourBitsGiveTheColorsOfTheOldAmigas()
{
	try Assert.Equal((int64)0xFF8800, (int64)ReduceColor(0xFE8A07, 4));
	try Assert.Equal((int64)0x112233, (int64)ReduceColor(0x112233, 4));

	var options = PaletteOptions.Create(32, "ocs");

	options.Bits = 4;

	// two colors that are the same in 12 bits become one entry
	var build = try BuildPalette(HistogramOf(OpaqueStrip(new uint32[] { 0xFE8A07, 0xFF8800, 0x000000 }), 4), options);

	try Assert.Equal(2, build.Palette.UsedCount(PaletteRange.Art));

	for (var i = 1; i < build.Palette.Size; i += 1)
	{
		uint32 rgb = build.Palette.ColorAt(i);

		try Assert.Equal((int64)rgb, (int64)ReduceColor(rgb, 4));
	}

	return;
}

Error<void> APictureUsesOnlyTheEntriesOfItsRange()
{
	var options = PaletteOptions.Create(32, "ranges");

	options.HasUiColors = true;
	options.UiColors = UiColors();

	var palette = (try BuildPalette(HistogramOf(OpaqueStrip(new uint32[] { 0xFF0000, 0x0000FF }), 8), options)).Palette;
	// 0x101010 is exactly ui 0, but art pictures must not use the UI entries
	var image = Strip(new uint32[] { 0xFF0000, 0x101010, 0x00FF00, 0xFFFFFF }, new int[] { 255, 255, 255, 0 });
	var art = try IndexImage(image, palette, PaletteRange.Art, 8);

	try Assert.Equal(1, art.Exact);
	try Assert.Equal(2, art.Approximated);
	try Assert.Equal(0, (int64)art.Indices[3]);

	for (var i = 0; i < 3; i += 1)
		try Assert.True((int)art.Indices[i] >= 1 && (int)art.Indices[i] < 24, "pixel " + i + " got entry " + art.Indices[i]);

	var ui = try IndexImage(image, palette, PaletteRange.Ui, 8);

	try Assert.Equal(24, (int64)ui.Indices[1]);

	for (var i = 0; i < 3; i += 1)
		try Assert.True((int)ui.Indices[i] >= 24, "pixel " + i + " got entry " + ui.Indices[i]);

	return;
}

Error<void> APalettePngKeepsTheIndices()
{
	var options = PaletteOptions.Create(32, "png");

	options.HasUiColors = true;
	options.UiColors = UiColors();

	var image = Strip(new uint32[] { 0xFF0000, 0x00FF00, 0x0000FF, 0 }, new int[] { 255, 255, 255, 0 });
	var palette = (try BuildPalette(HistogramOf(image, 8), options)).Palette;
	var picture = try IndexImage(image, palette, PaletteRange.Art, 8);
	var decoded = try DecodePngPicture(EncodePalettePng(picture.Width, picture.Height, picture.Indices, palette));

	try Assert.True(decoded.IsIndexed());
	try Assert.Equal(32, decoded.PaletteCount);
	try Assert.Bytes(picture.Indices, decoded.Indices);
	// entry 0 is transparent in the PNG, the others opaque with the palette colors
	try Assert.Equal(0, decoded.Rgba.Alpha(3, 0));
	try Assert.Equal(255, decoded.Rgba.Alpha(0, 0));
	try Assert.Equal(255, (int64)decoded.Rgba.Data[0]);
	try Assert.Equal((int64)0x80, (int64)decoded.PaletteRgba[31 * 4]);

	return;
}

Error<void> AnotherPaletteChangesOnlyTheColors()
{
	var day = (try BuildPalette(HistogramOf(OpaqueStrip(new uint32[] { 0xC08040, 0x40C080 }), 8), PaletteOptions.Create(32, "day"))).Palette;
	var night = day.Clone();

	for (var i = 1; i < night.FirstUi(); i += 1)
	{
		if (night.Used[i])
			night.Set(i, (night.ColorAt(i) >> 1) & 0x7F7F7F);
	}

	var picture = try IndexImage(OpaqueStrip(new uint32[] { 0xC08040, 0x40C080 }), day, PaletteRange.Art, 8);
	var dark = RenderIndexed(picture.Width, picture.Height, picture.Indices, night);

	try Assert.Equal(0x60, (int64)dark.Data[0]);
	try Assert.Equal(0x40, (int64)dark.Data[1]);
	try Assert.Equal(0x20, (int64)dark.Data[2]);
	try Assert.Equal(0x20, (int64)dark.Data[4]);

	return;
}

Error<void> PaletteMistakesAreNamed(string[] arguments)
{
	var result = ParsePaletteGpl(arguments[0], "bad.gpl");

	if (result is error failure)
		return Assert.Contains(arguments[1], failure.Message);

	return Assert.Failure("the palette was read");
}

Error<void> BlendingKeepsTheUserInterfaceEntries()
{
	var options = PaletteOptions.Create(32, "day");

	options.HasUiColors = true;
	options.UiColors = UiColors();

	var day = (try BuildPalette(HistogramOf(OpaqueStrip(new uint32[] { 0xC08040, 0x40C080 }), 8), options)).Palette;
	var night = NightOf(day);
	var mixed = new uint8[32 * 3];

	// the night is darker in the art, the same in the user interface
	try Assert.True(night.Rgb[3] + night.Rgb[4] + night.Rgb[5] < day.Rgb[3] + day.Rgb[4] + day.Rgb[5], "the night is not darker");

	for (var i = 24 * 3; i < 32 * 3; i += 1)
		try Assert.Equal((int64)day.Rgb[i], (int64)night.Rgb[i]);

	BlendPalettes(day, night, 0, mixed);
	try Assert.Bytes(day.Rgb, mixed);
	BlendPalettes(day, night, 256, mixed);
	try Assert.Bytes(night.Rgb, mixed);
	BlendPalettes(day, night, 128, mixed);
	try Assert.Equal((int64)(((int)day.Rgb[3] + (int)night.Rgb[3]) / 2), (int64)mixed[3]);

	// a flash tints the art, never the user interface
	TintPalette(mixed, 32, 0xFFFFFF, 256);
	try Assert.Equal(255, (int64)mixed[3]);

	for (var i = 24 * 3; i < 32 * 3; i += 1)
		try Assert.Equal((int64)night.Rgb[i], (int64)mixed[i]);

	return;
}
