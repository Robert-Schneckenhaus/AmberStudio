// The studio without a window, driven by a script (scripts/test.sh runs game/tests/studio.txt): every frame is drawn as
// in the window (the same App.Draw), with an input that the script makes. A line is a command; "#" starts a comment.
//
//   size W H                   the frame (default 1400 x 860)
//   project PATH               opens the project
//   frame [N]                  N frames without input
//   move X Y | click X Y | rclick X Y      the mouse in pixels of the frame
//   key NAME [ctrl] [shift]    a key (F5, S, Z, Escape, Left ...)
//   type TEXT                  typed text
//   map NAME | tab NAME        opens a map | the tab (Karte, Spiel, Datenbank, Gespräche, Text)
//   tool NAME | layer N | gid N            map tools: paint, erase, pick, terrain
//   hover X Y | paint X Y [X2 Y2]          the mouse over a cell of the map | a stroke from one cell to another
//   ticks N | gamekey NAME     the game: N ticks (no clock) | a key pressed for one tick
//   section NAME | record KEY | setfield FIELD VALUE | addrecord KEY | removerecord | usage
//   npc NAME | entry N | settext KEY TEXT | addtopic WORD | CONDITION | TEXT | removeentry
//   save | undo | redo | check | dump (prints the entry of the database that is chosen)
//   shot PATH                  the frame as PNG
//   expect WHAT ...            tab NAME, errors N, tile LAYER X Y GID, game running|stopped, game-map NAME, dirty true|false,
//                              field SECTION KEY FIELD VALUE, text KEY VALUE, line FILE N TEXT, status TEXT,
//                              message TEXT, npcs N, entries N, records SECTION N
//
// Returns the number of failed expectations (an unknown command counts as one).

namespace Amber.Studio;

using System;
using System.Image;
using System.Ui;
using Amber.Base;
using Amber.Player.Editor;

struct StudioTest
{
	Ui Ui;
	App App;
	int Width;
	int Height;
	int MouseX;
	int MouseY;
	bool Down;
	Image Frame;
	int Failures;
	int Line;

	void Fail(string text)
	{
		Console.WriteLine("FAILED (line " + Line + "): " + text);
		Failures += 1;
	}

	UiInput Input()
	{
		var input = UiInput.Create();

		input.MouseX = MouseX;
		input.MouseY = MouseY;
		input.MouseDown = Down;

		return input;
	}

	/// A frame with the input, then the frames the layout asks for (the button stays as it is).
	void Run(UiInput input)
	{
		Draw(input);

		for (var i = 0; i < 6 && Ui.WaitMilliseconds() == 0; i += 1)
			Draw(Input());
	}

	void Draw(UiInput input)
	{
		Ui.Begin(input, Width, Height, 1.0);
		App.Draw(Ui, Width, Height);
		App.AfterFrame();
		Frame = Ui.End();
	}

	void Press(int x, int y)
	{
		MouseX = x;
		MouseY = y;
		Down = true;

		var input = Input();

		input.MousePressed = true;
		Run(input);
	}

	void Release(int x, int y)
	{
		MouseX = x;
		MouseY = y;
		Down = false;

		var input = Input();

		input.MouseReleased = true;
		Run(input);
	}

	/// The middle of a cell of the open map in pixels of the frame.
	bool CellPoint(int cellX, int cellY, ref int x, ref int y)
	{
		if (!App.HasMap())
			return false;

		var map = App.Map.Map();
		var r = App.Map.CanvasRect();

		if (r.Width <= 0 || map.Width <= 0)
			return false;

		x = r.X + (cellX * 2 + 1) * r.Width / (map.Width * 2);
		y = r.Y + (cellY * 2 + 1) * r.Height / (map.Height * 2);

		return true;
	}

