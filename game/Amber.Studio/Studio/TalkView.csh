// The conversations: every "npc" block of the scripts, shown as its greeting, its topics (a word and, if it has one,
// the condition under which the answer counts; the first answer that fits counts, "*" is the answer to every other
// word) and what happens when an item is shown or given. The texts are the ones of tables.yaml (T.x), shown and edited
// as text. A topic is changed in its line of the script, so the rest of the script stays as it was.

namespace Amber.Studio;

using System;
using System.Ui;
using Amber.Base;

enum TalkKind : int32
{
	Greet,
	Topic,
	Show,
	Give,
	Gold
}

struct TalkEntry
{
	TalkKind Kind;
	/// The word of a topic, the item of show_item and give_item.
	string Word;
	string Condition;
	/// The texts it says (keys of texts without "T.").
	List<string> Texts;
	/// The other actions, as written ("learn_word(K.bridge)").
	List<string> Actions;
	/// The lines of the script (0-based) it takes.
	int Line;
	int EndLine;

	string Title()
	{
		string when = Condition.Length > 0 ? "  wenn " + Condition : "";

		switch (Kind)
		{
		case TalkKind.Greet:
			return "Begrüßung";
		case TalkKind.Topic:
			return (Word == "*" ? "Jedes andere Wort" : "Wort \"" + Word + "\"") + when;
		case TalkKind.Show:
			return "Zeigen " + Word + when;
		case TalkKind.Give:
			return "Geben " + Word + when;
		default:
			return "Gold geben" + when;
		}
	}
}

struct TalkNpc
{
	string Name;
	/// The path of the script and the map the block is in.
	string Script;
	string Map;
	int X;
	int Y;
	int Line;
	int EndLine;
	List<TalkEntry> Entries;
}

struct TalkValues
{
	int Npc;
	int Entry;
	string EditKey;
	string NewWord;
	string NewText;
	string NewCondition;
	string Message;
	string Changed;
}

/// A handle.
struct TalkView
{
	TalkValues[] _s;
	List<TalkNpc> Npcs;
	Dictionary<string, TextDoc> Scripts;
	TextDoc Tables;
	/// The texts of tables.yaml: key -> text, and the line of each (0-based).
	Dictionary<string, string> Texts;
	Dictionary<string, int> TextLines;
	/// The texts that are mappings (their text is the field "text"), and their speakers.
	Dictionary<string, bool> TextFields;
	Dictionary<string, string> Speakers;
	/// The last line of the section texts (0-based).
	int LastTextLine;
	Dictionary<string, string> Edit;
	Dictionary<string, string> EditBase;

	static TalkView Create()
	{
		var values = new TalkValues[1];

		values[0].EditKey = "";
		values[0].NewWord = "";
		values[0].NewText = "";
		values[0].NewCondition = "";
		values[0].Message = "";
		values[0].Changed = "";
		values[0].Entry = -1;

		return TalkView
		{
			_s = values, Npcs = List<TalkNpc>.Create(), Scripts = Dictionary<string, TextDoc>.Create(), Texts = Dictionary<string, string>.Create(),
			TextLines = Dictionary<string, int>.Create(), TextFields = Dictionary<string, bool>.Create(), Speakers = Dictionary<string, string>.Create(),
			Edit = Dictionary<string, string>.Create(), EditBase = Dictionary<string, string>.Create()
		};
	}

	int Count()
	{
		return Npcs.Count();
	}

	TalkNpc Get(int index)
	{
		return Npcs.Get(index);
	}

	void Select(int index)
	{
		if (_s[0].Npc != index)
		{
			_s[0].Npc = index;
			_s[0].Entry = -1;
		}
	}

	/// Selects the NPC by name (tests); false if there is none.
	bool SelectName(string name)
	{
		for (var i = 0; i < Npcs.Count(); i += 1)
		{
			if (Npcs.Get(i).Name == name)
			{
				Select(i);

				return true;
			}
		}

		return false;
	}

