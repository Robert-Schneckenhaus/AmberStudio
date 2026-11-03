// The window of the studio: one fixed layout. The menu bar on top; on the left the
// project (maps, scripts, database, conversations, screens); in the middle the area of what is chosen (map, game,
// database, conversations, text) with the messages under it; on the right the properties of what is chosen. The
// borders between them are splitters.

namespace Amber.Studio;

using System;
using System.Image;
using System.Ui;
using Amber.Base;
using Amber.Player.Editor;

const int TabMap = 0;
const int TabGame = 1;
const int TabData = 2;
const int TabTalks = 3;
const int TabText = 4;

struct AppValues
{
	bool HasProject;
	bool HasMap;
	int Tab;
	/// The entry of the tree that is chosen ("map:village", "script:glade.ams", "table:items", "npc:glade.ams:bram").
	string Selected;
	/// The text tab: the file, the line to show (1-based, 0 none) and whether it still has to scroll there.
	string TextFile;
	int TextLine;
	bool TextScroll;
	int TreeWidth;
	int CenterWidth;
	int ContentHeight;
	bool Opening;
	string OpenPath;
	bool AskQuit;
	bool Quit;
	bool Dark;
	string Status;
	int FrameWidth;
	int FrameHeight;
	/// The game was started from the map tab (it goes back there when the game ends).
	bool PlayFromMap;
	/// The text document that was changed last (undo in the data and conversation tabs).
	string LastDoc;
	int Message;
	/// The tree opens its main nodes in the next frame (a new project).
	bool OpenTree;
	/// The size of the Ui on top of the scale of the screen (Ansicht: Größer, Kleiner).
	double Zoom;
	bool GameWasRunning;
}

/// The studio; a handle.
struct App
{
	AppValues[] _s;
	StudioProject Project;
	List<StudioMessage> Messages;
	MapView Map;
	Dictionary<string, MapView> Maps;
	GameView Game;
	Dictionary<string, TextDoc> Docs;
	TableView Tables;
	TalkView Talks;

	static App Create()
	{
		var values = new AppValues[1];

		values[0].Selected = "";
		values[0].TextFile = "";
		values[0].TreeWidth = 230;
		values[0].CenterWidth = 760;
		values[0].ContentHeight = 520;
		values[0].OpenPath = "";
		values[0].Status = "";
		values[0].LastDoc = "";
		values[0].Message = -1;
		values[0].Zoom = 1.0;

		return App
		{
			_s = values, Messages = List<StudioMessage>.Create(), Maps = Dictionary<string, MapView>.Create(), Game = GameView.Create(),
			Docs = Dictionary<string, TextDoc>.Create(), Tables = TableView.Create(), Talks = TalkView.Create()
		};
	}

	bool HasMap()
	{
		return _s[0].HasMap;
	}

	bool HasProject()
	{
		return _s[0].HasProject;
	}

	bool QuitRequested()
	{
		return _s[0].Quit;
	}

	double Zoom()
	{
		return _s[0].Zoom;
	}

	/// In the browser the canvas has the pixels of the screen (devicePixelRatio 1 on most desktops): a size larger, so
	/// that the Ui takes its larger font (10x20).
	void UseDefaultZoom()
	{
		_s[0].Zoom = RunsInBrowser() ? 1.5 : 1.0;
	}

	/// One step larger or smaller: 100 %, 150 %, 200 %, 300 % (the steps at which the Ui has a sharp font).
	void ZoomBy(int step)
	{
		var steps = new double[] { 1.0, 1.5, 2.0, 3.0 };
		int at = 0;

		for (var i = 0; i < steps.Length; i += 1)
		{
			if (steps[i] <= _s[0].Zoom + 0.01)
				at = i;
		}

		_s[0].Zoom = steps[Clamp(at + step, 0, steps.Length - 1)];
	}

	int Tab()
	{
		return _s[0].Tab;
	}

	void SetTab(int tab)
	{
		_s[0].Tab = tab;
	}

	string Status()
	{
		return _s[0].Status;
	}

	void Say(string text)
	{
		_s[0].Status = text;
	}

	// ---- the project ----

