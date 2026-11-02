// The database: the sections of tables.yaml (texts, items, spells, monsters, groups, companions, chests, deltas,
// keywords, maps ...) as tables with a row per entry and a column per field, with a search over keys and values. The
// entry that is chosen is edited in the panel on the right: a field changes its line of tables.yaml (the comments and
// the layout of the rest stay), new fields and entries are added as lines, an entry can be copied and removed. The check
// of the content (F7, and after saving) tells what the game thinks of it; "Wo benutzt?" finds the symbol in the scripts.

namespace Amber.Studio;

using System;
using System.Ui;
using Amber.Base;

struct TableField
{
	string Name;
	string Value;
	bool Quoted;
	/// The field is a list or a mapping (shown as text, not edited here).
	bool Nested;
	/// The line of the value (0-based).
	int Line;
}

struct TableRecord
{
	string Key;
	/// The line of the key and the last line of the entry (0-based).
	int Line;
	int EndLine;
	/// An entry that is one value (texts: key: "text").
	bool Scalar;
	string Value;
	bool Quoted;
	/// An entry in one line: key: { a: 1, b: 2 }.
	bool Flow;
	List<TableField> Fields;

	Optional<TableField> Field(string name)
	{
		foreach (var field in Fields)
		{
			if (field.Name == name)
				return field;
		}

		return null;
	}
}

struct TableSection
{
	string Name;
	int Line;
	int EndLine;
	/// The section is a list (screens, natives): its items are shown, not edited.
	bool List;
	List<TableRecord> Records;
	/// The fields of the entries in the order they first appear.
	List<string> Columns;
}

struct TableValues
{
	int Section;
	int Record;
	string Filter;
	string Problem;
	string NewKey;
	string NewField;
	string NewValue;
	/// The editing of the fields of the entry that is chosen (Edit holds what the text boxes show).
	string EditKey;
	/// The symbol whose uses the panel asked for ("I.herb"), "" none.
	string Usage;
	string Message;
}

/// A handle.
struct TableView
{
	TableValues[] _s;
	TextDoc Doc;
	List<TableSection> Sections;
	Dictionary<string, string> Edit;
	/// The value of the file each text box started from.
	Dictionary<string, string> EditBase;

	static TableView Create()
	{
		var values = new TableValues[1];

		values[0].Filter = "";
		values[0].Problem = "";
		values[0].NewKey = "";
		values[0].NewField = "";
		values[0].NewValue = "";
		values[0].EditKey = "";
		values[0].Usage = "";
		values[0].Message = "";
		values[0].Record = -1;

		return TableView { _s = values, Sections = List<TableSection>.Create(), Edit = Dictionary<string, string>.Create(), EditBase = Dictionary<string, string>.Create() };
	}

	/// Reads the sections from the document again (after every change); the section and the entry that are chosen stay
	/// chosen by their names.
	void Load(TextDoc doc)
	{
		string section = _s[0].Section < Sections.Count() ? Sections.Get(_s[0].Section).Name : "";
		string record = SelectedKey();

		Doc = doc;
		Sections.Clear();

		var parsed = ParseYaml(doc.Text());

		if (parsed is not YamlNode root)
		{
			_s[0].Problem = "tables.yaml " + parsed.Message;

			return;
		}

		_s[0].Problem = "";
		ReadSections(root);

		if (section.Length > 0)
			SelectSection(section);

		if (record.Length > 0)
			SelectRecord(record);
	}

	List<string> SectionNames()
	{
		var names = List<string>.Create();

		foreach (var section in Sections)
			names.Add(section.Name);

		return names;
	}

	void SelectSection(string name)
	{
		for (var i = 0; i < Sections.Count(); i += 1)
		{
			if (Sections.Get(i).Name == name && _s[0].Section != i)
			{
				_s[0].Section = i;
				_s[0].Record = -1;
				_s[0].EditKey = "";
			}
		}
	}

	bool SelectRecord(string key)
	{
		if (_s[0].Section >= Sections.Count())
			return false;

		var records = Sections.Get(_s[0].Section).Records;

		for (var i = 0; i < records.Count(); i += 1)
		{
			if (records.Get(i).Key == key)
			{
				_s[0].Record = i;

				return true;
			}
		}

		return false;
	}

	string SelectedKey()
	{
		if (Selected() is TableRecord record)
			return record.Key;

		return "";
	}

