// amberplayer - plays a game of the engine (a content folder: tables.yaml, Tiled maps, AmberScript, screens), and the map
// editor and the developer tools (content check, pack cook).

using System;
using Amber.Base;
using Amber.Player.Content;
using Amber.Player.Editor;
using Amber.Player.Game;
using Amber.Player.Platform;
using Amber.Player.Tools;

int Main(string[] args)
{
	var options = LaunchOptions.Parse(args);
	var root = FindRepositoryRoot(options.Root);

	if (root is string found)
		RepositoryRoot = found;
	else
	{
		Console.WriteErrorLine(root.Message);

		return 1;
	}

	var result = Run(args, options);

	if (result is int code)
		return code;

	Console.WriteErrorLine("error: " + result.Message);

	return 1;
}

Error<int> Run(string[] args, LaunchOptions options)
{
	string contentFolder = options.Content != null ? options.Content : DefaultContent();

	if (args.Length >= 3 && args[0] == "--char-preview")
	{
		var looks = List<string>.Create();

		for (var i = 2; i < args.Length; i += 1)
		{
			if (args[i] == "--root")
				i += 1;
			else
				looks.Add(args[i]);
		}

		try CreateCharacterPreview(args[1], looks);

		return 0;
	}

	if (args.Length >= 3 && args[0] == "--preview-map")
	{
		int scale = 2;

		if (args.Length > 3 && args[3] != "--root")
			scale = try NumberArgument(args[3]);

		try CreateMapPreview(args[1], args[2], scale, HasArgument(args, "collision"), HasArgument(args, "grid"));

		return 0;
	}

	// dev tool: --map-palette <map.tmx>... --out <palette.gpl> [options of amberpal extract] [--all-tiles]
	if (args.Length >= 1 && args[0] == "--map-palette")
	{
		try CreateMapPalette(args);

		return 0;
	}

	// dev tool: --contact <sheet.png> <tileW> <tileH> <out.png> [col row cols rows [scale]]
	if (args.Length >= 5 && args[0] == "--contact")
	{
		var numbers = List<int>.Create();

		for (var i = 5; i < args.Length && args[i] != "--root"; i += 1)
			numbers.Add(try NumberArgument(args[i]));

		try CreateContactSheet(args[1], try NumberArgument(args[2]), try NumberArgument(args[3]), args[4], NumberOr(numbers, 0, 0), NumberOr(numbers, 1, 0),
			NumberOr(numbers, 2, 20), NumberOr(numbers, 3, 12), NumberOr(numbers, 4, 4));

		return 0;
	}

	if (args.Length >= 1 && args[0] == "--check-content")
	{
		var content = try ContentSource.Load(contentFolder, RepositoryRoot);

		Console.WriteLine("Content ok: " + content.Texts.Count() + " texts, " + content.Items.Count() + " items, " + content.Keywords.Count() + " keywords");

		foreach (var map in content.Compilation.Maps)
		{
			var entities = List<string>.Create();

			foreach (var entity in map.EntityInfos)
				entities.Add(entity.Name + "#" + entity.Id);

			Console.WriteLine("  map " + map.Name + ": " + map.Groups.Count() + " groups, " + map.Bindings.Count() + " bindings, entities: " + JoinList(", ", entities));
		}

		Console.WriteLine("Pack ok: " + (try PackCook.Verify(content, try PackCook.Cook(content))));

		return 0;
	}

	if (args.Length >= 2 && args[0] == "--build-pack")
	{
		var content = try ContentSource.Load(contentFolder, RepositoryRoot);
		var pack = try PackCook.Cook(content);

		try File.WriteAllBytes(args[1], pack);
		Console.WriteLine(args[1] + ": " + (try PackCook.Verify(content, pack)));

		return 0;
	}

	var game = new AnyGame();

	if (options.Editor)
	{
		// the editor uses a bigger virtual screen
		VirtualScreenWidth = 640;
		VirtualScreenHeight = 400;
		game = AnyGame.OfEditor(try MapEditorGame.Load(options));
	}
	else
		game = AnyGame.OfGame(try PrototypeGame.Load(options));

	if (options.Headless)
		return RunHeadless(game, options);

	return RunWindow(game, options);
}

Error<int> NumberArgument(string text)
{
	if (TryParseInt(text) is int value)
		return value;

	return error("'" + text + "' is not a number.", (int)ErrorKind.Argument);
}

int NumberOr(List<int> numbers, int index, int fallback)
{
	return index < numbers.Count() ? numbers.Get(index) : fallback;
}

bool HasArgument(string[] args, string name)
{
	foreach (var arg in args)
	{
		if (arg == name)
			return true;
	}

	return false;
}