	int EntryIndex()
	{
		return _s[0].Entry;
	}

	void SelectEntry(int index)
	{
		_s[0].Entry = index;
	}

	string Message()
	{
		return _s[0].Message;
	}

	string TextOf(string key)
	{
		return Texts.GetOrDefault(key, "");
	}

	Optional<TalkNpc> Current()
	{
		if (_s[0].Npc < 0 || _s[0].Npc >= Npcs.Count())
			return null;

		return Npcs.Get(_s[0].Npc);
	}

	// ---- reading ----

	void Load(List<TextDoc> scripts, TextDoc tables)
	{
		string name = Current() is TalkNpc npc ? npc.Name : "";
		int entry = _s[0].Entry;

		Npcs.Clear();
		Scripts.Clear();
		Tables = tables;
		ReadTexts();

		foreach (var script in scripts)
		{
			Scripts.Set(script.Path, script);
			ReadScript(script);
		}

		if (name.Length > 0)
			SelectName(name);

		_s[0].Entry = entry;
	}

	void ReadTexts()
	{
		Texts.Clear();
		TextLines.Clear();
		TextFields.Clear();
		Speakers.Clear();

		if (ParseYaml(Tables.Text()) is not YamlNode root)
			return;

		if (root.Get("texts") is not YamlNode texts)
			return;

		if (!texts.IsMapping())
			return;

		// a text is "key: text" or "key: { speaker: ..., text: ... }" (block or flow)
		for (var i = 0; i < texts.Keys.Count(); i += 1)
		{
			var value = texts.Items.Get(i);
			string key = texts.Keys.Get(i);

			if (value.IsScalar())
				Texts.Set(key, value.Value);
			else if (value.IsMapping())
			{
				TextFields.Set(key, true);

				if (value.Get("text") is YamlNode text && text.IsScalar())
					Texts.Set(key, text.Value);
				else
					Texts.Set(key, "");

				if (value.Get("speaker") is YamlNode speaker && speaker.IsScalar())
					Speakers.Set(key, speaker.Value);
			}
		}

		// the lines: in the section texts, "key:" at the indentation of the entries, then the line with "text:"
		bool inside = false;
		int indent = -1;
		string current = "";

		for (var j = 0; j < Tables.Lines.Count(); j += 1)
		{
			string line = Tables.Lines.Get(j);

			if (BlankYaml(line))
				continue;

			if (IndentOf(line) == 0)
			{
				inside = KeyOfLine(line) == "texts";
				indent = -1;

				continue;
			}

			if (!inside)
				continue;

			if (indent < 0)
				indent = IndentOf(line);

			if (IndentOf(line) == indent)
			{
				current = KeyOfLine(line);

				if (!TextFields.ContainsKey(current) || FindKey(line, "text") >= 0)
				{
					if (!TextLines.ContainsKey(current))
						TextLines.Set(current, j);
				}

				LastTextLine = j;
			}
			else if (current.Length > 0 && TextFields.ContainsKey(current) && !TextLines.ContainsKey(current) && FindKey(line, "text") >= 0)
				TextLines.Set(current, j);

			LastTextLine = j;
		}
	}