	/// Opens the project of the folder and checks it.
	Error<void> OpenProject(Ui ui, string folder)
	{
		var project = try StudioProject.Open(folder);

		Project = project;
		Amber.Player.Platform.RepositoryRoot = project.Root;
		Maps.Clear();
		Docs.Clear();
		_s[0].HasProject = true;
		_s[0].HasMap = false;
		_s[0].Selected = "";
		Game.Stop();
		_s[0].OpenTree = true;
		Reload();
		Check();

		if (project.Maps.Count() > 0)
			OpenMap(project.Maps.Contains(StartMap()) ? StartMap() : project.Maps.Get(0));

		Say("Projekt " + project.Name + " geöffnet: " + project.Content);

		return;
	}

	/// The map where a new game starts (tables.yaml start: map), "" if the tables do not name one.
	string StartMap()
	{
		foreach (var section in Tables.Sections)
		{
			if (section.Name != "start")
				continue;

			foreach (var record in section.Records)
			{
				if (record.Key == "map")
					return record.Value;
			}
		}

		return "";
	}

	/// Reads the database and the conversations again (after a save, an undo or a change of a text).
	void Reload()
	{
		if (Doc(Project.TablesPath()) is TextDoc tables)
			Tables.Load(tables);

		var scripts = List<TextDoc>.Create();

		foreach (var name in Project.Scripts)
		{
			if (Doc(Project.ScriptPath(name)) is TextDoc script)
				scripts.Add(script);
		}

		if (Doc(Project.TablesPath()) is TextDoc texts)
			Talks.Load(scripts, texts);
	}

	/// The text document of a file (read once, then the one in memory, with its changes).
	Optional<TextDoc> Doc(string path)
	{
		if (Docs.TryGet(path) is TextDoc doc)
			return doc;

		if (TextDoc.Load(path) is TextDoc loaded)
		{
			Docs.Set(path, loaded);

			return loaded;
		}

		Messages.Add(StudioMessage.Of(MessageKind.Error, "Kann " + path + " nicht lesen."));

		return null;
	}

	/// The check of the content (with the files as they are saved).
	void Check()
	{
		Messages.Clear();
		Messages.AddRange(CheckProject(Project).ToArray());
		_s[0].Message = -1;
	}

	int ErrorCount()
	{
		int count = 0;

		foreach (var message in Messages)
		{
			if (message.Kind == MessageKind.Error)
				count += 1;
		}

		return count;
	}

	bool Dirty()
	{
		foreach (var map in Maps.Values())
		{
			if (map.Doc.Dirty())
				return true;
		}

		foreach (var doc in Docs.Values())
		{
			if (doc.Dirty())
				return true;
		}

		return false;
	}

	/// Saves every changed map and file, then checks the content again.
	void SaveAll()
	{
		int saved = 0;

		foreach (var map in Maps.Values())
		{
			if (map.Doc.Dirty())
			{
				if (map.Save() is error e)
					Messages.Add(StudioMessage.Of(MessageKind.Error, e.Message));
				else
					saved += 1;
			}
		}

		foreach (var doc in Docs.Values())
		{
			if (doc.Dirty())
			{
				if (doc.Save() is error e)
					Messages.Add(StudioMessage.Of(MessageKind.Error, e.Message));
				else
					saved += 1;
			}
		}

		Check();
		Say(saved == 0 ? "Nichts zu speichern" : saved + " Datei(en) gespeichert" + (Project.InBrowser() ? " (als Download)" : ""));
	}

	void OpenMap(string name)
	{
		if (Maps.TryGet(name) is MapView open)
		{
			Map = open;
		}
		else
		{
			var opened = MapView.Open(name, Project.MapPath(name));

			if (opened is not MapView view)
			{
				Messages.Add(StudioMessage.At(MessageKind.Error, opened.Message, Project.MapPath(name), 0));

				return;
			}

			Maps.Set(name, view);
			Map = view;
		}

		_s[0].HasMap = true;
		_s[0].Selected = "map:" + name;
		_s[0].Tab = TabMap;
	}

	/// The text tab with the file, at the line (0: from the top).
	void OpenText(string path, int line)
	{
		if (!(Doc(path) is TextDoc))
			return;

		_s[0].TextFile = path;
		_s[0].TextLine = line;
		_s[0].TextScroll = line > 0;
		_s[0].Tab = TabText;
	}

