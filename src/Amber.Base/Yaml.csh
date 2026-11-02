// A YAML reader for the subset the game content uses (C#: YamlDotNet): block mappings and sequences by indentation, flow
// mappings { a: 1 } and sequences [1, 2] (also across lines), plain, single and double quoted scalars, comments, empty
// values. Block scalars (| and >), anchors, tags and several documents are not supported and give an error.
//
// All scalars stay text (like YamlDotNet's deserializer into object); Plain says whether a scalar was written without
// quotes, which the schema check needs to type numbers and booleans. An empty value, ~ and null are Null nodes.

namespace Amber.Base;

using System;

enum YamlKind : int32
{
	Null,
	Scalar,
	Mapping,
	Sequence
}

/// A node of a YAML document. Mappings keep their keys in the order of the file.
struct YamlNode
{
	YamlKind Kind;
	/// Scalar: the text; Null: how it was written ("", "~", "null").
	string Value;
	/// Scalar: written without quotes.
	bool Plain;
	/// Mapping: the keys.
	List<string> Keys;
	/// Mapping: the values of the keys; sequence: the items.
	List<YamlNode> Items;
	int Line;

	static YamlNode Null(int line, string text)
	{
		return YamlNode { Kind = YamlKind.Null, Value = text, Plain = true, Line = line };
	}

	static YamlNode Scalar(string value, bool plain, int line)
	{
		return YamlNode { Kind = YamlKind.Scalar, Value = value, Plain = plain, Line = line };
	}

	static YamlNode Mapping(int line)
	{
		return YamlNode { Kind = YamlKind.Mapping, Keys = List<string>.Create(), Items = List<YamlNode>.Create(), Line = line };
	}

	static YamlNode Sequence(int line)
	{
		return YamlNode { Kind = YamlKind.Sequence, Keys = List<string>.Create(), Items = List<YamlNode>.Create(), Line = line };
	}

	bool IsNull()
	{
		return Kind == YamlKind.Null;
	}

	bool IsScalar()
	{
		return Kind == YamlKind.Scalar;
	}

	bool IsMapping()
	{
		return Kind == YamlKind.Mapping;
	}

	bool IsSequence()
	{
		return Kind == YamlKind.Sequence;
	}

	/// Number of entries of a mapping or items of a sequence.
	int Count()
	{
		if (Kind != YamlKind.Mapping && Kind != YamlKind.Sequence)
			return 0;

		return Items.Count();
	}

	bool ContainsKey(string key)
	{
		return IndexOfKey(key) >= 0;
	}

	int IndexOfKey(string key)
	{
		if (Kind != YamlKind.Mapping)
			return -1;

		for (var i = 0; i < Keys.Count(); i += 1)
		{
			if (Keys.Get(i) == key)
				return i;
		}

		return -1;
	}

	/// The value of the key (a Null node counts as a value), or no value if the key is missing.
	Optional<YamlNode> Get(string key)
	{
		int index = IndexOfKey(key);

		if (index < 0)
			return null;

		return Items.Get(index);
	}

	/// The value of the key if it exists and is not null (C#: GetValueOrDefault(key) is { } value).
	Optional<YamlNode> GetValue(string key)
	{
		if (Get(key) is YamlNode value)
		{
			if (!value.IsNull())
				return value;
		}

		return null;
	}

	/// The scalar text of the key, or null if it is missing or not a scalar (C#: GetValueOrDefault(key) as string).
	string GetText(string key)
	{
		if (Get(key) is YamlNode value)
		{
			if (value.IsScalar())
				return value.Value;
		}

		return null;
	}

	string KeyAt(int index)
	{
		return Keys.Get(index);
	}

	YamlNode ItemAt(int index)
	{
		return Items.Get(index);
	}

	/// Sets a key of a mapping (replaces the value of an existing key, else appends it).
	void Set(string key, YamlNode value)
	{
		int index = IndexOfKey(key);

		if (index >= 0)
		{
			Items.Set(index, value);

			return;
		}

		Keys.Add(key);
		Items.Add(value);
	}

	void Add(YamlNode item)
	{
		Items.Add(item);
	}

	/// A copy of the mapping or sequence with its own key and item lists (the items themselves are shared).
	YamlNode ShallowCopy()
	{
		if (Kind != YamlKind.Mapping && Kind != YamlKind.Sequence)
			return this;

		var copy = Kind == YamlKind.Mapping ? Mapping(Line) : Sequence(Line);

		for (var i = 0; i < Items.Count(); i += 1)
		{
			if (Kind == YamlKind.Mapping)
				copy.Keys.Add(Keys.Get(i));

			copy.Items.Add(Items.Get(i));
		}

		return copy;
	}