	void ReadScript(TextDoc script)
	{
		var lines = script.Lines;
		string map = "";

		for (var i = 0; i < lines.Count(); i += 1)
		{
			string line = StripComment(lines.Get(i)).Trim().ToString();

			if (line.StartsWith("map "))
				map = Word(line, 4);

			if (!line.StartsWith("npc "))
				continue;

			int end = BlockEnd(lines, i);
			var npc = TalkNpc { Name = Word(line, 4), Script = script.Path, Map = map, Line = i, EndLine = end, Entries = List<TalkEntry>.Create() };
			int open = line.IndexOf("(");
			int comma = line.IndexOf(",");
			int close = line.IndexOf(")");

			if (open > 0 && comma > open && close > comma)
			{
				npc.X = TryParseInt(line.Substring(open + 1, comma - open - 1).Trim().ToString()) is int x ? x : 0;
				npc.Y = TryParseInt(line.Substring(comma + 1, close - comma - 1).Trim().ToString()) is int y ? y : 0;
			}

			// the statements directly in the block
			int j = i + 1;

			while (j < end)
			{
				string statement = StripComment(lines.Get(j)).Trim().ToString();
				int last = statement.Contains("{") ? BlockEnd(lines, j) : j;

				if (statement.StartsWith("greet "))
					npc.Entries.Add(Entry(TalkKind.Greet, "", "", statement, j, j));
				else if (statement.StartsWith("topic "))
				{
					int q1 = statement.IndexOf('"');
					int q2 = q1 >= 0 ? statement.IndexOf('"', q1 + 1) : -1;
					string word = q2 > q1 ? statement.Substring(q1 + 1, q2 - q1 - 1) : "";

					npc.Entries.Add(Entry(TalkKind.Topic, word, ConditionOf(statement), Joined(lines, j, last), j, last));
				}
				else if (statement.StartsWith("on show_item(") || statement.StartsWith("on give_item(") || statement.StartsWith("on give_gold"))
				{
					var kind = statement.StartsWith("on show_item(") ? TalkKind.Show : statement.StartsWith("on give_item(") ? TalkKind.Give : TalkKind.Gold;
					int a = statement.IndexOf("(");
					int b = statement.IndexOf(")");
					string item = a >= 0 && b > a ? statement.Substring(a + 1, b - a - 1) : "";

					npc.Entries.Add(Entry(kind, item, ConditionOf(statement), Joined(lines, j, last), j, last));
				}

				j = last + 1;
			}

			Npcs.Add(npc);
			i = end;
		}
	}

	static TalkEntry Entry(TalkKind kind, string word, string condition, string text, int line, int end)
	{
		var entry = TalkEntry { Kind = kind, Word = word, Condition = condition, Texts = List<string>.Create(), Actions = List<string>.Create(), Line = line, EndLine = end };

		if (kind == TalkKind.Greet)
		{
			int at = text.IndexOf("T.");

			if (at >= 0)
				entry.Texts.Add(SymbolAt(text, at + 2));

			return entry;
		}

		// the actions inside "do { ... }"
		int open = text.IndexOf("do {");
		int close = text.LastIndexOf('}');

		if (open < 0 || close < open)
			return entry;

		string body = text.Substring(open + 4, close - open - 4);

		foreach (var part in SplitToList(body, ";"))
		{
			string action = part.Trim().ToString();

			if (action.Length == 0)
				continue;

			if (action.StartsWith("say(T."))
				entry.Texts.Add(SymbolAt(action, 6));
			else
				entry.Actions.Add(action);
		}

		return entry;
	}

	// ---- changing ----

	/// A text of tables.yaml gets the new content.
	bool SetText(string key, string text)
	{
		if (!TextLines.ContainsKey(key))
		{
			_s[0].Message = "Den Text T." + key + " gibt es nicht";

			return false;
		}

		int line = TextLines.GetOrDefault(key, 0);

		Tables.SetLine(line, ReplaceYamlValue(Tables.Lines.Get(line), TextFields.ContainsKey(key) ? "text" : key, text));
		_s[0].Changed = Tables.Path;

		return true;
	}

	/// The word and the condition of a topic (its first line).
	bool SetTopic(TalkNpc npc, TalkEntry entry, string word, string condition)
	{
		if (entry.Kind != TalkKind.Topic)
			return false;

		if (Scripts.TryGet(npc.Script) is not TextDoc script)
			return false;

		string line = script.Lines.Get(entry.Line);
		int q1 = line.IndexOf('"');
		int q2 = q1 >= 0 ? line.IndexOf('"', q1 + 1) : -1;
		int doAt = line.IndexOf(" do ");

		if (q1 < 0 || q2 < q1 || doAt < q2)
			return false;

		string head = line.Substring(0, q1 + 1) + word.Replace("\"", "") + "\"";
		string tail = line.Substring(doAt);
		string when = condition.Trim().ToString().Length > 0 ? " when " + condition.Trim().ToString() : "";

		script.SetLine(entry.Line, head + when + tail);
		_s[0].Changed = script.Path;

		return true;
	}

