// Changes of single values in the text of a YAML file: the value after "key:" in a line (block or flow style) is
// replaced and everything else of the line - other keys, the comment - stays as it was. The studio never writes a
// whole YAML file anew, so tables.yaml keeps its comments and its layout.

namespace Amber.Studio;

using System;
using Amber.Base;

/// The value as YAML: plain if it can be read back as the same text, else double-quoted.
string YamlValue(string value, bool quoted)
{
	bool plain = !quoted && value.Length > 0 && value.Trim().ToString() == value;

	if (plain)
	{
		string specials = "\"'&*!|>%@`#,[]{}";

		if (specials.IndexOf(value[0]) >= 0 || value[0] == '-' && value.Length > 1 && value[1] == ' ')
			plain = false;

		if (value.Contains(": ") || value.Contains(" #") || value.EndsWith(":"))
			plain = false;

		if (value.Contains(",") || value.Contains("}") || value.Contains("]"))
			plain = false; // inside a flow mapping these end the value
	}

	if (plain)
		return value;

	return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
}

/// True if the character may stand before a key ("key:" at the start, after a space, "{" or ",").
bool KeyBoundary(string line, int at)
{
	if (at == 0)
		return true;

	char c = line[at - 1];

	return c == ' ' || c == '\t' || c == '{' || c == ',';
}

/// Where the key of the line starts ("key:" or "\"key\":"), -1 if the line has no such key.
int FindKey(string line, string key)
{
	foreach (var form in new string[] { key + ":", "\"" + key + "\":", "'" + key + "':" })
	{
		int from = 0;

		while (from < line.Length)
		{
			int at = line.IndexOf(form, from);

			if (at < 0)
				break;

			int after = at + form.Length;

			if (KeyBoundary(line, at) && (after >= line.Length || line[after] == ' ' || line[after] == '\t'))
				return at;

			from = at + 1;
		}
	}

	return -1;
}

/// The line with the value of the key replaced (the line as it was if the key is not in it). In a flow mapping the
/// value ends at "," or "}", else at a comment (" #") or the end of the line.
string ReplaceYamlValue(string line, string key, string value)
{
	int at = FindKey(line, key);

	if (at < 0)
		return line;

	int colon = line.IndexOf(':', at + key.Length);
	int start = colon + 1;

	while (start < line.Length && line[start] == ' ')
		start += 1;

	bool flow = line.Substring(0, at).Contains("{");
	int end = start;
	bool quoted = false;

	if (start < line.Length && (line[start] == '"' || line[start] == '\''))
	{
		quoted = true;

		char quote = line[start];

		end = start + 1;

		while (end < line.Length)
		{
			if (line[end] == '\\' && quote == '"')
				end += 2;
			else if (line[end] == quote)
			{
				if (quote == '\'' && end + 1 < line.Length && line[end + 1] == '\'')
					end += 2;
				else
				{
					end += 1;

					break;
				}
			}
			else
				end += 1;
		}

		end = Math.Min(end, line.Length);
	}
	else
	{
		while (end < line.Length)
		{
			char c = line[end];

			if (flow && (c == ',' || c == '}'))
				break;

			if (c == '#' && end > 0 && line[end - 1] == ' ')
				break;

			end += 1;
		}

		while (end > start && line[end - 1] == ' ')
			end -= 1;
	}

	string written = YamlValue(value, quoted);
	string before = line.Substring(0, colon + 1) + " ";

	return before + written + line.Substring(end);
}

/// The number of spaces at the start of the line.
int IndentOf(string line)
{
	int count = 0;

	while (count < line.Length && line[count] == ' ')
		count += 1;

	return count;
}

/// True for a line without content (empty or a comment).
bool BlankYaml(string line)
{
	string trimmed = line.Trim().ToString();

	return trimmed.Length == 0 || trimmed.StartsWith("#");
}

/// The key of a line "key: ..." (without quotes), or "".
string KeyOfLine(string line)
{
	string trimmed = line.Trim().ToString();

	if (trimmed.StartsWith("- ") || trimmed.StartsWith("#"))
		return "";

	int colon = trimmed.IndexOf(':');

	if (colon <= 0)
		return "";

	string key = trimmed.Substring(0, colon);

	if (key.Length >= 2 && (key[0] == '"' || key[0] == '\''))
		key = key.Substring(1, key.Length - 2);

	return key;
}

/// A key as it can be written in YAML and in the scripts: lowercase letters, digits and "_".
string SymbolName(string text)
{
	var builder = StringBuilder.Create();
	string lower = text.ToLower();

	for (var i = 0; i < lower.Length; i += 1)
	{
		char c = lower[i];

		if (c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_')
			builder.Append(c);
		else if (c == ' ' || c == '-')
			builder.Append('_');
	}

	string result = builder.ToString();

	if (result.Length == 0 || result[0] >= '0' && result[0] <= '9')
		result = "n_" + result;

	return result;
}