	Optional<TableRecord> Selected()
	{
		if (_s[0].Section >= Sections.Count())
			return null;

		var records = Sections.Get(_s[0].Section).Records;

		if (_s[0].Record < 0 || _s[0].Record >= records.Count())
			return null;

		return records.Get(_s[0].Record);
	}

	string SectionName()
	{
		return _s[0].Section < Sections.Count() ? Sections.Get(_s[0].Section).Name : "";
	}

	/// The symbol the panel asked to look for ("" none); asking takes it.
	string TakeUsage()
	{
		string usage = _s[0].Usage;

		_s[0].Usage = "";

		return usage;
	}

	string Message()
	{
		return _s[0].Message;
	}

	// ---- reading ----

	void ReadSections(YamlNode root)
	{
		var lines = Doc.Lines;

		for (var i = 0; i < root.Keys.Count(); i += 1)
		{
			string name = root.Keys.Get(i);
			var node = root.Items.Get(i);
			int start = SectionLine(name);

			if (start < 0)
				continue;

			int end = start;

			for (var j = start + 1; j < lines.Count(); j += 1)
			{
				string line = lines.Get(j);

				if (!BlankYaml(line) && IndentOf(line) == 0)
					break;

				if (!BlankYaml(line))
					end = j;
			}

			var section = TableSection
			{
				Name = name, Line = start, EndLine = end, List = node.IsSequence(), Records = List<TableRecord>.Create(), Columns = List<string>.Create()
			};

			if (node.IsMapping())
				ReadRecords(ref section, node);
			else if (node.IsSequence())
			{
				for (var k = 0; k < node.Items.Count(); k += 1)
				{
					var item = node.Items.Get(k);

					section.Records.Add(TableRecord
					{
						Key = item.IsScalar() ? item.Value : "#" + (k + 1), Line = item.Line - 1, EndLine = item.Line - 1, Scalar = true, Value = item.IsScalar() ? item.Value : "...",
						Fields = List<TableField>.Create()
					});
				}
			}
			else
			{
				// a section that is one value (icon_sheet: "..."): one entry
				section.Records.Add(TableRecord
				{
					Key = name, Line = start, EndLine = start, Scalar = true, Value = node.IsScalar() ? node.Value : "", Quoted = node.IsScalar() && !node.Plain,
					Fields = List<TableField>.Create()
				});
			}

			Sections.Add(section);
		}
	}

	/// The line of "name:" at the start of a line (0-based), -1 if there is none.
	int SectionLine(string name)
	{
		for (var i = 0; i < Doc.Lines.Count(); i += 1)
		{
			string line = Doc.Lines.Get(i);

			if (IndentOf(line) == 0 && KeyOfLine(line) == name)
				return i;
		}

		return -1;
	}

	void ReadRecords(ref TableSection section, YamlNode node)
	{
		var lines = Doc.Lines;
		int indent = -1;

		// the indentation of the entries: the first line with content after the header
		for (var j = section.Line + 1; j <= section.EndLine; j += 1)
		{
			if (!BlankYaml(lines.Get(j)))
			{
				indent = IndentOf(lines.Get(j));

				break;
			}
		}

		var starts = List<int>.Create();

		for (var j = section.Line + 1; j <= section.EndLine; j += 1)
		{
			string line = lines.Get(j);

			if (!BlankYaml(line) && IndentOf(line) == indent && KeyOfLine(line).Length > 0)
				starts.Add(j);
		}

		// a header with a flow value (palettes: {}) has its entries in the same line
		if (indent < 0 && node.Keys.Count() > 0)
			starts.Add(section.Line);

		for (var k = 0; k < node.Keys.Count(); k += 1)
		{
			string key = node.Keys.Get(k);
			var value = node.Items.Get(k);
			int line = section.Line;

			foreach (var start in starts)
			{
				if (KeyOfLine(lines.Get(start)) == key)
				{
					line = start;

					break;
				}
			}

			int end = line;
			int index = starts.IndexOf(line);
			int next = index >= 0 && index + 1 < starts.Count() ? starts.Get(index + 1) : section.EndLine + 1;

			for (var j = line + 1; j < next; j += 1)
			{
				if (!BlankYaml(lines.Get(j)))
					end = j;
			}

			var record = TableRecord { Key = key, Line = line, EndLine = end, Fields = List<TableField>.Create() };

			if (value.IsMapping())
			{
				record.Flow = lines.Get(line).Contains("{");

				for (var f = 0; f < value.Keys.Count(); f += 1)
				{
					var item = value.Items.Get(f);
					string name = value.Keys.Get(f);

					record.Fields.Add(TableField
					{
						Name = name, Value = item.IsScalar() ? item.Value : item.IsNull() ? "" : Describe(item), Quoted = item.IsScalar() && !item.Plain,
						Nested = item.IsMapping() || item.IsSequence(), Line = item.IsNull() || item.IsScalar() ? FieldLine(line, end, name, item.Line - 1) : item.Line - 1
					});

					if (!section.Columns.Contains(name))
						section.Columns.Add(name);
				}
			}
			else
			{
				record.Scalar = true;
				record.Value = value.IsScalar() ? value.Value : value.IsNull() ? "" : Describe(value);
				record.Quoted = value.IsScalar() && !value.Plain;
			}

			section.Records.Add(record);
		}
	}