	/// A readable, canonical form of the node (for tests and comparisons): {key: value, ...}, [a, b], 'text', ~.
	string Describe()
	{
		switch (Kind)
		{
			case YamlKind.Null:
				return "~";
			case YamlKind.Scalar:
				return (Plain ? "" : "\"") + Value + (Plain ? "" : "\"");
			case YamlKind.Mapping:
			{
				var builder = StringBuilder.Create();

				builder.Append("{");

				for (var i = 0; i < Items.Count(); i += 1)
				{
					if (i > 0)
						builder.Append(", ");

					builder.Append(Keys.Get(i) + ": " + Items.Get(i).Describe());
				}

				builder.Append("}");

				return builder.ToString();
			}
			default:
			{
				var builder = StringBuilder.Create();

				builder.Append("[");

				for (var i = 0; i < Items.Count(); i += 1)
				{
					if (i > 0)
						builder.Append(", ");

					builder.Append(Items.Get(i).Describe());
				}

				builder.Append("]");

				return builder.ToString();
			}
		}
	}
}

/// One line of the document without its comment: the indentation and the content.
struct YamlLine
{
	int Number;
	int Indent;
	string Content;
}

/// Reads a YAML document. Errors name the line: "(12): ...".
Error<YamlNode> ParseYaml(string text)
{
	var parser = YamlParser { Lines = List<YamlLine>.Create(), Index = 0 };

	try parser.SplitLines(text);

	var root = try parser.ParseNode(0);

	parser.SkipBlank();

	if (parser.Index < parser.Lines.Count())
		return error("(" + parser.Lines.Get(parser.Index).Number + "): unexpected content '" + parser.Lines.Get(parser.Index).Content + "'.", (int)ErrorKind.InvalidData);

	return root;
}

struct YamlParser
{
	List<YamlLine> Lines;
	int Index;

	Error<void> SplitLines(string text)
	{
		var physical = text.Replace("\r\n", "\n").Split('\n');

		for (var i = 0; i < physical.Length; i += 1)
		{
			string line = physical[i].ToString();
			int indent = 0;

			while (indent < line.Length && line[indent] == ' ')
				indent += 1;

			if (indent < line.Length && line[indent] == '\t')
				return error("(" + (i + 1) + "): tabs are not allowed for indentation.", (int)ErrorKind.InvalidData);

			string content = StripComment(line.Substring(indent));

			if (content == "---" || content == "...")
			{
				if (i == 0 || content == "...")
					continue;

				return error("(" + (i + 1) + "): only one document is supported.", (int)ErrorKind.InvalidData);
			}

			Lines.Add(YamlLine { Number = i + 1, Indent = indent, Content = content });
		}

		return;
	}

	/// The content without a comment (a # at the start or after a space, outside of quotes) and without trailing spaces.
	string StripComment(string content)
	{
		char quote = (char)0;

		for (var i = 0; i < content.Length; i += 1)
		{
			char c = content[i];

			if (quote != 0)
			{
				if (c == '\\' && quote == '"')
				{
					i += 1;
					continue;
				}

				if (c == quote)
					quote = (char)0;

				continue;
			}

			if ((c == '"' || c == '\'') && (i == 0 || IsQuoteStart(content[i - 1])))
			{
				quote = c;
				continue;
			}

			if (c == '#' && (i == 0 || content[i - 1] == ' ' || content[i - 1] == '\t'))
				return TrimEnd(content.Substring(0, i));
		}

		return TrimEnd(content);
	}

	bool IsQuoteStart(char previous)
	{
		return previous == ' ' || previous == '\t' || previous == '[' || previous == '{' || previous == ',' || previous == ':' || previous == '-';
	}

	void SkipBlank()
	{
		while (Index < Lines.Count() && Lines.Get(Index).Content.Length == 0)
			Index += 1;
	}

	string Where(int line)
	{
		return "(" + line + "): ";
	}

	/// The node at the current line if it is indented at least 'minIndent', else a Null node.
	Error<YamlNode> ParseNode(int minIndent)
	{
		SkipBlank();

		if (Index >= Lines.Count())
			return YamlNode.Null(0, "");

		var line = Lines.Get(Index);

		if (line.Indent < minIndent)
			return YamlNode.Null(line.Number, "");

		if (IsSequenceItem(line.Content))
			return ParseSequence(line.Indent);

		if (MappingKeyEnd(line.Content) >= 0)
			return ParseMapping(line.Indent);

		Index += 1;

		return ParseInline(line.Content, line.Number, line.Indent);
	}