	void Command(string[] p, string line)
	{
		string c = p[0];

		if (c == "size")
		{
			Width = Number(p, 1);
			Height = Number(p, 2);
		}
		else if (c == "project")
		{
			if (App.OpenProject(Ui, p[1]) is error e)
				Fail(e.Message);

			Run(Input());
		}
		else if (c == "frame")
		{
			int count = p.Length > 1 ? Number(p, 1) : 1;

			for (var i = 0; i < count; i += 1)
				Run(Input());
		}
		else if (c == "move")
		{
			MouseX = Number(p, 1);
			MouseY = Number(p, 2);
			Run(Input());
		}
		else if (c == "click" || c == "rclick")
		{
			int x = Number(p, 1);
			int y = Number(p, 2);

			if (c == "click")
			{
				Press(x, y);
				Release(x, y);
			}
			else
			{
				MouseX = x;
				MouseY = y;

				var down = Input();

				down.RightDown = true;
				down.RightPressed = true;
				Run(down);

				var up = Input();

				up.RightReleased = true;
				Run(up);
			}
		}
		else if (c == "key")
		{
			var input = Input();
			var modifiers = KeyModifiers.None;

			for (var i = 2; i < p.Length; i += 1)
			{
				if (p[i] == "ctrl")
				{
					modifiers = modifiers | KeyModifiers.Ctrl;
					input.Ctrl = true;
				}
				else if (p[i] == "shift")
				{
					modifiers = modifiers | KeyModifiers.Shift;
					input.Shift = true;
				}
			}

			input.AddKey(UiKeyNamed(p[1]), modifiers);
			Run(input);
		}
		else if (c == "type")
		{
			var input = Input();

			input.Text = Rest(line, 1);
			Run(input);
		}
		else if (c == "map")
		{
			App.OpenMap(p[1]);
			Run(Input());
		}
		else if (c == "tab")
		{
			App.SetTab(TabNamed(p[1]));
			Run(Input());
		}
		else if (c == "tool")
		{
			App.Map.SetTool(p[1] == "erase" ? EditorTool.Erase : p[1] == "pick" ? EditorTool.Pick : p[1] == "terrain" ? EditorTool.Terrain : EditorTool.Paint);
			Run(Input());
		}
		else if (c == "layer")
		{
			App.Map.SetLayer(Number(p, 1));
			Run(Input());
		}
		else if (c == "gid")
		{
			App.Map.SelectGid((uint32)Number(p, 1));
			Run(Input());
		}
		else if (c == "hover" || c == "paint")
		{
			int x = 0;
			int y = 0;

			if (!CellPoint(Number(p, 1), Number(p, 2), ref x, ref y))
			{
				Fail("no map is shown");

				return;
			}

			if (c == "hover")
			{
				MouseX = x;
				MouseY = y;
				Run(Input());

				return;
			}

			Press(x, y);

			if (p.Length >= 5)
			{
				int x2 = 0;
				int y2 = 0;

				CellPoint(Number(p, 3), Number(p, 4), ref x2, ref y2);

				// along the way, a few steps
				for (var step = 1; step <= 4; step += 1)
				{
					MouseX = x + (x2 - x) * step / 4;
					MouseY = y + (y2 - y) * step / 4;
					Run(Input());
				}

				x = x2;
				y = y2;
			}

			Release(x, y);
		}
		else if (c == "ticks")
		{
			for (var i = 0; i < Number(p, 1); i += 1)
			{
				if (App.Game.Tick() is error e)
				{
					Fail("game: " + e.Message);

					break;
				}
			}

			App.Game.Render();
			Run(Input());
		}
		else if (c == "gamekey")
		{
			var key = EngineKey(UiKeyNamed(p[1]));

			App.Game.Input.KeyDown(key);

			if (App.Game.Tick() is error e)
				Fail("game: " + e.Message);

			App.Game.Input.KeyUp(key);
			App.Game.Render();
			Run(Input());
		}
		else if (c == "section")
		{
			App.Tables.SelectSection(p[1]);
			App.SetTab(TabData);
			Run(Input());
		}
		else if (c == "record")
		{
			if (!App.Tables.SelectRecord(p[1]))
				Fail("no entry " + p[1]);

			Run(Input());
		}
		else if (c == "setfield")
		{
			if (App.Tables.SetField(App.Tables.SelectedKey(), p[1], Rest(line, 2)))
				App.Edited(App.Project.TablesPath());
			else
				Fail("setfield " + p[1] + ": " + App.Tables.Message());

			Run(Input());
		}
		else if (c == "addrecord")
		{
			if (App.Tables.AddRecord(p[1]))
			{
				App.Edited(App.Project.TablesPath());
				App.Tables.SelectRecord(p[1]);
			}
			else
				Fail("addrecord: " + App.Tables.Message());

			Run(Input());
		}
		else if (c == "removerecord")
		{
			if (App.Tables.RemoveRecord())
				App.Edited(App.Project.TablesPath());
			else
				Fail("removerecord");

			Run(Input());
		}
		else if (c == "usage")
		{
			string prefix = PrefixOfSection(App.Tables.SectionName());

			App.FindUsages(prefix + "." + App.Tables.SelectedKey());
			Run(Input());
		}
		else if (c == "npc")
		{
			if (!App.Talks.SelectName(p[1]))
				Fail("no NPC " + p[1]);

			App.SetTab(TabTalks);
			Run(Input());
		}
		else if (c == "entry")
		{
			App.Talks.SelectEntry(Number(p, 1));
			Run(Input());
		}
		else if (c == "settext")
		{
			if (App.Talks.SetText(p[1], Rest(line, 2)))
				App.Edited(App.Project.TablesPath());
			else
				Fail("settext: " + App.Talks.Message());

			Run(Input());
		}
		else if (c == "addtopic" || c == "removeentry")
		{
			if (App.Talks.Current() is not TalkNpc npc)
			{
				Fail("no NPC chosen");

				return;
			}

			bool done = false;

			if (c == "addtopic")
			{
				var parts = SplitToList(Rest(line, 1), "|");

				done = App.Talks.AddTopic(npc, Part(parts, 0), Part(parts, 1), Part(parts, 2));
			}
			else if (App.Talks.EntryIndex() >= 0 && App.Talks.EntryIndex() < npc.Entries.Count())
				done = App.Talks.RemoveEntry(npc, npc.Entries.Get(App.Talks.EntryIndex()));

			if (done)
				App.Edited(npc.Script);
			else
				Fail(c + ": " + App.Talks.Message());

			Run(Input());
		}
		else if (c == "save")
		{
			App.SaveAll();
			Run(Input());
		}
		else if (c == "undo")
		{
			App.Undo();
			Run(Input());
		}
		else if (c == "redo")
		{
			App.Redo();
			Run(Input());
		}
		else if (c == "check")
		{
			App.Check();
			Run(Input());
		}
		else if (c == "shot")
		{
			string directory = System.Path.GetDirectory(p[1]);

			if (directory.Length > 0)
				Directory.Create(directory);

			if (Frame.Save(p[1]) is error e)
				Fail("cannot save " + p[1]);
			else
				Console.WriteLine("Screenshot: " + p[1]);
		}
		else if (c == "dump")
		{
			if (App.Tables.Selected() is TableRecord record)
			{
				Console.WriteLine("record " + record.Key + " lines " + record.Line + ".." + record.EndLine + " scalar " + record.Scalar);

				foreach (var field in record.Fields)
					Console.WriteLine("  " + field.Name + " = " + field.Value + " (line " + field.Line + "): " + App.Tables.Doc.Lines.Get(field.Line) + " v" + App.Tables.Doc.Version());
			}
			else
				Console.WriteLine("no record");
		}
		else if (c == "expect")
			Expect(p, line);
		else
			Fail("unknown command: " + line);
	}