	/// The line of a field: the one the reader gave if the key is in it, else the line of the entry that has it.
	int FieldLine(int start, int end, string name, int given)
	{
		if (given >= start && given <= end && FindKey(Doc.Lines.Get(given), name) >= 0)
			return given;

		for (var j = start; j <= end; j += 1)
		{
			if (FindKey(Doc.Lines.Get(j), name) >= 0)
				return j;
		}

		return given;
	}

	/// A list or a mapping as one short text: [a, b] or {a: 1, b: 2}.
	static string Describe(YamlNode node)
	{
		var parts = List<string>.Create();

		for (var i = 0; i < node.Items.Count(); i += 1)
		{
			var item = node.Items.Get(i);
			string value = item.IsScalar() ? item.Value : item.IsNull() ? "" : Describe(item);

			parts.Add(node.IsMapping() ? node.Keys.Get(i) + ": " + value : value);
		}

		return node.IsMapping() ? "{" + JoinList(", ", parts) + "}" : "[" + JoinList(", ", parts) + "]";
	}

	// ---- changing ----

	/// The field of the entry gets the value; a field the entry does not have yet is added. Returns what was done.
	bool SetField(string key, string field, string value)
	{
		if (!SelectRecord(key))
			return false;

		if (Selected() is not TableRecord record)
			return false;

		if (record.Scalar)
		{
			string line = Doc.Lines.Get(record.Line);

			Doc.SetLine(record.Line, ReplaceYamlValue(line, record.Key, value));

			return true;
		}

		if (record.Field(field) is TableField existing)
		{
			if (existing.Nested)
			{
				_s[0].Message = field + " ist eine Liste: in tables.yaml ändern";

				return false;
			}

			Doc.SetLine(existing.Line, ReplaceYamlValue(Doc.Lines.Get(existing.Line), field, value));

			return true;
		}

		if (record.Flow)
		{
			string line = Doc.Lines.Get(record.Line);
			int close = line.LastIndexOf('}');

			if (close < 0)
				return false;

			string inner = line.Substring(0, close).TrimEnd().ToString();
			string separator = inner.EndsWith("{") ? " " : ", ";

			Doc.SetLine(record.Line, inner + separator + field + ": " + YamlValue(value, false) + " " + line.Substring(close));

			return true;
		}

		// a block entry: a new line after its last one, indented like its fields
		int indent = IndentOf(Doc.Lines.Get(record.Line)) + 2;

		if (record.Fields.Count() > 0)
			indent = IndentOf(Doc.Lines.Get(record.Fields.Get(0).Line));

		var added = List<string>.Create();

		added.Add(Spaces(indent) + field + ": " + YamlValue(value, false));
		Doc.InsertLines(record.EndLine + 1, added);

		return true;
	}

