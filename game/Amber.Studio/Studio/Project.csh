// The project that is open: a game folder of the engine (the content folder with tables.yaml, maps, scripts and
// screens) and the folder above it in which assets/ lies. The studio has no file format of its own: it reads and
// writes the files that the game, the tests, Git and VS Code use.

namespace Amber.Studio;

using System;
using Amber.Base;

/// Where the browser copies a folder that the user chose (FileDialogMode.Folder) and where a written file becomes a
/// download.
const string BrowserFiles = "/home/web_user/files";
const string BrowserDownloads = "/home/web_user/downloads";

struct StudioProject
{
	/// The folder with assets/ (the repository): the game looks for its tilesets, figures and icons there.
	string Root;
	/// The content folder (tables.yaml, maps/, scripts/, screens/).
	string Content;
	/// The name shown in the tree.
	string Name;
	/// The maps (maps/*.tmx without the extension), the scripts and the screens (file names).
	List<string> Maps;
	List<string> Scripts;
	List<string> Screens;

	/// The project of a folder: a repository (with game/content), a content folder (with tables.yaml) or a folder
	/// above it.
	static Error<StudioProject> Open(string folder)
	{
		string path = Path.Normalize(folder);

		if (path.EndsWith("/") && path.Length > 1)
			path = path.Substring(0, path.Length - 1);

		string content = "";
		string root = "";

		if (File.Exists(Path.Combine(path, "game/content/tables.yaml")))
		{
			root = path;
			content = Path.Combine(path, "game/content");
		}
		else if (File.Exists(Path.Combine(path, "tables.yaml")))
		{
			content = path;
			string up = Path.GetDirectory(Path.GetDirectory(path));

			root = up.Length > 0 && Directory.Exists(Path.Combine(up, "assets")) ? up : path;
		}
		else if (File.Exists(Path.Combine(path, "content/tables.yaml")))
		{
			content = Path.Combine(path, "content");
			root = Directory.Exists(Path.Combine(path, "assets")) ? path : Path.GetDirectory(path);
		}
		else
			return error("Kein Amber-Projekt: " + folder + " (gesucht: tables.yaml, content/tables.yaml oder game/content/tables.yaml)",
				(int)ErrorKind.Io);

		var project = StudioProject
		{
			Root = root.Length > 0 ? root : ".", Content = content, Name = Path.GetFileName(root.Length > 0 ? root : content), Maps = List<string>.Create(),
			Scripts = List<string>.Create(), Screens = List<string>.Create()
		};

		if (project.Name.Length == 0)
			project.Name = "Projekt";

		project.Scan();

		return project;
	}

	void Scan()
	{
		Maps.Clear();
		Scripts.Clear();
		Screens.Clear();

		foreach (var name in Directory.GetEntries(Path.Combine(Content, "maps")))
		{
			if (name.EndsWith(".tmx") && !name.Contains("edit_test"))
				Maps.Add(name.Substring(0, name.Length - 4));
		}

		foreach (var name in Directory.GetEntries(Path.Combine(Content, "scripts")))
		{
			if (name.EndsWith(".ams"))
				Scripts.Add(name);
		}

		foreach (var name in Directory.GetEntries(Path.Combine(Content, "screens")))
		{
			if (name.EndsWith(".yaml"))
				Screens.Add(name);
		}
	}

	string MapPath(string name)
	{
		return Path.Combine(Path.Combine(Content, "maps"), name + ".tmx");
	}

	string ScriptPath(string name)
	{
		return Path.Combine(Path.Combine(Content, "scripts"), name);
	}

	string ScreenPath(string name)
	{
		return Path.Combine(Path.Combine(Content, "screens"), name);
	}

	string TablesPath()
	{
		return Path.Combine(Content, "tables.yaml");
	}

	/// True if the project lies in the file system of a browser page (the files go out as downloads).
	bool InBrowser()
	{
		return RunsInBrowser();
	}
}

/// True in a browser page (its file system has the folder the browser copies the user's files to).
bool RunsInBrowser()
{
	return Directory.Exists("/home/web_user");
}

/// In the browser a saved file is also offered as a download (the page cannot write the user's folder).
void OfferDownload(string path)
{
	if (!RunsInBrowser())
		return;

	if (File.ReadAllBytes(path) is uint8[] bytes)
	{
		Directory.Create(BrowserDownloads);
		File.WriteAllBytes(Path.Combine(BrowserDownloads, Path.GetFileName(path)), bytes);
	}
}
