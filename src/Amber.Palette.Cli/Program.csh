// amberpal - palettes and palette pictures: build a palette from PNG pictures, turn PNG pictures
// into palette pictures, swap the palette of a palette picture, draw a palette.

using System;
using Amber.Base;
using Amber.Graphics;

const string Usage = "amberpal - palettes and palette pictures\n"
	+ "\n"
	+ "Usage:\n"
	+ "  amberpal extract <png>... --out <palette.gpl> [--size <n>] [--bits 8|4] [--range art|ui] [--ui <ui.gpl>] [--base <palette.gpl>]\n"
	+ "                   [--name <name>] [--swatch <swatch.png>]\n"
	+ "  amberpal index   <png>... --palette <palette.gpl> --out <file.png|directory> [--range art|ui|all] [--bits 8|4]\n"
	+ "  amberpal apply   <palette picture.png> --palette <palette.gpl> --out <file.png> [--rgba]\n"
	+ "  amberpal swatch  <palette.gpl> --out <swatch.png> [--cell <pixels>]\n"
	+ "\n"
	+ "Every palette has 16, 32, 64, 128 or 256 entries (default 256; 32 for the old Amigas). Entry 0 is transparent, the\n"
	+ "last 8 entries are the user interface colors (frames and everything else that is always visible), the entries\n"
	+ "between them are the art. Palettes are GIMP palettes (.gpl); entries named 'unused' are free.\n"
	+ "\n"
	+ "extract   collects the colors of the pictures and fills the free art entries (--range ui: the UI entries). If there\n"
	+ "          are more colors than free entries, median cut merges them. --base keeps the entries of an existing\n"
	+ "          palette in their place (the palette pictures made with it stay valid), --ui puts the colors of a .gpl\n"
	+ "          file (up to 8, or the last 8 of a palette) into the UI entries, --bits 4 rounds to the 12-bit colors of\n"
	+ "          the old Amigas.\n"
	+ "index     writes every picture as an 8-bit palette PNG with the colors of the palette, using only the entries of\n"
	+ "          the range (default art), and says how many pixels did not fit exactly. Several pictures need a directory.\n"
	+ "apply     gives a palette picture another palette with the same entries (day and night, another map): the indices\n"
	+ "          stay, only the colors change. --rgba writes a normal RGBA PNG instead.\n"
	+ "swatch    draws the palette, 16 entries per row; free entries are crossed out.\n"
	+ "\n"
	+ "Pixels with alpha below 128 become transparent (entry 0), the others opaque.";

int Main(string[] args)
{
	if (args.Length == 0 || args[0] == "-h" || args[0] == "--help")
	{
		Console.WriteLine(Usage);

		return 0;
	}

	var line = CommandLine.Parse(args);

	if (line.Problem != null)
		return Fail(line.Problem);

	Error<void> result;

	switch (args[0])
	{
		case "extract":
			result = Extract(line);
			break;
		case "index":
			result = Index(line);
			break;
		case "apply":
			result = Apply(line);
			break;
		case "swatch":
			result = Swatch(line);
			break;
		default:
			Console.WriteErrorLine("Unknown command '" + args[0] + "'.\n\n" + Usage);

			return 2;
	}

	if (result is error failure)
		return Fail(failure.Message);

	return 0;
}

int Fail(string message)
{
	Console.WriteErrorLine("error: " + message);

	return 1;
}

/// The options of a command.
struct CommandLine
{
	List<string> Inputs;
	string Out;
	string PalettePath;
	string UiPath;
	string BasePath;
	string Name;
	string SwatchPath;
	int Size;
	int Bits;
	int Cell;
	PaletteRange Range;
	bool RangeGiven;
	bool Rgba;
	string Problem;

	static CommandLine Parse(string[] arguments)
	{
		var line = CommandLine { Inputs = List<string>.Create(), Size = 256, Bits = 8, Cell = 12, Range = PaletteRange.Art };

		for (var i = 1; i < arguments.Length; i += 1)
		{
			string argument = arguments[i];
			bool hasValue = i + 1 < arguments.Length;
			string value = hasValue ? arguments[i + 1] : null;

			if (argument == "--rgba")
				line.Rgba = true;
			else if (!argument.StartsWith("--"))
				line.Inputs.Add(argument);
			else if (!hasValue)
				line.Problem = argument + " needs a value";
			else
			{
				i += 1;

				if (argument == "--out")
					line.Out = value;
				else if (argument == "--palette")
					line.PalettePath = value;
				else if (argument == "--ui")
					line.UiPath = value;
				else if (argument == "--base")
					line.BasePath = value;
				else if (argument == "--name")
					line.Name = value;
				else if (argument == "--swatch")
					line.SwatchPath = value;
				else if (argument == "--size")
					line.Size = TryParseInt(value) is int size ? size : -1;
				else if (argument == "--bits")
					line.Bits = TryParseInt(value) is int bits ? bits : -1;
				else if (argument == "--cell")
					line.Cell = TryParseInt(value) is int cell ? cell : -1;
				else if (argument == "--range")
				{
					line.RangeGiven = true;

					if (ParseRange(value) is PaletteRange range)
						line.Range = range;
					else
						line.Problem = "--range is art, ui or all";
				}
				else
					line.Problem = "unknown option " + argument;
			}
		}

		if (line.Problem == null && !IsPaletteSize(line.Size))
			line.Problem = "--size is 16, 32, 64, 128 or 256";

		if (line.Problem == null && line.Bits != 8 && line.Bits != 4)
			line.Problem = "--bits is 8 or 4";

		if (line.Problem == null && (line.Cell < 1 || line.Cell > 64))
			line.Problem = "--cell is 1 to 64";

		return line;
	}
}