	/// A new entry: a copy of the entry that is chosen with the new key, or (texts and the like) a new empty value.
	bool AddRecord(string key)
	{
		if (_s[0].Section >= Sections.Count() || key.Length == 0)
			return false;

		var section = Sections.Get(_s[0].Section);

		if (section.List)
		{
			_s[0].Message = section.Name + " ist eine Liste: in tables.yaml ändern";

			return false;
		}

		foreach (var existing in section.Records)
		{
			if (existing.Key == key)
			{
				_s[0].Message = "Den Schlüssel " + key + " gibt es schon";

				return false;
			}
		}

		var lines = List<string>.Create();
		int at = section.EndLine + 1;

		if (Selected() is TableRecord source && !source.Scalar)
		{
			for (var j = source.Line; j <= source.EndLine; j += 1)
			{
				string line = Doc.Lines.Get(j);

				if (j == source.Line)
				{
					int colon = line.IndexOf(':');

					line = Spaces(IndentOf(line)) + key + line.Substring(colon);
				}

				lines.Add(line);
			}

			at = source.EndLine + 1;
		}
		else
		{
			int indent = section.Records.Count() > 0 ? IndentOf(Doc.Lines.Get(section.Records.Get(0).Line)) : 2;

			lines.Add(Spaces(indent) + key + ": \"\"");
		}

		Doc.InsertLines(at, lines);
		_s[0].Message = key + " angelegt";

		return true;
	}

	bool RemoveRecord()
	{
		if (Selected() is not TableRecord record)
			return false;

		if (record.Line == SectionLineOf())
			return false;

		Doc.RemoveLines(record.Line, record.EndLine - record.Line + 1);
		_s[0].Message = record.Key + " entfernt";
		_s[0].Record = -1;

		return true;
	}

	int SectionLineOf()
	{
		return _s[0].Section < Sections.Count() ? Sections.Get(_s[0].Section).Line : -1;
	}

	// ---- drawing ----

	bool Matches(TableRecord record, string filter)
	{
		if (filter.Length == 0)
			return true;

		string lower = filter.ToLower();

		if (record.Key.ToLower().Contains(lower) || record.Value != null && record.Value.ToLower().Contains(lower))
			return true;

		foreach (var field in record.Fields)
		{
			if (field.Value.ToLower().Contains(lower))
				return true;
		}

		return false;
	}

	/// The table of the section. True if the document was changed.
	bool Draw(Ui ui, int height)
	{
		if (_s[0].Problem.Length > 0)
			ui.Note(_s[0].Problem);

		if (Sections.Count() == 0)
		{
			ui.Area("nodata", 0, height);

			return false;
		}

		_s[0].Section = Clamp(_s[0].Section, 0, Sections.Count() - 1);

		var section = Sections.Get(_s[0].Section);
		int columns = section.Columns.Count() > 0 ? Math.Min(section.Columns.Count(), 6) : 1;

		using (ui.Row())
		{
			ui.Label(section.Name + " (" + section.Records.Count() + ")");
			ui.TextBox("filter", ref _s[0].Filter);
			ui.Tooltip("Suche in Schlüsseln und Werten");
		}

		int keyWidth = 150;

		using (ui.Row())
		{
			using (ui.Column(keyWidth))
				ui.Note("Schlüssel");

			if (section.Columns.Count() == 0)
				ui.Note("Wert");

			for (var c = 0; c < columns; c += 1)
			{
				using (ui.Column(110))
					ui.Note(section.Columns.Get(c));
			}
		}

		using (ui.Scroll("records", Math.Max(60, height - 60)))
		{
			for (var i = 0; i < section.Records.Count(); i += 1)
			{
				var record = section.Records.Get(i);

				if (!Matches(record, _s[0].Filter))
					continue;

				using (ui.Id(i))
				{
					using (ui.Row())
					{
						using (ui.Column(keyWidth))
						{
							if (ui.ListItem(Cut(record.Key, 20) + "##key", _s[0].Record == i))
								_s[0].Record = i;
						}

						if (record.Scalar)
							ui.Label(Cut(record.Value, 90));
						else
						{
							for (var c = 0; c < columns; c += 1)
							{
								using (ui.Column(110))
								{
									if (record.Field(section.Columns.Get(c)) is TableField field)
										ui.Label(Cut(field.Value, 12));
									else
										ui.Note("-");
								}
							}
						}
					}
				}
			}
		}

		return false;
	}

