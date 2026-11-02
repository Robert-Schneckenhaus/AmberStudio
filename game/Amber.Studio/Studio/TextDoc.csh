// A text file the studio changes (tables.yaml, the scripts): its lines, whether it was changed and an undo history of
// whole texts (the files are small). The data and the conversation editors change single lines, so comments and the
// layout of everything else stay as they were.

namespace Amber.Studio;

using System;
using Amber.Base;

struct TextDocValues
{
	bool Dirty;
	/// Counts the changes (views that show the text redraw when it differs).
	int Version;
}

/// A handle: copies share the lines and the history.
struct TextDoc
{
	TextDocValues[] _s;
	string Path;
	List<string> Lines;
	List<string> _undo;
	List<string> _redo;

	static Error<TextDoc> Load(string path)
	{
		var read = File.ReadAllText(path);

		if (read is not string text)
			return error("Kann " + path + " nicht lesen.", (int)ErrorKind.Io);

		var doc = TextDoc { _s = new TextDocValues[1], Path = path, Lines = List<string>.Create(), _undo = List<string>.Create(), _redo = List<string>.Create() };

		doc.SetLines(text);

		return doc;
	}

	bool IsLoaded()
	{
		return _s.Length > 0;
	}

	bool Dirty()
	{
		return _s[0].Dirty;
	}

	int Version()
	{
		return _s[0].Version;
	}

	string Name()
	{
		return System.Path.GetFileName(Path);
	}

	string Text()
	{
		var parts = new string[Lines.Count()];

		for (var i = 0; i < parts.Length; i += 1)
			parts[i] = Lines.Get(i);

		return String.Join("\n", parts);
	}

	void SetLines(string text)
	{
		Lines.Clear();

		foreach (var line in text.Split('\n'))
		{
			string value = line.ToString();

			if (value.EndsWith("\r"))
				value = value.Substring(0, value.Length - 1);

			Lines.Add(value);
		}
	}

	/// Before a change: the text as it is goes into the undo history.
	void Remember()
	{
		_undo.Add(Text());
		_redo.Clear();

		if (_undo.Count() > 200)
			_undo.RemoveAt(0);
	}

	void Changed()
	{
		_s[0].Dirty = true;
		_s[0].Version += 1;
	}

	/// The line (0-based) gets a new text (one step of the history).
	void SetLine(int index, string text)
	{
		if (index < 0 || index >= Lines.Count() || Lines.Get(index) == text)
			return;

		Remember();
		Lines.Set(index, text);
		Changed();
	}

	/// New lines before the line `index` (the end: Lines.Count()).
	void InsertLines(int index, List<string> lines)
	{
		if (lines.Count() == 0)
			return;

		Remember();

		for (var i = 0; i < lines.Count(); i += 1)
			Lines.Insert(Math.Min(Math.Max(0, index), Lines.Count()) + i, lines.Get(i));

		Changed();
	}

	/// Removes `count` lines from `index` on.
	void RemoveLines(int index, int count)
	{
		if (index < 0 || count <= 0 || index >= Lines.Count())
			return;

		Remember();

		for (var i = 0; i < count && index < Lines.Count(); i += 1)
			Lines.RemoveAt(index);

		Changed();
	}

	bool CanUndo()
	{
		return _undo.Count() > 0;
	}

	bool CanRedo()
	{
		return _redo.Count() > 0;
	}

	bool Undo()
	{
		if (_undo.Count() == 0)
			return false;

		_redo.Add(Text());
		SetLines(_undo.Get(_undo.Count() - 1));
		_undo.RemoveAt(_undo.Count() - 1);
		Changed();

		return true;
	}

	bool Redo()
	{
		if (_redo.Count() == 0)
			return false;

		_undo.Add(Text());
		SetLines(_redo.Get(_redo.Count() - 1));
		_redo.RemoveAt(_redo.Count() - 1);
		Changed();

		return true;
	}

	Error<void> Save()
	{
		if (File.WriteAllText(Path, Text()) is error e)
			return error("Kann " + Path + " nicht schreiben.", (int)ErrorKind.Io);

		_s[0].Dirty = false;
		OfferDownload(Path);

		return;
	}
}