	/// A new topic after the last one of the NPC (before its item answers), with a new text in tables.yaml.
	bool AddTopic(TalkNpc npc, string word, string condition, string text)
	{
		if (word.Length == 0)
			return false;

		if (Scripts.TryGet(npc.Script) is not TextDoc script)
			return false;

		// the key of the text: <npc>_<word>, made unique
		string key = SymbolName(npc.Name + "_" + word);
		string unique = key;
		int number = 2;

		while (Texts.ContainsKey(unique))
		{
			unique = key + "_" + number;
			number += 1;
		}

		int after = npc.Line;
		int indent = IndentOf(script.Lines.Get(npc.Line)) + 2;
		int lastTopic = -1;

		foreach (var entry in npc.Entries)
		{
			if (entry.Kind == TalkKind.Topic || entry.Kind == TalkKind.Greet)
			{
				// a new word goes before the answer to every other word
				if (entry.Kind == TalkKind.Topic && entry.Word == "*")
					break;

				after = entry.EndLine;
				lastTopic = entry.Line;
			}
		}

		if (lastTopic >= 0)
			indent = IndentOf(script.Lines.Get(lastTopic));

		string when = condition.Length > 0 ? " when " + condition : "";
		var line = List<string>.Create();

		line.Add(Spaces(indent) + "topic \"" + word.Replace("\"", "") + "\"" + when + " do { say(T." + unique + "); }");
		script.InsertLines(after + 1, line);

		// the text: at the end of the section texts, with the speaker of the greeting
		if (LastTextLine <= 0)
		{
			_s[0].Message = "tables.yaml hat keine Texte";

			return true;
		}

		string speaker = "";

		foreach (var entry in npc.Entries)
		{
			if (entry.Kind == TalkKind.Greet && entry.Texts.Count() > 0)
				speaker = Speakers.GetOrDefault(entry.Texts.Get(0), "");
		}

		var textLines = List<string>.Create();

		textLines.Add(Spaces(2) + unique + ":");

		if (speaker.Length > 0)
			textLines.Add(Spaces(4) + "speaker: " + YamlValue(speaker, false));

		textLines.Add(Spaces(4) + "text: " + YamlValue(text, true));
		Tables.InsertLines(LastTextLine + 1, textLines);
		// keywords come before texts in tables.yaml: added last, so the line of the text above was still right
		EnsureKeyword(word);
		_s[0].Message = "Thema \"" + word + "\" mit T." + unique + " angelegt";
		_s[0].Changed = script.Path;

		return true;
	}

	/// A word of a topic is a keyword (K.<word>): a new one is added to keywords in tables.yaml.
	void EnsureKeyword(string word)
	{
		if (word == "*")
			return;

		string key = word.ToLower();
		bool inside = false;
		int last = -1;

		for (var j = 0; j < Tables.Lines.Count(); j += 1)
		{
			string line = Tables.Lines.Get(j);

			if (BlankYaml(line))
				continue;

			if (IndentOf(line) == 0)
			{
				if (inside)
					break;

				inside = KeyOfLine(line) == "keywords";
				last = inside ? j : last;

				continue;
			}

			if (inside)
			{
				if (KeyOfLine(line) == key)
					return;

				last = j;
			}
		}

		if (last < 0)
			return;

		var added = List<string>.Create();

		added.Add("  " + key + ": " + YamlValue(word, false));
		Tables.InsertLines(last + 1, added);
	}