	void Expect(string[] p, string line)
	{
		string what = p.Length > 1 ? p[1] : "";

		if (what == "tab")
			Check(App.Tab() == TabNamed(p[2]), "tab " + p[2] + ", but it is " + App.Tab());
		else if (what == "errors")
		{
			int count = App.ErrorCount();

			if (count != Number(p, 2))
			{
				foreach (var message in App.Messages)
					Console.WriteLine("  " + message.Label());
			}

			Check(count == Number(p, 2), "errors " + p[2] + ", but there are " + count);
		}
		else if (what == "tile")
		{
			var layer = App.Map.Map().Layers.Get(Number(p, 2));
			uint32 gid = Amber.Player.Tiled.GidOf(layer.Get(Number(p, 3), Number(p, 4)));

			Check(gid == (uint32)Number(p, 5), "tile " + p[3] + "," + p[4] + " of layer " + p[2] + " is " + gid + ", not " + p[5]);
		}
		else if (what == "game")
			Check(App.Game.Running() == (p[2] == "running"), "the game is " + (App.Game.Running() ? "running" : "stopped"));
		else if (what == "game-map")
		{
			if (App.Game.Game().Debug("expect map " + p[2]) is error e)
				Fail(e.Message);
		}
		else if (what == "game-debug")
		{
			if (App.Game.Game().Debug(Rest(line, 2)) is error e)
				Fail(e.Message);
		}
		else if (what == "dirty")
			Check(App.Dirty() == (p[2] == "true"), "dirty " + p[2]);
		else if (what == "field")
		{
			App.Tables.SelectSection(p[2]);

			string value = "?";

			if (App.Tables.SelectRecord(p[3]) && App.Tables.Selected() is TableRecord record)
			{
				if (record.Scalar)
					value = record.Value;
				else if (record.Field(p[4]) is TableField field)
					value = field.Value;
			}

			Check(value == Rest(line, 5), p[2] + "." + p[3] + "." + p[4] + " is '" + value + "', not '" + Rest(line, 5) + "'");
		}
		else if (what == "text")
			Check(App.Talks.TextOf(p[2]) == Rest(line, 3), "T." + p[2] + " is '" + App.Talks.TextOf(p[2]) + "'");
		else if (what == "line")
		{
			string path = System.Path.Combine(App.Project.Content, p[2]);
			string text = Rest(line, 4);

			if (App.Doc(path) is TextDoc doc && Number(p, 3) - 1 < doc.Lines.Count())
				Check(doc.Lines.Get(Number(p, 3) - 1).Contains(text), p[2] + ":" + p[3] + " is '" + doc.Lines.Get(Number(p, 3) - 1) + "'");
			else
				Fail("no line " + p[3] + " in " + p[2]);
		}
		else if (what == "file-contains")
		{
			string path = System.Path.Combine(App.Project.Content, p[2]);
			var read = File.ReadAllText(path);

			Check(read is string text && text.Contains(Rest(line, 3)), p[2] + " does not contain '" + Rest(line, 3) + "'");
		}
		else if (what == "status")
			Check(App.Status().Contains(Rest(line, 2)), "status is '" + App.Status() + "'");
		else if (what == "message")
		{
			bool found = false;

			foreach (var message in App.Messages)
			{
				if (message.Label().Contains(Rest(line, 2)))
					found = true;
			}

			Check(found, "no message with '" + Rest(line, 2) + "'");
		}
		else if (what == "npcs")
			Check(App.Talks.Count() == Number(p, 2), "npcs " + p[2] + ", but there are " + App.Talks.Count());
		else if (what == "entries")
		{
			int count = App.Talks.Current() is TalkNpc npc ? npc.Entries.Count() : -1;

			Check(count == Number(p, 2), "entries " + p[2] + ", but there are " + count);
		}
		else if (what == "records")
		{
			App.Tables.SelectSection(p[2]);

			int count = -1;

			foreach (var section in App.Tables.Sections)
			{
				if (section.Name == p[2])
					count = section.Records.Count();
			}

			Check(count == Number(p, 3), "records of " + p[2] + ": " + count);
		}
		else
			Fail("unknown expectation: " + line);
	}

