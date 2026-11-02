// A small XML reader and writer for the Tiled files (C#: System.Xml.Linq): elements, attributes, text, comments, the XML
// declaration and the five predefined entities plus character references. No namespaces, no DTDs.

namespace Amber.Player.Tiled;

using System;
using Amber.Base;

/// An element with its attributes (in document order), child elements and text. Copies share the lists.
struct XmlElement
{
	string Name;
	List<string> AttributeNames;
	List<string> AttributeValues;
	List<XmlElement> Children;
	string Text;

	static XmlElement Create(string name)
	{
		return XmlElement { Name = name, AttributeNames = List<string>.Create(), AttributeValues = List<string>.Create(), Children = List<XmlElement>.Create(), Text = "" };
	}

	/// The value of an attribute, or null.
	string Attribute(string name)
	{
		int index = IndexOfText(AttributeNames, name);

		return index < 0 ? null : AttributeValues.Get(index);
	}

	void SetAttribute(string name, string value)
	{
		int index = IndexOfText(AttributeNames, name);

		if (index < 0)
		{
			AttributeNames.Add(name);
			AttributeValues.Add(value);
		}
		else
			AttributeValues.Set(index, value);
	}

	/// The first child element with the name.
	Optional<XmlElement> Element(string name)
	{
		foreach (var child in Children)
		{
			if (child.Name == name)
				return child;
		}

		return null;
	}

	/// All child elements with the name.
	List<XmlElement> Elements(string name)
	{
		var result = List<XmlElement>.Create();

		foreach (var child in Children)
		{
			if (child.Name == name)
				result.Add(child);
		}

		return result;
	}
}

Error<XmlElement> ParseXml(string text)
{
	var reader = XmlReader { Text = text, Position = 0 };

	try reader.SkipProlog();

	var root = try reader.ReadElement();

	return root;
}

Error<XmlElement> LoadXml(string path)
{
	var text = File.ReadAllText(path);

	if (text is string content)
	{
		var parsed = ParseXml(content);

		if (parsed is XmlElement root)
			return root;

		return error(path + ": " + parsed.Message, (int)ErrorKind.InvalidData);
	}

	return error("cannot read '" + path + "': " + text.Message, (int)ErrorKind.Io);
}

struct XmlReader
{
	string Text;
	int Position;

	Error<void> Fail(string message)
	{
		int line = 1;

		for (var i = 0; i < Position && i < Text.Length; i += 1)
		{
			if (Text[i] == '\n')
				line += 1;
		}

		return error("XML line " + line + ": " + message, (int)ErrorKind.InvalidData);
	}

	bool StartsWith(string value)
	{
		if (Position + value.Length > Text.Length)
			return false;

		for (var i = 0; i < value.Length; i += 1)
		{
			if (Text[Position + i] != value[i])
				return false;
		}

		return true;
	}

	void SkipWhitespace()
	{
		while (Position < Text.Length && (Text[Position] == ' ' || Text[Position] == '\t' || Text[Position] == '\r' || Text[Position] == '\n'))
			Position += 1;
	}

	/// Skips to the end of the text (inclusive); false if it is missing.
	bool SkipPast(string end)
	{
		while (Position < Text.Length)
		{
			if (StartsWith(end))
			{
				Position += end.Length;

				return true;
			}

			Position += 1;
		}

		return false;
	}

	/// The declaration, comments, processing instructions and a DOCTYPE before the root element.
	Error<void> SkipProlog()
	{
		if (Text.Length >= 3 && (int)Text[0] == 0xEF && (int)Text[1] == 0xBB && (int)Text[2] == 0xBF)
			Position += 3;

		while (true)
		{
			SkipWhitespace();

			if (StartsWith("<?"))
			{
				if (!SkipPast("?>"))
					return Fail("unterminated processing instruction");
			}
			else if (StartsWith("<!--"))
			{
				if (!SkipPast("-->"))
					return Fail("unterminated comment");
			}
			else if (StartsWith("<!"))
			{
				if (!SkipPast(">"))
					return Fail("unterminated declaration");
			}
			else
				return;
		}
	}

	bool IsNameCharacter(char c)
	{
		return c != ' ' && c != '\t' && c != '\r' && c != '\n' && c != '/' && c != '>' && c != '=' && c != '<' && c != '"' && c != '\'';
	}

	string ReadName()
	{
		int start = Position;

		while (Position < Text.Length && IsNameCharacter(Text[Position]))
			Position += 1;

		return Text.Substring(start, Position - start);
	}