	/// What a click on a message does: a map opens, a file opens at the line.
	void OpenMessage(StudioMessage message)
	{
		if (message.File.Length == 0)
			return;

		if (message.File.EndsWith(".tmx"))
			OpenMap(System.Path.GetStem(message.File));
		else
			OpenText(message.File, message.Line);
	}

	// ---- playing ----

	/// F5: the game on the open map at the cell under the mouse (or where the mouse was last), else from its start.
	void Play()
	{
		string map = "";
		int x = 0;
		int y = 0;

		if (_s[0].HasMap)
		{
			if (Map.Hovered(ref x, ref y) || (x > 0 || y > 0))
				map = Map.Name;
			else
			{
				map = Map.Name;
				x = Map.Map().Width / 2;
				y = Map.Map().Height / 2;
			}
		}

		_s[0].PlayFromMap = _s[0].Tab == TabMap;

		if (Game.Start(Project, map, x, y, "") is error e)
		{
			Messages.Add(StudioMessage.Of(MessageKind.Error, "Spiel: " + e.Message));
			Say("Das Spiel startet nicht: " + e.Message);

			return;
		}

		_s[0].Tab = TabGame;
		Say(Game.Status());
	}

	void StopGame()
	{
		Game.Stop();
		Say(Game.Status());

		if (_s[0].PlayFromMap && _s[0].HasMap)
			_s[0].Tab = TabMap;
	}

	// ---- undo ----

	void Undo()
	{
		if (_s[0].Tab == TabMap && _s[0].HasMap)
		{
			Map.Undo();

			return;
		}

		if (Docs.TryGet(_s[0].Tab == TabText ? _s[0].TextFile : _s[0].LastDoc) is TextDoc doc && doc.Undo())
			Reload();
	}

	void Redo()
	{
		if (_s[0].Tab == TabMap && _s[0].HasMap)
		{
			Map.Redo();

			return;
		}

		if (Docs.TryGet(_s[0].Tab == TabText ? _s[0].TextFile : _s[0].LastDoc) is TextDoc doc && doc.Redo())
			Reload();
	}

	/// A text document was changed by the data or the conversation tab.
	void Edited(string path)
	{
		_s[0].LastDoc = path;
		Reload();
	}

	/// What the widgets asked for that needs the whole project: "Wo benutzt?" of the database.
	void AfterFrame()
	{
		// the game ended by itself (Escape in the world): back to the map
		if (_s[0].GameWasRunning && !Game.Running())
			StopGame();

		_s[0].GameWasRunning = Game.Running();

		string usage = Tables.TakeUsage();

		if (usage.Length > 0)
			FindUsages(usage);
	}

	/// The places of the scripts that name the symbol ("I.herb") become messages.
	void FindUsages(string symbol)
	{
		for (var i = Messages.Count() - 1; i >= 0; i -= 1)
		{
			if (Messages.Get(i).Kind == MessageKind.Found)
				Messages.RemoveAt(i);
		}

		int found = 0;

		foreach (var name in Project.Scripts)
		{
			string path = Project.ScriptPath(name);

			if (Doc(path) is not TextDoc doc)
				continue;

			for (var i = 0; i < doc.Lines.Count(); i += 1)
			{
				string line = doc.Lines.Get(i);

				if (NamesSymbol(line, symbol))
				{
					Messages.Add(StudioMessage.At(MessageKind.Found, name + ":" + (i + 1) + ": " + line.Trim().ToString(), path, i + 1));
					found += 1;
				}
			}
		}

		Say(found == 0 ? symbol + " kommt in keinem Skript vor" : symbol + ": " + found + " Stelle(n) in den Skripten");
	}

	// ---- the frame ----