	/// Removes the topic if it has its lines to itself.
	bool RemoveEntry(TalkNpc npc, TalkEntry entry)
	{
		if (entry.Kind != TalkKind.Topic)
			return false;

		if (Scripts.TryGet(npc.Script) is not TextDoc script)
			return false;

		if (!StripComment(script.Lines.Get(entry.Line)).Trim().ToString().StartsWith("topic ") || !StripComment(script.Lines.Get(entry.EndLine)).Trim().ToString().EndsWith("}"))
		{
			_s[0].Message = "Das Thema teilt seine Zeilen: im Skript ändern";

			return false;
		}

		script.RemoveLines(entry.Line, entry.EndLine - entry.Line + 1);
		_s[0].Message = "Thema \"" + entry.Word + "\" entfernt";
		_s[0].Entry = -1;
		_s[0].Changed = script.Path;

		return true;
	}

	// ---- drawing ----

	/// The conversation of the NPC that is chosen. Returns the path of a document it changed ("" none).
	string Draw(Ui ui, int height)
	{
		_s[0].Changed = "";

		if (Current() is not TalkNpc npc)
		{
			ui.Area("nonpc", 0, height);
			ui.Note(Npcs.Count() == 0 ? "Die Skripte haben keine Figuren mit Gespräch (npc)." : "Links eine Figur wählen.");

			return "";
		}

		ui.Label(npc.Name + " - " + System.Path.GetFileName(npc.Script) + ", Karte " + npc.Map + " bei " + npc.X + ", " + npc.Y);
		ui.Note("Die erste passende Antwort zählt; ein Klick wählt sie zum Bearbeiten.");

		using (ui.Scroll("talk", Math.Max(60, height - 50)))
		{
			for (var i = 0; i < npc.Entries.Count(); i += 1)
			{
				var entry = npc.Entries.Get(i);

				using (ui.Id(i))
				{
					if (ui.ListItem(entry.Title() + "##entry", _s[0].Entry == i))
						_s[0].Entry = i;

					using (ui.Indent())
					{
						foreach (var key in entry.Texts)
							ui.Text(Texts.ContainsKey(key) ? "\"" + TextOf(key) + "\"" : "(T." + key + " fehlt in tables.yaml)");

						foreach (var action in entry.Actions)
							ui.Note(action);
					}
				}
			}
		}

		return _s[0].Changed;
	}

	/// What the text box of the value shows: what was typed, or the value of the file if that changed meanwhile.
	string Edited(string name, string current)
	{
		if (EditBase.GetOrDefault(name, current) != current)
			Edit.Set(name, current);

		EditBase.Set(name, current);

		return Edit.GetOrDefault(name, current);
	}