	Error<XmlElement> ReadElement()
	{
		if (!StartsWith("<"))
			return FailElement("expected an element");

		Position += 1;

		string name = ReadName();

		if (name.Length == 0)
			return FailElement("expected an element name");

		var element = XmlElement.Create(name);

		while (true)
		{
			SkipWhitespace();

			if (Position >= Text.Length)
				return FailElement("unterminated element <" + name + ">");

			if (StartsWith("/>"))
			{
				Position += 2;

				return element;
			}

			if (Text[Position] == '>')
			{
				Position += 1;

				break;
			}

			string attribute = ReadName();

			SkipWhitespace();

			if (attribute.Length == 0 || Position >= Text.Length || Text[Position] != '=')
				return FailElement("expected an attribute in <" + name + ">");

			Position += 1;
			SkipWhitespace();

			if (Position >= Text.Length || (Text[Position] != '"' && Text[Position] != '\''))
				return FailElement("expected a quoted value for '" + attribute + "'");

			char quote = Text[Position];
			int start = Position + 1;

			Position = start;

			while (Position < Text.Length && Text[Position] != quote)
				Position += 1;

			if (Position >= Text.Length)
				return FailElement("unterminated value of '" + attribute + "'");

			element.AttributeNames.Add(attribute);
			element.AttributeValues.Add(Unescape(Text.Substring(start, Position - start)));
			Position += 1;
		}

		var text = StringBuilder.Create();

		while (true)
		{
			if (Position >= Text.Length)
				return FailElement("element <" + name + "> is not closed");

			if (StartsWith("</"))
			{
				Position += 2;

				string closing = ReadName();

				SkipWhitespace();

				if (closing != name || Position >= Text.Length || Text[Position] != '>')
					return FailElement("</" + name + "> expected");

				Position += 1;
				element.Text = Unescape(text.ToString());

				return element;
			}

			if (StartsWith("<!--"))
			{
				if (!SkipPast("-->"))
					return FailElement("unterminated comment");

				continue;
			}

			if (StartsWith("<![CDATA["))
			{
				Position += 9;

				int start = Position;

				if (!SkipPast("]]>"))
					return FailElement("unterminated CDATA");

				text.Append(Text.Substring(start, Position - 3 - start).Replace("&", "&amp;").Replace("<", "&lt;"));

				continue;
			}

			if (StartsWith("<?"))
			{
				if (!SkipPast("?>"))
					return FailElement("unterminated processing instruction");

				continue;
			}

			if (Text[Position] == '<')
			{
				element.Children.Add(try ReadElement());

				continue;
			}

			int textStart = Position;

			while (Position < Text.Length && Text[Position] != '<')
				Position += 1;

			text.Append(Text.Substring(textStart, Position - textStart));
		}
	}

	Error<XmlElement> FailElement(string message)
	{
		var failure = Fail(message);

		return error(failure.Message, (int)ErrorKind.InvalidData);
	}
}

/// The index of the character at or after the start, or -1.
int IndexOfFrom(string text, char c, int start)
{
	for (var i = start; i < text.Length; i += 1)
	{
		if (text[i] == c)
			return i;
	}

	return -1;
}

/// Replaces the entities and character references.
string Unescape(string text)
{
	if (text.IndexOf('&') < 0)
		return text;

	var result = StringBuilder.Create();
	int i = 0;

	while (i < text.Length)
	{
		if (text[i] != '&')
		{
			result.Append(text[i]);
			i += 1;

			continue;
		}

		int end = IndexOfFrom(text, ';', i);

		if (end < 0)
		{
			result.Append(text.Substring(i));

			break;
		}

		string entity = text.Substring(i + 1, end - i - 1);

		if (entity == "amp")
			result.Append('&');
		else if (entity == "lt")
			result.Append('<');
		else if (entity == "gt")
			result.Append('>');
		else if (entity == "quot")
			result.Append('"');
		else if (entity == "apos")
			result.Append('\'');
		else if (entity.StartsWith("#x") && TryParseHex(entity.Substring(2)) is uint64 hex)
			result.Append(CodePointText((int)hex));
		else if (entity.StartsWith("#") && TryParseInt(entity.Substring(1)) is int value)
			result.Append(CodePointText(value));
		else
			result.Append("&" + entity + ";");

		i = end + 1;
	}

	return result.ToString();
}

/// The text with the characters XML needs escaped (attribute values and text).
string EscapeXml(string text)
{
	return text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
}