	bool IsSequenceItem(string content)
	{
		return content == "-" || content.StartsWith("- ");
	}

	/// The position of the ':' that ends the key of a block mapping line, or -1 if the line is not "key: value".
	int MappingKeyEnd(string content)
	{
		if (content.Length == 0 || content[0] == '[' || content[0] == '{' || content[0] == '-' && IsSequenceItem(content))
			return -1;

		int start = 0;

		if (content[0] == '"' || content[0] == '\'')
		{
			int end = ClosingQuote(content, 0);

			if (end < 0)
				return -1;

			start = end + 1;

			while (start < content.Length && content[start] == ' ')
				start += 1;

			if (start < content.Length && content[start] == ':' && (start + 1 == content.Length || content[start + 1] == ' '))
				return start;

			return -1;
		}

		for (var i = start; i < content.Length; i += 1)
		{
			if (content[i] == ':' && (i + 1 == content.Length || content[i + 1] == ' '))
				return i;
		}

		return -1;
	}

	Error<string> KeyText(string raw, int lineNumber)
	{
		string key = raw.Trim().ToString();

		if (key.Length > 0 && (key[0] == '"' || key[0] == '\''))
		{
			var node = try ParseQuoted(key, lineNumber);

			return node.Value;
		}

		return key;
	}

	Error<YamlNode> ParseMapping(int indent)
	{
		var mapping = YamlNode.Mapping(Lines.Get(Index).Number);

		while (true)
		{
			SkipBlank();

			if (Index >= Lines.Count())
				break;

			var line = Lines.Get(Index);

			if (line.Indent < indent)
				break;

			if (line.Indent > indent)
				return error(Where(line.Number) + "bad indentation of a mapping entry.", (int)ErrorKind.InvalidData);

			int colon = MappingKeyEnd(line.Content);

			if (colon < 0)
			{
				if (IsSequenceItem(line.Content))
					break;

				return error(Where(line.Number) + "expected 'key: value' but found '" + line.Content + "'.", (int)ErrorKind.InvalidData);
			}

			string key = try KeyText(line.Content.Substring(0, colon), line.Number);
			string rest = line.Content.Substring(colon + 1).Trim().ToString();

			if (mapping.ContainsKey(key))
				return error(Where(line.Number) + "the key '" + key + "' is used twice.", (int)ErrorKind.InvalidData);

			Index += 1;

			if (rest.Length > 0)
			{
				mapping.Set(key, try ParseInline(rest, line.Number, line.Indent + colon + 2));
				continue;
			}

			SkipBlank();

			if (Index < Lines.Count())
			{
				var next = Lines.Get(Index);

				if (next.Indent > indent)
				{
					mapping.Set(key, try ParseNode(indent + 1));
					continue;
				}

				// a sequence may start at the indentation of its key
				if (next.Indent == indent && IsSequenceItem(next.Content))
				{
					mapping.Set(key, try ParseSequence(indent));
					continue;
				}
			}

			mapping.Set(key, YamlNode.Null(line.Number, ""));
		}

		return mapping;
	}

	Error<YamlNode> ParseSequence(int indent)
	{
		var sequence = YamlNode.Sequence(Lines.Get(Index).Number);

		while (true)
		{
			SkipBlank();

			if (Index >= Lines.Count())
				break;

			var line = Lines.Get(Index);

			if (line.Indent < indent || !IsSequenceItem(line.Content))
				break;

			if (line.Indent > indent)
				return error(Where(line.Number) + "bad indentation of a sequence item.", (int)ErrorKind.InvalidData);

			int offset = 1;

			while (offset < line.Content.Length && line.Content[offset] == ' ')
				offset += 1;

			string rest = line.Content.Substring(offset);

			if (rest.Length == 0)
			{
				Index += 1;
				sequence.Add(try ParseNode(indent + 1));
				continue;
			}

			if (MappingKeyEnd(rest) >= 0 || IsSequenceItem(rest))
			{
				// "- key: value" starts a mapping (or "- - x" a sequence) at the column after the dash
				Lines.Set(Index, YamlLine { Number = line.Number, Indent = indent + offset, Content = rest });
				sequence.Add(try ParseNode(indent + offset));
				continue;
			}

			Index += 1;
			sequence.Add(try ParseInline(rest, line.Number, indent + offset));
		}

		return sequence;
	}