	/// Shortcuts that work everywhere (before the widgets, which would take the keys otherwise).
	void Shortcuts(Ui ui)
	{
		var input = ui.Input();

		if (input.Pressed(System.Ui.Key.O, KeyModifiers.Ctrl))
			_s[0].Opening = true;

		if (input.Pressed(System.Ui.Key.Plus, KeyModifiers.Ctrl))
			ZoomBy(1);

		if (input.Pressed(System.Ui.Key.Minus, KeyModifiers.Ctrl))
			ZoomBy(-1);

		if (input.Pressed(System.Ui.Key.D0, KeyModifiers.Ctrl))
			_s[0].Zoom = 1.0;

		if (!_s[0].HasProject)
			return;

		if (input.Pressed(System.Ui.Key.F5, KeyModifiers.Shift))
			StopGame();
		else if (input.Pressed(System.Ui.Key.F5))
			Play();

		if (input.Pressed(System.Ui.Key.S, KeyModifiers.Ctrl))
			SaveAll();

		if (input.Pressed(System.Ui.Key.F7))
		{
			Check();
			Say(ErrorCount() == 0 ? "Keine Fehler" : ErrorCount() + " Fehler");
		}

		if (_s[0].Tab != TabGame || !Game.Running())
		{
			if (input.Pressed(System.Ui.Key.Z, KeyModifiers.Ctrl))
				Undo();

			if (input.Pressed(System.Ui.Key.Y, KeyModifiers.Ctrl) || input.Pressed(System.Ui.Key.Z, KeyModifiers.Ctrl | KeyModifiers.Shift))
				Redo();
		}
	}

	/// The whole window for a frame of `width` x `height` pixels.
	void Draw(Ui ui, int width, int height)
	{
		_s[0].FrameWidth = width;
		_s[0].FrameHeight = height;
		ui.SetTheme(_s[0].Dark ? Theme.Dark() : Theme.Light());

		if (ui.Input().CloseRequested)
		{
			if (Dirty())
				_s[0].AskQuit = true;
			else
				_s[0].Quit = true;
		}

		Shortcuts(ui);
		DrawMenu(ui);

		if (_s[0].HasProject)
			DrawProject(ui);
		else
			DrawWelcome(ui);

		DrawDialogs(ui);
	}

	void DrawMenu(Ui ui)
	{
		using (ui.MenuBar())
		{
			using (ui.Menu("Projekt"))
			{
				if (ui.MenuItem("Öffnen...", "Ctrl+O"))
					_s[0].Opening = true;

				if (_s[0].HasProject)
				{
					if (ui.MenuItem("Alles speichern", "Ctrl+S"))
						SaveAll();

					if (ui.MenuItem("Prüfen", "F7"))
						Check();
				}

				ui.Separator();

				if (ui.MenuItem("Beenden"))
				{
					if (Dirty())
						_s[0].AskQuit = true;
					else
						_s[0].Quit = true;
				}
			}

			if (_s[0].HasProject)
			{
				using (ui.Menu("Bearbeiten"))
				{
					if (ui.MenuItem("Rückgängig", "Ctrl+Z"))
						Undo();

					if (ui.MenuItem("Wiederholen", "Ctrl+Y"))
						Redo();
				}

				using (ui.Menu("Spiel"))
				{
					if (ui.MenuItem("Spielen ab hier", "F5"))
						Play();

					if (ui.MenuItem("Spiel beenden", "Shift+F5"))
						StopGame();
				}
			}

			using (ui.Menu("Ansicht"))
			{
				if (ui.MenuItem(_s[0].Dark ? "Helles Thema" : "Dunkles Thema"))
					_s[0].Dark = !_s[0].Dark;

				ui.Separator();

				if (ui.MenuItem("Größer", "Ctrl+Plus"))
					ZoomBy(1);

				if (ui.MenuItem("Kleiner", "Ctrl+Minus"))
					ZoomBy(-1);

				if (ui.MenuItem("Normale Größe", "Ctrl+0"))
					_s[0].Zoom = 1.0;
			}
		}
	}

	void DrawWelcome(Ui ui)
	{
		using (ui.Panel("Amber Studio"))
		{
			ui.Text("Ein Projekt ist ein Spielordner der Amber-Engine: der Ordner mit tables.yaml, maps/, scripts/ und screens/, oder das Repository mit game/content. Die Bilder (assets/) liegen im Ordner darüber.");

			if (ui.Button("Projekt öffnen..."))
				_s[0].Opening = true;

			if (_s[0].Status.Length > 0)
				ui.Note(_s[0].Status);
		}
	}