	/// The answer that is chosen: its word, its condition and its texts; a new topic. Returns the path of a changed
	/// document ("" none).
	string DrawProperties(Ui ui)
	{
		_s[0].Changed = "";

		if (Current() is not TalkNpc npc)
			return "";

		ui.Label("Gespräch: " + npc.Name);

		if (_s[0].Message.Length > 0)
			ui.Note(_s[0].Message);

		if (_s[0].Entry >= 0 && _s[0].Entry < npc.Entries.Count())
		{
			var entry = npc.Entries.Get(_s[0].Entry);
			string editKey = npc.Script + ":" + entry.Line + ":" + entry.Word + ":" + entry.Condition;

			if (_s[0].EditKey != editKey)
			{
				_s[0].EditKey = editKey;
				Edit.Clear();
				EditBase.Clear();
			}

			ui.Separator();
			ui.Label(entry.Title());

			if (entry.Kind == TalkKind.Topic)
			{
				string word = Edited("#word", entry.Word);
				string when = Edited("#when", entry.Condition);

				ui.Note("Wort");
				ui.TextBox("word", ref word);
				ui.Note("Bedingung (leer: immer)");
				ui.TextBox("when", ref when);
				Edit.Set("#word", word);
				Edit.Set("#when", when);

				bool done = ui.Submitted("word") || ui.Submitted("when") || !ui.HasFocus("word") && !ui.HasFocus("when");

				if (done && (word != entry.Word || when != entry.Condition) && word.Length > 0 && SetTopic(npc, entry, word, when))
				{
					EditBase.Set("#word", word);
					EditBase.Set("#when", when);
				}
			}

			foreach (var key in entry.Texts)
			{
				string text = Edited(key, TextOf(key));
				string id = "text:" + key;

				ui.Note("Text T." + key);
				ui.TextBox(id, ref text);
				Edit.Set(key, text);

				if (text != TextOf(key) && (ui.Submitted(id) || !ui.HasFocus(id)) && SetText(key, text))
					EditBase.Set(key, text);
			}

			if (entry.Kind == TalkKind.Topic && ui.Button("Thema entfernen"))
				RemoveEntry(npc, entry);
		}

		ui.Separator();
		ui.Label("Neues Thema");
		ui.Note("Wort");
		ui.TextBox("newword", ref _s[0].NewWord);
		ui.Note("Bedingung (leer: immer)");
		ui.TextBox("newwhen", ref _s[0].NewCondition);
		ui.Note("Antwort");
		ui.TextBox("newtext", ref _s[0].NewText);

		if (ui.Button("Thema anlegen") && _s[0].NewWord.Length > 0)
		{
			if (AddTopic(npc, _s[0].NewWord, _s[0].NewCondition, _s[0].NewText))
			{
				_s[0].NewWord = "";
				_s[0].NewText = "";
				_s[0].NewCondition = "";
			}
		}

		return _s[0].Changed;
	}
}

/// The line without a // comment (not inside a string).
string StripComment(string line)
{
	bool quoted = false;

	for (var i = 0; i + 1 < line.Length; i += 1)
	{
		if (line[i] == '"')
			quoted = !quoted;
		else if (!quoted && line[i] == '/' && line[i + 1] == '/')
			return line.Substring(0, i);
	}

	return line;
}

/// The name that starts at the position (letters, digits, "_").
string Word(string text, int start)
{
	int end = start;

	while (end < text.Length && (text[end] >= 'a' && text[end] <= 'z' || text[end] >= 'A' && text[end] <= 'Z' || text[end] >= '0' && text[end] <= '9' || text[end] == '_'))
		end += 1;

	return text.Substring(start, end - start);
}

string SymbolAt(string text, int start)
{
	return Word(text, start);
}

/// The condition between "when" and "do" of a statement, "" without one.
string ConditionOf(string statement)
{
	int when = statement.IndexOf(" when ");
	int doAt = statement.IndexOf(" do ");

	if (doAt < 0 && statement.EndsWith(" do"))
		doAt = statement.Length - 3;

	if (when < 0 || doAt < when)
		return "";

	return statement.Substring(when + 6, doAt - when - 6).Trim().ToString();
}

/// The last line of the block that opens in the line (the line of its closing brace), counting braces outside of
/// strings and comments; the line itself if no block opens there.
int BlockEnd(List<string> lines, int start)
{
	int depth = 0;
	bool opened = false;

	for (var i = start; i < lines.Count(); i += 1)
	{
		string line = StripComment(lines.Get(i));
		bool quoted = false;

		for (var c = 0; c < line.Length; c += 1)
		{
			char ch = line[c];

			if (ch == '"')
				quoted = !quoted;
			else if (!quoted && ch == '{')
			{
				depth += 1;
				opened = true;
			}
			else if (!quoted && ch == '}')
			{
				depth -= 1;

				if (opened && depth == 0)
					return i;
			}
		}

		if (!opened)
			return start;
	}

	return lines.Count() - 1;
}

/// The lines from `start` to `end` as one text (without comments).
string Joined(List<string> lines, int start, int end)
{
	var parts = List<string>.Create();

	for (var i = start; i <= end && i < lines.Count(); i += 1)
		parts.Add(StripComment(lines.Get(i)).Trim().ToString());

	return JoinList(" ", parts);
}