	void Check(bool ok, string text)
	{
		if (!ok)
			Fail(text);
	}
}

int Number(string[] parts, int index)
{
	if (index < parts.Length && TryParseInt(parts[index]) is int value)
		return value;

	return 0;
}

/// The text of the line after the first `skip` words.
string Rest(string line, int skip)
{
	string rest = line.Trim().ToString();

	for (var i = 0; i < skip; i += 1)
	{
		int space = rest.IndexOf(' ');

		if (space < 0)
			return "";

		rest = rest.Substring(space + 1).TrimStart().ToString();
	}

	return rest;
}

string Part(List<string> parts, int index)
{
	return index < parts.Count() ? parts.Get(index).Trim().ToString() : "";
}

int TabNamed(string name)
{
	string lower = name.ToLower();

	if (lower.StartsWith("spiel") || lower == "game")
		return TabGame;

	if (lower.StartsWith("daten") || lower == "data")
		return TabData;

	if (lower.StartsWith("gespr") || lower == "talks")
		return TabTalks;

	if (lower.StartsWith("text"))
		return TabText;

	return TabMap;
}

System.Ui.Key UiKeyNamed(string name)
{
	if (name.Length == 1 && name[0] >= 'A' && name[0] <= 'Z')
		return (System.Ui.Key)((int)System.Ui.Key.A + (int)name[0] - (int)'A');

	if (name.Length >= 2 && name[0] == 'F' && TryParseInt(name.Substring(1)) is int f && f >= 1 && f <= 12)
		return (System.Ui.Key)((int)System.Ui.Key.F1 + f - 1);

	switch (name)
	{
	case "Escape":
		return System.Ui.Key.Escape;
	case "Enter":
		return System.Ui.Key.Enter;
	case "Space":
		return System.Ui.Key.Space;
	case "Tab":
		return System.Ui.Key.Tab;
	case "Left":
		return System.Ui.Key.Left;
	case "Right":
		return System.Ui.Key.Right;
	case "Up":
		return System.Ui.Key.Up;
	case "Down":
		return System.Ui.Key.Down;
	case "Delete":
		return System.Ui.Key.Delete;
	case "Backspace":
		return System.Ui.Key.Backspace;
	default:
		return System.Ui.Key.None;
	}
}

int RunStudioTest(string path, string project)
{
	var read = File.ReadAllText(path);

	if (read is not string text)
	{
		Console.WriteErrorLine("amberstudio: cannot read " + path);

		return 1;
	}

	var test = StudioTest { Ui = Ui.Create(), App = App.Create(), Width = 1400, Height = 860, MouseX = -1, MouseY = -1, Frame = Image.Create(1, 1) };

	if (project.Length > 0)
	{
		if (test.App.OpenProject(test.Ui, project) is error e)
		{
			Console.WriteErrorLine("amberstudio: " + e.Message);

			return 1;
		}
	}

	test.Run(test.Input());

	var lines = SplitToList(text, "\n");

	for (var i = 0; i < lines.Count(); i += 1)
	{
		string line = lines.Get(i).Trim().ToString();

		test.Line = i + 1;

		if (line.Length == 0 || line.StartsWith("#"))
			continue;

		test.Command(SplitWhitespace(line), line);
	}

	Console.WriteLine(test.Failures == 0 ? "Studio test ok: " + path : "Studio test: " + test.Failures + " failure(s)");

	return test.Failures;
}