	void DrawDialogs(Ui ui)
	{
		if (_s[0].Opening)
		{
			var result = ui.FileDialog("project", "Projektordner öffnen", ref _s[0].OpenPath, FileDialogMode.Folder);

			if (result == UiDialogResult.Ok)
			{
				_s[0].Opening = false;

				if (OpenProject(ui, _s[0].OpenPath) is error e)
					Say(e.Message);
			}
			else if (result == UiDialogResult.Cancel)
				_s[0].Opening = false;
		}

		if (_s[0].AskQuit)
		{
			using (ui.Modal("quit", "Ungespeicherte Änderungen"))
			{
				ui.Label("Es gibt Änderungen, die noch nicht gespeichert sind.");

				using (ui.Row())
				{
					if (ui.Button("Speichern und beenden"))
					{
						SaveAll();
						_s[0].Quit = true;
					}

					if (ui.Button("Verwerfen"))
						_s[0].Quit = true;

					if (ui.Button("Abbrechen"))
						_s[0].AskQuit = false;
				}
			}
		}
	}

	/// Pixels of the frame at scale 1.
	int Unscaled(Ui ui, int pixels)
	{
		double scale = ui.Scale() > 0.0 ? ui.Scale() : 1.0;

		return (int)((double)pixels / scale);
	}

	void DrawProject(Ui ui)
	{
		int width = Unscaled(ui, _s[0].FrameWidth);
		int height = Unscaled(ui, _s[0].FrameHeight);
		int top = Unscaled(ui, ui.LastRect().Y + ui.LastRect().Height);
		int rest = Math.Max(200, height - top - 24);

		_s[0].TreeWidth = Clamp(_s[0].TreeWidth, 120, Math.Max(120, width / 3));
		_s[0].CenterWidth = Clamp(_s[0].CenterWidth, 240, Math.Max(240, width - _s[0].TreeWidth - 200));

		using (ui.Row())
		{
			using (ui.Column(_s[0].TreeWidth))
			{
				using (ui.Scroll("tree", rest))
					DrawTree(ui);
			}

			ui.Splitter("tree", ref _s[0].TreeWidth, 120, Math.Max(120, width / 3));

			using (ui.Column(_s[0].CenterWidth))
				DrawCenter(ui, rest);

			ui.Splitter("center", ref _s[0].CenterWidth, 240, Math.Max(240, width - _s[0].TreeWidth - 200));

			using (ui.Column(0))
			{
				using (ui.Scroll("properties", rest))
					DrawProperties(ui, rest - 20);
			}
		}
	}

	void DrawTree(Ui ui)
	{
		var project = Project;

		if (_s[0].OpenTree)
		{
			// the ids of the nodes come from the groups around them: set where they are drawn
			_s[0].OpenTree = false;
			ui.SetTreeOpen(project.Name + "##root", true);

			using (ui.Indent())
			{
				ui.SetTreeOpen("Karten##maps", true);
				ui.SetTreeOpen("Datenbank##tables", true);
				ui.SetTreeOpen("Gespräche##talks", true);
			}
		}

		var root = ui.TreeNode(project.Name + "##root", false);

		if (!root.Open)
			return;

		using (ui.Indent())
		{
			if (ui.TreeNode("Karten##maps", false).Open)
			{
				using (ui.Indent())
				{
					foreach (var name in project.Maps)
					{
						if (ui.TreeLeaf(name + "##map", _s[0].Selected == "map:" + name))
							OpenMap(name);
					}
				}
			}

			if (ui.TreeNode("Datenbank##tables", false).Open)
			{
				using (ui.Indent())
				{
					foreach (var section in Tables.SectionNames())
					{
						if (ui.TreeLeaf(section + "##table", _s[0].Selected == "table:" + section))
						{
							_s[0].Selected = "table:" + section;
							Tables.SelectSection(section);
							_s[0].Tab = TabData;
						}
					}
				}
			}

			if (ui.TreeNode("Gespräche##talks", false).Open)
			{
				using (ui.Indent())
				{
					for (var i = 0; i < Talks.Count(); i += 1)
					{
						var npc = Talks.Get(i);
						string key = "npc:" + npc.Script + ":" + npc.Name;

						if (ui.TreeLeaf(npc.Name + " (" + System.Path.GetStem(npc.Script) + ")##" + key, _s[0].Selected == key))
						{
							_s[0].Selected = key;
							Talks.Select(i);
							_s[0].Tab = TabTalks;
						}
					}
				}
			}

			if (ui.TreeNode("Skripte##scripts", false).Open)
			{
				using (ui.Indent())
				{
					foreach (var name in project.Scripts)
					{
						if (ui.TreeLeaf(name + "##script", _s[0].Selected == "script:" + name))
						{
							_s[0].Selected = "script:" + name;
							OpenText(project.ScriptPath(name), 0);
						}
					}
				}
			}

			if (ui.TreeNode("Screens##screens", false).Open)
			{
				using (ui.Indent())
				{
					foreach (var name in project.Screens)
					{
						if (ui.TreeLeaf(name + "##screen", _s[0].Selected == "screen:" + name))
						{
							_s[0].Selected = "screen:" + name;
							OpenText(project.ScreenPath(name), 0);
						}
					}
				}
			}

			if (ui.TreeLeaf("tables.yaml##file", _s[0].Selected == "file:tables"))
			{
				_s[0].Selected = "file:tables";
				OpenText(project.TablesPath(), 0);
			}
		}
	}