	/// A value written on one line (a flow collection may continue on the following lines).
	Error<YamlNode> ParseInline(string text, int lineNumber, int column)
	{
		if (text[0] == '[' || text[0] == '{')
		{
			string flow = text;

			while (!FlowComplete(flow))
			{
				if (Index >= Lines.Count())
					return error(Where(lineNumber) + "unterminated flow collection.", (int)ErrorKind.InvalidData);

				flow = flow + " " + Lines.Get(Index).Content;
				Index += 1;
			}

			var reader = YamlFlowReader { Text = flow, Position = 0, LineNumber = lineNumber };
			var node = try reader.ReadValue();

			reader.SkipSpaces();

			if (reader.Position < flow.Length)
				return error(Where(lineNumber) + "unexpected text after a flow collection: '" + flow.Substring(reader.Position) + "'.", (int)ErrorKind.InvalidData);

			return node;
		}

		if (text[0] == '"' || text[0] == '\'')
		{
			int end = ClosingQuote(text, 0);

			if (end < 0)
				return error(Where(lineNumber) + "unterminated string.", (int)ErrorKind.InvalidData);

			if (end != text.Length - 1)
				return error(Where(lineNumber) + "unexpected text after a string: '" + text.Substring(end + 1) + "'.", (int)ErrorKind.InvalidData);

			return ParseQuoted(text, lineNumber);
		}

		if (text[0] == '|' || text[0] == '>')
			return error(Where(lineNumber) + "block scalars (| and >) are not supported.", (int)ErrorKind.InvalidData);

		if (text[0] == '&' || text[0] == '*' || text[0] == '!')
			return error(Where(lineNumber) + "anchors, aliases and tags are not supported.", (int)ErrorKind.InvalidData);

		// a plain scalar may continue on more indented lines (folded with spaces)
		string value = text;

		while (Index < Lines.Count())
		{
			var next = Lines.Get(Index);

			if (next.Content.Length == 0 || next.Indent < column || IsSequenceItem(next.Content) || MappingKeyEnd(next.Content) >= 0)
				break;

			value = value + " " + next.Content;
			Index += 1;
		}

		return PlainScalar(value, lineNumber);
	}

	/// True if the brackets of the flow text are balanced (outside of quotes).
	bool FlowComplete(string text)
	{
		int depth = 0;
		char quote = (char)0;

		for (var i = 0; i < text.Length; i += 1)
		{
			char c = text[i];

			if (quote != 0)
			{
				if (c == '\\' && quote == '"')
				{
					i += 1;
					continue;
				}

				if (c == quote)
					quote = (char)0;

				continue;
			}

			if (c == '"' || c == '\'')
				quote = c;
			else if (c == '[' || c == '{')
				depth += 1;
			else if (c == ']' || c == '}')
				depth -= 1;
		}

		return depth <= 0;
	}
}

/// The position of the quote that closes the string starting at 'start', or -1.
int ClosingQuote(string text, int start)
{
	char quote = text[start];

	for (var i = start + 1; i < text.Length; i += 1)
	{
		if (quote == '"' && text[i] == '\\')
		{
			i += 1;
			continue;
		}

		if (text[i] == quote)
		{
			if (quote == '\'' && i + 1 < text.Length && text[i + 1] == '\'')
			{
				i += 1;
				continue;
			}

			return i;
		}
	}

	return -1;
}

YamlNode PlainScalar(string text, int line)
{
	string value = text.Trim().ToString();

	if (value.Length == 0 || value == "~" || value == "null" || value == "Null" || value == "NULL")
		return YamlNode.Null(line, value);

	return YamlNode.Scalar(value, true, line);
}

/// A quoted scalar ("..." with escapes, or '...' with '' for a quote).
Error<YamlNode> ParseQuoted(string text, int line)
{
	var builder = StringBuilder.Create();
	char quote = text[0];
	int i = 1;

	while (i < text.Length)
	{
		char c = text[i];

		if (quote == '\'')
		{
			if (c == '\'')
			{
				if (i + 1 < text.Length && text[i + 1] == '\'')
				{
					builder.Append('\'');
					i += 2;
					continue;
				}

				return YamlNode.Scalar(builder.ToString(), false, line);
			}

			builder.Append(c);
			i += 1;
			continue;
		}

		if (c == '"')
			return YamlNode.Scalar(builder.ToString(), false, line);

		if (c == '\\' && i + 1 < text.Length)
		{
			char escaped = text[i + 1];

			i += 2;

			switch (escaped)
			{
				case 'n':
					builder.Append('\n');
					break;
				case 't':
					builder.Append('\t');
					break;
				case 'r':
					builder.Append('\r');
					break;
				case '0':
					builder.Append((char)0);
					break;
				case '"':
					builder.Append('"');
					break;
				case '\\':
					builder.Append('\\');
					break;
				case '/':
					builder.Append('/');
					break;
				case 'x':
				case 'u':
				case 'U':
				{
					int digits = escaped == 'x' ? 2 : (escaped == 'u' ? 4 : 8);

					if (i + digits > text.Length)
						return error("(" + line + "): bad escape sequence.", (int)ErrorKind.InvalidData);

					var code = TryParseHex(text.Substring(i, digits));

					if (code is uint64 value)
						builder.Append(CodePointText((int)value));
					else
						return error("(" + line + "): bad escape sequence.", (int)ErrorKind.InvalidData);

					i += digits;
					break;
				}
				default:
					return error("(" + line + "): unknown escape sequence '\\" + text.Substring(i - 1, 1) + "'.", (int)ErrorKind.InvalidData);
			}

			continue;
		}

		builder.Append(c);
		i += 1;
	}

	return error("(" + line + "): unterminated string.", (int)ErrorKind.InvalidData);
}

