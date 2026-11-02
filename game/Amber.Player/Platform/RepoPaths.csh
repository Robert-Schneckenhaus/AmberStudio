namespace Amber.Player.Platform;

using System;
using Amber.Base;

/// The repository root (C#: RepoPaths.Root): the folder with game/content/tables.yaml, found from the current folder
/// upwards unless --root names it. The third party packs (tilesets, characters, icons) are expected in <root>/assets.
string RepositoryRoot = ".";

Error<string> FindRepositoryRoot(string given)
{
	if (given != null)
		return given;

	string candidate = ".";

	for (var i = 0; i < 8; i += 1)
	{
		if (File.Exists(candidate + "/game/content/tables.yaml"))
			return candidate;

		candidate = candidate == "." ? ".." : candidate + "/..";
	}

	return error("Could not find the repository root (start the game in the repository or pass --root <dir>).", (int)ErrorKind.Io);
}

string DefaultContent()
{
	return Path.Combine(RepositoryRoot, "game/content");
}

string TilesetDirectory()
{
	return Path.Combine(RepositoryRoot, "assets/ManaSeedSummerForest/sample map/TSX files");
}