	void DrawCenter(Ui ui, int height)
	{
		using (ui.TabBar())
		{
			ui.Tab("Karte", ref _s[0].Tab, TabMap);
			ui.Tab("Spiel", ref _s[0].Tab, TabGame);
			ui.Tab("Datenbank", ref _s[0].Tab, TabData);
			ui.Tab("Gespräche", ref _s[0].Tab, TabTalks);
			ui.Tab("Text", ref _s[0].Tab, TabText);
		}

		int tabs = Unscaled(ui, ui.LastRect().Height) + 6;
		int content = Clamp(_s[0].ContentHeight, 100, Math.Max(100, height - tabs - 90));

		_s[0].ContentHeight = content;

		switch (_s[0].Tab)
		{
		case TabMap:
			DrawMapTab(ui, content);
			break;
		case TabGame:
			DrawGameTab(ui, content);
			break;
		case TabData:
			if (Tables.Draw(ui, content))
				Edited(Project.TablesPath());
			break;
		case TabTalks:
		{
			string changed = Talks.Draw(ui, content);

			if (changed.Length > 0)
				Edited(changed);
		}
			break;
		default:
			DrawTextTab(ui, content);
			break;
		}

		ui.Splitter("messages", ref _s[0].ContentHeight, 100, Math.Max(100, height - tabs - 90));
		DrawMessages(ui);
	}

	void DrawMapTab(Ui ui, int height)
	{
		if (!_s[0].HasMap)
		{
			ui.Area("nomap", 0, height);
			ui.Note("Keine Karte offen: links eine Karte wählen.");

			return;
		}

		using (ui.Row())
		{
			ui.Label(Map.Name + (Map.Doc.Dirty() ? " *" : ""));

			if (ui.Button("Rückgängig"))
				Map.Undo();

			if (ui.Button("Wiederholen"))
				Map.Redo();

			if (ui.Button("Speichern"))
			{
				if (Map.Save() is error e)
					Say(e.Message);
				else
					Check();
			}

			if (ui.Button("Spielen ab hier (F5)"))
				Play();

			int x = 0;
			int y = 0;

			if (Map.Hovered(ref x, ref y))
				ui.Note("Feld " + x + ", " + y);
			else if (Map.Message().Length > 0)
				ui.Note(Map.Message());
		}

		Map.DrawCanvas(ui, Math.Max(60, height - Unscaled(ui, ui.LastRect().Height) - 8));
	}

	void DrawGameTab(Ui ui, int height)
	{
		using (ui.Row())
		{
			if (Game.Running())
			{
				if (ui.Button("Beenden (Shift+F5)"))
					StopGame();
			}
			else if (ui.Button("Starten (F5)"))
				Play();

			ui.Note(Game.Status().Length > 0 ? Game.Status() : "Das Spiel läuft hier im Studio; Escape in der Welt beendet es.");
		}

		bool wasRunning = Game.Running();

		if (Game.Draw(ui, Math.Max(60, height - Unscaled(ui, ui.LastRect().Height) - 8), true) is error e)
			Say(e.Message);

		if (wasRunning && !Game.Running())
			StopGame();
	}