Optional<PaletteRange> ParseRange(string text)
{
	if (text == "art")
		return PaletteRange.Art;

	if (text == "ui")
		return PaletteRange.Ui;

	if (text == "all")
		return PaletteRange.All;

	return null;
}

Error<void> Extract(CommandLine line)
{
	if (line.Inputs.Count() == 0 || line.Out == null)
		return error("extract needs pictures and --out", (int)ErrorKind.Argument);

	if (line.Range == PaletteRange.All)
		return error("extract fills the art (--range art) or the user interface (--range ui)", (int)ErrorKind.Argument);

	var histogram = ColorHistogram.Create();

	foreach (var path in line.Inputs)
		histogram.AddImage(try LoadPng(path), line.Bits);

	var options = PaletteOptions.Create(line.Size, line.Name != null ? line.Name : Path.GetStem(line.Out).ToString());

	options.Bits = line.Bits;
	options.Range = line.Range;

	if (line.BasePath != null)
	{
		options.HasBase = true;
		options.Base = try LoadPalette(line.BasePath);

		if (!line.RangeGiven && line.Size == 256)
			options.Size = options.Base.Size;
	}

	if (line.UiPath != null)
	{
		options.HasUiColors = true;
		options.UiColors = try LoadUiColors(line.UiPath);
	}

	var build = try BuildPalette(histogram, options);

	try SavePalette(line.Out, build.Palette);
	Console.WriteLine(DescribeBuild(build, histogram, line.Range));
	Console.WriteLine("Wrote " + line.Out);

	if (line.SwatchPath != null)
	{
		try SavePng(line.SwatchPath, PaletteSwatch(build.Palette, line.Cell));
		Console.WriteLine("Wrote " + line.SwatchPath);
	}

	return;
}

Error<void> Index(CommandLine line)
{
	if (line.Inputs.Count() == 0 || line.Out == null || line.PalettePath == null)
		return error("index needs pictures, --palette and --out", (int)ErrorKind.Argument);

	var palette = try LoadPalette(line.PalettePath);
	bool toDirectory = line.Inputs.Count() > 1 || Directory.Exists(line.Out) || !line.Out.ToLower().EndsWith(".png");

	if (toDirectory && !Directory.Exists(line.Out))
		Directory.Create(line.Out);

	foreach (var path in line.Inputs)
	{
		var image = try LoadPng(path);
		var picture = try IndexImage(image, palette, line.Range, line.Bits);
		string target = toDirectory ? Path.Combine(line.Out, Path.GetFileName(path)).ToString() : line.Out;

		try File.WriteAllBytes(target, EncodePalettePng(picture.Width, picture.Height, picture.Indices, palette));

		string report = target + ": " + picture.Exact + " pixels exact, " + picture.Approximated + " nearest color";

		if (picture.Approximated > 0)
			report = report + " (worst distance " + picture.WorstDistance + ")";

		if (picture.SemiTransparent > 0)
			report = report + ", " + picture.SemiTransparent + " partly transparent";

		Console.WriteLine(report);
	}

	return;
}

Error<void> Apply(CommandLine line)
{
	if (line.Inputs.Count() != 1 || line.Out == null || line.PalettePath == null)
		return error("apply needs one palette picture, --palette and --out", (int)ErrorKind.Argument);

	var data = File.ReadAllBytes(line.Inputs.Get(0));

	if (data is uint8[] bytes)
	{
		var picture = try DecodePngPicture(bytes);

		if (!picture.IsIndexed())
			return error(line.Inputs.Get(0) + " is not a palette picture (make one with 'amberpal index')", (int)ErrorKind.InvalidData);

		var palette = try LoadPalette(line.PalettePath);

		if (picture.PaletteCount > palette.Size)
			return error(line.Inputs.Get(0) + " has " + picture.PaletteCount + " colors, the palette only " + palette.Size, (int)ErrorKind.InvalidData);

		int width = picture.Rgba.Width;
		int height = picture.Rgba.Height;

		if (line.Rgba)
			try SavePng(line.Out, RenderIndexed(width, height, picture.Indices, palette));
		else
			try File.WriteAllBytes(line.Out, EncodePalettePng(width, height, picture.Indices, palette));

		Console.WriteLine("Wrote " + line.Out);

		return;
	}

	return error("cannot read '" + line.Inputs.Get(0) + "': " + data.Message, (int)ErrorKind.Io);
}

Error<void> Swatch(CommandLine line)
{
	if (line.Inputs.Count() != 1 || line.Out == null)
		return error("swatch needs one palette and --out", (int)ErrorKind.Argument);

	var palette = try LoadPalette(line.Inputs.Get(0));

	try SavePng(line.Out, PaletteSwatch(palette, line.Cell));
	Console.WriteLine("Wrote " + line.Out);

	return;
}