/// Reads flow collections: { key: value, ... } and [ item, ... ].
struct YamlFlowReader
{
	string Text;
	int Position;
	int LineNumber;

	void SkipSpaces()
	{
		while (Position < Text.Length && (Text[Position] == ' ' || Text[Position] == '\t'))
			Position += 1;
	}

	char Current()
	{
		return Position < Text.Length ? Text[Position] : (char)0;
	}

	Error<YamlNode> ReadValue()
	{
		SkipSpaces();

		char c = Current();

		if (c == '{')
			return ReadMapping();

		if (c == '[')
			return ReadSequence();

		if (c == '"' || c == '\'')
			return ReadQuoted();

		return ReadPlain(false);
	}

	Error<YamlNode> ReadQuoted()
	{
		int end = ClosingQuote(Text, Position);

		if (end < 0)
			return error("(" + LineNumber + "): unterminated string.", (int)ErrorKind.InvalidData);

		var node = try ParseQuoted(Text.Substring(Position, end - Position + 1), LineNumber);

		Position = end + 1;

		return node;
	}

	/// A plain scalar of a flow collection ends at ',', ']', '}' (and at ': ' for a key).
	Error<YamlNode> ReadPlain(bool key)
	{
		int start = Position;

		while (Position < Text.Length)
		{
			char c = Text[Position];

			if (c == ',' || c == ']' || c == '}')
				break;

			if (c == ':' && (Position + 1 >= Text.Length || Text[Position + 1] == ' ' || Text[Position + 1] == ',' || Text[Position + 1] == '}' || Text[Position + 1] == ']'))
			{
				if (key)
					break;
			}

			Position += 1;
		}

		return PlainScalar(Text.Substring(start, Position - start), LineNumber);
	}

	Error<YamlNode> ReadMapping()
	{
		var mapping = YamlNode.Mapping(LineNumber);

		Position += 1;
		SkipSpaces();

		if (Current() == '}')
		{
			Position += 1;

			return mapping;
		}

		while (true)
		{
			SkipSpaces();

			YamlNode keyNode;

			if (Current() == '"' || Current() == '\'')
				keyNode = try ReadQuoted();
			else
				keyNode = try ReadPlain(true);

			string key = keyNode.Value;

			SkipSpaces();

			YamlNode value = YamlNode.Null(LineNumber, "");

			if (Current() == ':')
			{
				Position += 1;
				SkipSpaces();

				if (Current() != ',' && Current() != '}')
					value = try ReadValue();
			}

			if (mapping.ContainsKey(key))
				return error("(" + LineNumber + "): the key '" + key + "' is used twice.", (int)ErrorKind.InvalidData);

			mapping.Set(key, value);
			SkipSpaces();

			if (Current() == ',')
			{
				Position += 1;
				continue;
			}

			if (Current() == '}')
			{
				Position += 1;

				return mapping;
			}

			return error("(" + LineNumber + "): expected ',' or '}' in a flow mapping.", (int)ErrorKind.InvalidData);
		}

		return mapping;
	}

	Error<YamlNode> ReadSequence()
	{
		var sequence = YamlNode.Sequence(LineNumber);

		Position += 1;
		SkipSpaces();

		if (Current() == ']')
		{
			Position += 1;

			return sequence;
		}

		while (true)
		{
			sequence.Add(try ReadValue());
			SkipSpaces();

			if (Current() == ',')
			{
				Position += 1;
				SkipSpaces();

				// a trailing comma
				if (Current() == ']')
				{
					Position += 1;

					return sequence;
				}

				continue;
			}

			if (Current() == ']')
			{
				Position += 1;

				return sequence;
			}

			return error("(" + LineNumber + "): expected ',' or ']' in a flow sequence.", (int)ErrorKind.InvalidData);
		}

		return sequence;
	}
}
