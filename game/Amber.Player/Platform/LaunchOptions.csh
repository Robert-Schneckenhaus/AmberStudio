namespace Amber.Player.Platform;

using System;
using Amber.Base;

/// Command line of the prototype. The script options exist to check the game without a person at the keyboard: a script
/// drives the input frame by frame and can take screenshots.
struct LaunchOptions
{
	/// Text file with input script lines (see InputScript), or null.
	string Script;
	/// Content folder (maps, scripts, texts), or null for game/content of the repository.
	string Content;
	/// A cooked pack (--build-pack) to run from instead of cooking the content folder at the start, or null. The Tiled
	/// maps still come from the content folder.
	string Pack;
	/// The quick savegame (F2 saves, F3 loads), or null for game/saves/quick.amsv.
	string SavePath;
	/// Integer scale of the 320x200 virtual screen.
	int Scale;
	/// Write the generated map and script into the content folder and exit.
	bool GenerateContent;
	/// Start the map editor instead of the game (--edit [map]).
	bool Editor;
	/// Map to edit: a name of content/maps (village) or the path of a TMX file, or null.
	string EditTarget;
	/// The repository root (--root), or null to look for it from the current folder upwards.
	string Root;
	/// Run without a window (--headless): scripts run as fast as possible, screenshots are rendered in memory.
	bool Headless;

	static LaunchOptions Parse(string[] args)
	{
		var options = LaunchOptions { Scale = 4 };
		bool scaleGiven = false;

		for (var i = 0; i < args.Length; i += 1)
		{
			string next = i + 1 < args.Length ? args[i + 1] : null;

			if (args[i] == "--script" && next != null)
			{
				options.Script = next;
				i += 1;
			}
			else if (args[i] == "--content" && next != null)
			{
				options.Content = next;
				i += 1;
			}
			else if (args[i] == "--pack" && next != null)
			{
				options.Pack = next;
				i += 1;
			}
			else if (args[i] == "--save" && next != null)
			{
				options.SavePath = next;
				i += 1;
			}
			else if (args[i] == "--root" && next != null)
			{
				options.Root = next;
				i += 1;
			}
			else if (args[i] == "--scale" && next != null && TryParseInt(next) is int scale)
			{
				options.Scale = scale < 1 ? 1 : scale > 8 ? 8 : scale;
				scaleGiven = true;
				i += 1;
			}
			else if (args[i] == "--generate-content")
				options.GenerateContent = true;
			else if (args[i] == "--headless")
				options.Headless = true;
			else if (args[i] == "--edit")
			{
				options.Editor = true;

				if (next != null && !next.StartsWith("--"))
				{
					options.EditTarget = next;
					i += 1;
				}
			}
		}

		// the editor uses a bigger virtual screen (640x400), so a smaller scale gives a comfortable window
		if (options.Editor && !scaleGiven)
			options.Scale = 2;

		return options;
	}
}
