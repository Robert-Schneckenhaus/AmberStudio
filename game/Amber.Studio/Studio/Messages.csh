// The panel at the bottom: what the check of the content found (the same check as --check-content: tables, scripts,
// screens and the cooked pack), what the studio did, and the places a search found. An entry that names a file and a
// line opens it there.

namespace Amber.Studio;

using System;
using Amber.Base;
using Amber.Player.Content;

enum MessageKind : int32
{
	Info,
	Warning,
	Error,
	/// A place a search found.
	Found
}

struct StudioMessage
{
	MessageKind Kind;
	string Text;
	/// The file it is about ("" none) and its line (1-based, 0 none).
	string File;
	int Line;

	static StudioMessage Of(MessageKind kind, string text)
	{
		return StudioMessage { Kind = kind, Text = text, File = "", Line = 0 };
	}

	static StudioMessage At(MessageKind kind, string text, string file, int line)
	{
		return StudioMessage { Kind = kind, Text = text, File = file, Line = line };
	}

	string Label()
	{
		string kind = Kind == MessageKind.Error ? "Fehler" : Kind == MessageKind.Warning ? "Warnung" : Kind == MessageKind.Found ? "Fund" : "Info";

		return kind + ": " + Text;
	}
}

/// The message of a line of a compiler or loader error: "path(12,5): error AMS0123: ..." names the file and the line;
/// "(12): ..." of the YAML reader names a line of tables.yaml.
StudioMessage ParseProblem(string line, string tablesPath)
{
	int open = line.IndexOf("(");

	if (open >= 0)
	{
		int close = line.IndexOf(")", open);

		if (close > open)
		{
			string inside = line.Substring(open + 1, close - open - 1);
			int comma = inside.IndexOf(",");
			string number = comma >= 0 ? inside.Substring(0, comma) : inside;

			if (TryParseInt(number) is int lineNumber)
			{
				string file = line.Substring(0, open).Trim().ToString();

				if (file.Length == 0 || file.StartsWith("tables.yaml"))
					file = tablesPath;

				return StudioMessage.At(MessageKind.Error, line, file, lineNumber);
			}
		}
	}

	if (line.StartsWith("tables.yaml"))
		return StudioMessage.At(MessageKind.Error, line, tablesPath, 0);

	return StudioMessage.Of(MessageKind.Error, line);
}

/// Checks the content of the project: every problem is a message; with none, a summary.
List<StudioMessage> CheckProject(StudioProject project)
{
	var messages = List<StudioMessage>.Create();
	var loaded = ContentSource.Load(project.Content, project.Root);

	if (loaded is not ContentSource content)
	{
		foreach (var line in SplitToList(loaded.Message, "\n"))
		{
			string text = line.Trim().ToString();

			if (text.Length > 0 && text != "The scripts have errors:")
				messages.Add(ParseProblem(text, project.TablesPath()));
		}

		return messages;
	}

	var cooked = PackCook.Cook(content);

	if (cooked is not uint8[] pack)
	{
		messages.Add(StudioMessage.Of(MessageKind.Error, "Pack: " + cooked.Message));

		return messages;
	}

	var verified = PackCook.Verify(content, pack);

	if (verified is not string summary)
	{
		messages.Add(StudioMessage.Of(MessageKind.Error, "Pack: " + verified.Message));

		return messages;
	}

	messages.Add(StudioMessage.Of(MessageKind.Info, "Inhalt in Ordnung: " + content.Texts.Count() + " Texte, " + content.Items.Count() + " Gegenstände, "
		+ content.Keywords.Count() + " Wörter, " + content.Compilation.Maps.Count() + " Karten; Pack: " + summary));

	return messages;
}