	/// The entry that is chosen, with its fields to edit. True if the document was changed.
	bool DrawProperties(Ui ui)
	{
		bool changed = false;

		if (Sections.Count() == 0)
			return false;

		var section = Sections.Get(Clamp(_s[0].Section, 0, Sections.Count() - 1));

		ui.Label("Datenbank: " + section.Name);

		if (_s[0].Message.Length > 0)
			ui.Note(_s[0].Message);

		if (Selected() is TableRecord record)
		{
			if (_s[0].EditKey != section.Name + "." + record.Key)
			{
				// another entry: the text boxes show its values
				_s[0].EditKey = section.Name + "." + record.Key;
				Edit.Clear();
				EditBase.Clear();
			}

			ui.Separator();
			ui.Label(record.Key);

			if (record.Scalar)
			{
				if (!section.List && EditField(ui, "", "Wert", record.Value != null ? record.Value : "", record.Key))
					changed = true;
			}
			else
			{
				foreach (var field in record.Fields)
				{
					if (field.Nested)
					{
						ui.Note(field.Name + ": " + field.Value);

						continue;
					}

					if (EditField(ui, field.Name, field.Name, field.Value, record.Key))
						changed = true;
				}

				ui.Separator();
				ui.Note("Neues Feld");

				using (ui.Row())
				{
					ui.TextBox("newfield", ref _s[0].NewField);
					ui.TextBox("newvalue", ref _s[0].NewValue);
				}

				if (ui.Button("Feld hinzufügen") && _s[0].NewField.Length > 0)
				{
					if (SetField(record.Key, SymbolName(_s[0].NewField), _s[0].NewValue))
					{
						changed = true;
						_s[0].NewField = "";
						_s[0].NewValue = "";
					}
				}
			}

			ui.Separator();

			string prefix = PrefixOfSection(section.Name);

			if (prefix.Length > 0 && ui.Button("Wo benutzt?"))
				_s[0].Usage = prefix + "." + record.Key;

			if (!section.List && ui.Button("Eintrag entfernen"))
				changed = RemoveRecord() || changed;
		}
		else
			ui.Note("Links in der Tabelle einen Eintrag wählen.");

		if (!section.List)
		{
			ui.Separator();
			ui.Note(Selected() is TableRecord ? "Neuer Eintrag (Kopie des gewählten)" : "Neuer Eintrag");
			ui.TextBox("newkey", ref _s[0].NewKey);

			if (ui.Button("Anlegen") && _s[0].NewKey.Length > 0)
			{
				string key = SymbolName(_s[0].NewKey);

				if (AddRecord(key))
				{
					changed = true;
					_s[0].NewKey = "";
					Load(Doc);
					SelectRecord(key);
				}
			}
		}

		return changed;
	}

	/// A text box for a field: the change goes into the file with Enter or when the box loses the focus. A value that
	/// changed in the file meanwhile (undo) replaces what the box shows.
	bool EditField(Ui ui, string field, string label, string current, string key)
	{
		string id = "field:" + field;

		if (EditBase.GetOrDefault(field, current) != current)
			Edit.Set(field, current);

		EditBase.Set(field, current);

		string value = Edit.GetOrDefault(field, current);

		ui.Note(label);
		ui.TextBox(id, ref value);
		Edit.Set(field, value);

		if (value != current && (ui.Submitted(id) || !ui.HasFocus(id)))
		{
			bool done = SetField(key, field, value);

			if (done)
				EditBase.Set(field, value);

			if (done && field.Length > 0 && IsNumber(current) && !IsNumber(value))
				_s[0].Message = "Achtung: " + field + " war eine Zahl";

			return done;
		}

		return false;
	}
}

bool IsNumber(string text)
{
	return TryParseInt(text) is int;
}

string Spaces(int count)
{
	return String.Repeat(" ", Math.Max(0, count));
}

/// At most `length` characters (bytes) of the text, "..." if it was longer.
string Cut(string text, int length)
{
	if (text == null)
		return "";

	if (text.Length <= length)
		return text;

	int cut = length;

	// not in the middle of a UTF-8 character
	while (cut > 0 && ((int)text[cut] & 0xC0) == 0x80)
		cut -= 1;

	return text.Substring(0, cut) + "...";
}

/// The prefix of the symbols of a section in the scripts (items: I.herb), "" if the scripts do not name them.
string PrefixOfSection(string section)
{
	switch (section)
	{
	case "texts":
		return "T";
	case "keywords":
		return "K";
	case "items":
		return "I";
	case "groups":
		return "G";
	case "maps":
		return "M";
	case "companions":
		return "C";
	case "screens":
		return "S";
	case "spells":
		return "SP";
	case "tiles":
		return "TILE";
	case "deltas":
		return "DELTA";
	case "chests":
		return "CH";
	case "natives":
		return "N";
	case "palettes":
		return "PAL";
	default:
		return "";
	}
}