	void DrawTextTab(Ui ui, int height)
	{
		if (Docs.TryGet(_s[0].TextFile) is not TextDoc doc)
		{
			ui.Area("notext", 0, height);
			ui.Note("Keine Datei offen: links ein Skript, einen Screen oder tables.yaml wählen.");

			return;
		}

		ui.Label(System.Path.GetFileName(doc.Path) + (doc.Dirty() ? " *" : "") + " - zum Bearbeiten in VS Code öffnen; die Prüfung zeigt die Fehler unten");

		var font = ui.Font();
		int lineHeight = font.LineHeight() + 2;
		int count = doc.Lines.Count();
		int view = Math.Max(40, height - Unscaled(ui, ui.LastRect().Height) - 8);
		var theme = ui.GetTheme();

		if (_s[0].TextScroll)
		{
			ui.SetScroll("text", 0, Math.Max(0, (_s[0].TextLine - 4) * lineHeight));
			_s[0].TextScroll = false;
		}

		using (ui.ScrollArea("text", 0, view))
		{
			int longest = 0;

			foreach (var line in doc.Lines)
				longest = Math.Max(longest, line.Length);

			var r = ui.Area("lines", 60 + longest * 8, Unscaled(ui, count * lineHeight) + 8);
			int first = Math.Max(0, ui.ScrollY("text") / lineHeight - 1);
			int last = Math.Min(count, first + ui.LastRect().Height / Math.Max(1, lineHeight) + view);

			for (var i = first; i < last; i += 1)
			{
				int y = r.Y + i * lineHeight;

				if (i + 1 == _s[0].TextLine)
					ui.FillRect(Rect.Create(r.X, y, r.Width, lineHeight), theme.Selection);

				ui.DrawText(r.X + 4, y + 1, PadNumber(i + 1, 4), theme.TextMuted);
				ui.DrawText(r.X + 4 + font.Measure("00000"), y + 1, doc.Lines.Get(i), theme.Text);
			}
		}
	}

	void DrawMessages(Ui ui)
	{
		using (ui.Row())
		{
			int errors = ErrorCount();

			ui.Label(errors == 0 ? "Meldungen" : "Meldungen: " + errors + " Fehler");

			if (ui.Button("Prüfen (F7)"))
				Check();

			if (_s[0].Status.Length > 0)
				ui.Note(_s[0].Status);
		}

		using (ui.Scroll("messages", 0))
		{
			for (var i = 0; i < Messages.Count(); i += 1)
			{
				var message = Messages.Get(i);

				using (ui.Id(i))
				{
					if (ui.ListItem(message.Label() + "##message", _s[0].Message == i))
					{
						_s[0].Message = i;
						OpenMessage(message);
					}
				}
			}
		}
	}

	void DrawProperties(Ui ui, int height)
	{
		switch (_s[0].Tab)
		{
		case TabMap:
			if (_s[0].HasMap)
				Map.DrawPanel(ui, height);
			break;
		case TabGame:
			DrawGameProperties(ui);
			break;
		case TabData:
			if (Tables.DrawProperties(ui))
				Edited(Project.TablesPath());
			break;
		case TabTalks:
		{
			string changed = Talks.DrawProperties(ui);

			if (changed.Length > 0)
				Edited(changed);
		}
			break;
		default:
			ui.Note("Die Datei ist hier nur zu lesen.");
			break;
		}
	}

	void DrawGameProperties(Ui ui)
	{
		ui.Label("Spiel");
		ui.Note(Game.Running() ? "läuft, " + Game.Ticks() + " Ticks" : "angehalten");
		ui.Note("Pfeiltasten gehen, Leertaste untersucht, T zielt, H heilt, P zeigt die Gruppe; Escape beendet das Spiel.");
	}
}

/// True if the line names the symbol as a whole ("I.herb", not "I.herbs").
bool NamesSymbol(string line, string symbol)
{
	int from = 0;

	while (from < line.Length)
	{
		int at = line.IndexOf(symbol, from);

		if (at < 0)
			return false;

		int after = at + symbol.Length;
		bool startOk = at == 0 || !IdentifierChar(line[at - 1]) && line[at - 1] != '.';
		bool endOk = after >= line.Length || !IdentifierChar(line[after]);

		if (startOk && endOk)
			return true;

		from = at + 1;
	}

	return false;
}

bool IdentifierChar(char c)
{
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_';
}

/// The number right-aligned in a field of the width.
string PadNumber(int value, int width)
{
	string text = "" + value;

	while (text.Length < width)
		text = " " + text;

	return text;
}
