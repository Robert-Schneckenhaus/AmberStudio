// amberstudio - the editor of the games of the Amber engine (docs: game/Amber.Studio/
// README.md). A window of System.Ui: on Windows and Linux, and in the browser with the wasm backend of CShift.
//
//   amberstudio [--project <folder>]           the window; without a folder the repository around the current folder
//   amberstudio --test <script> [--project f]  no window: the script drives the studio (see StudioTest.csh)
//   --browser                                  in a web page (scripts/studio-page.sh): a larger Ui, saved files download

using System;
using System.Ui;
using Amber.Studio;

int Main(string[] args)
{
	string project = "";
	string script = "";

	for (var i = 0; i < args.Length; i += 1)
	{
		if (args[i] == "--project" && i + 1 < args.Length)
		{
			project = args[i + 1];
			i += 1;
		}
		else if (args[i] == "--browser")
			BrowserPage = true;
		else if (args[i] == "--test" && i + 1 < args.Length)
		{
			script = args[i + 1];
			i += 1;
		}
	}

	if (script.Length > 0)
		return RunStudioTest(script, project);

	var opened = Window.Open("Amber Studio", 1400, 860);

	if (opened is not Window window)
	{
		Console.WriteErrorLine("amberstudio: kein Fenster: " + opened.Message);

		return 1;
	}

	window.ConfirmClose(true);

	var ui = Ui.Create();
	var app = App.Create();

	app.UseDefaultZoom();

	if (project.Length == 0)
		project = FindProjectFolder();

	bool first = true;

	while (!app.QuitRequested() && window.Update())
	{
		ui.Begin(window, app.Zoom());

		if (first && project.Length > 0)
		{
			if (app.OpenProject(ui, project) is error e)
				app.Say(e.Message);
		}

		first = false;
		app.Draw(ui, window.Width(), window.Height());
		app.AfterFrame();
		window.Show(ui);
	}

	window.Dispose();

	return 0;
}

/// The repository around the current folder (the one with game/content), "" if there is none (the browser).
string FindProjectFolder()
{
	// the page of GitHub Pages carries the content of the game as an example project (scripts/studio-page.sh)
	if (File.Exists("demo/game/content/tables.yaml"))
		return "demo";

	string folder = Directory.GetCurrentDirectory();

	for (var i = 0; i < 6 && folder.Length > 0; i += 1)
	{
		if (File.Exists(Path.Combine(folder, "game/content/tables.yaml")))
			return folder;

		string up = Path.GetDirectory(folder);

		if (up == folder)
			break;

		folder = up;
	}

	return "";
}
