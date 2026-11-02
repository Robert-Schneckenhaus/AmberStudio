// A JSON reader (C#: System.Text.Json) for the screen schema and for checking YAML documents against it.

namespace Amber.Base;

using System;

enum JsonKind : int32
{
	Null,
	Bool,
	Number,
	String,
	Array,
	Object
}

/// A JSON value. Objects keep their keys in the order of the text. Integers are exact (IsInteger, Integer).
struct JsonValue
{
	JsonKind Kind;
	bool Bool;
	double Number;
	bool IsInteger;
	int64 Integer;
	string Text;
	List<string> Keys;
	List<JsonValue> Items;

	static JsonValue Null()
	{
		return JsonValue { Kind = JsonKind.Null };
	}

	static JsonValue OfBool(bool value)
	{
		return JsonValue { Kind = JsonKind.Bool, Bool = value };
	}

	static JsonValue OfInteger(int64 value)
	{
		return JsonValue { Kind = JsonKind.Number, Number = (double)value, IsInteger = true, Integer = value };
	}

	static JsonValue OfNumber(double value)
	{
		return JsonValue { Kind = JsonKind.Number, Number = value, IsInteger = false };
	}

	static JsonValue OfString(string text)
	{
		return JsonValue { Kind = JsonKind.String, Text = text };
	}

	static JsonValue NewArray()
	{
		return JsonValue { Kind = JsonKind.Array, Keys = List<string>.Create(), Items = List<JsonValue>.Create() };
	}

	static JsonValue NewObject()
	{
		return JsonValue { Kind = JsonKind.Object, Keys = List<string>.Create(), Items = List<JsonValue>.Create() };
	}

	int Count()
	{
		if (Kind != JsonKind.Array && Kind != JsonKind.Object)
			return 0;

		return Items.Count();
	}

	Optional<JsonValue> Get(string key)
	{
		if (Kind != JsonKind.Object)
			return null;

		for (var i = 0; i < Keys.Count(); i += 1)
		{
			if (Keys.Get(i) == key)
				return Items.Get(i);
		}

		return null;
	}

	bool Has(string key)
	{
		if (Get(key) is JsonValue value)
			return true;

		return false;
	}

	void Set(string key, JsonValue value)
	{
		for (var i = 0; i < Keys.Count(); i += 1)
		{
			if (Keys.Get(i) == key)
			{
				Items.Set(i, value);

				return;
			}
		}

		Keys.Add(key);
		Items.Add(value);
	}

	void Add(JsonValue item)
	{
		Items.Add(item);
	}

	/// Structural equality (numbers compare by value).
	bool SameAs(JsonValue other)
	{
		if (Kind != other.Kind)
			return false;

		switch (Kind)
		{
			case JsonKind.Null:
				return true;
			case JsonKind.Bool:
				return Bool == other.Bool;
			case JsonKind.Number:
				return IsInteger && other.IsInteger ? Integer == other.Integer : Number == other.Number;
			case JsonKind.String:
				return Text == other.Text;
			case JsonKind.Array:
			{
				if (Items.Count() != other.Items.Count())
					return false;

				for (var i = 0; i < Items.Count(); i += 1)
				{
					if (!Items.Get(i).SameAs(other.Items.Get(i)))
						return false;
				}

				return true;
			}
			default:
			{
				if (Items.Count() != other.Items.Count())
					return false;

				for (var i = 0; i < Keys.Count(); i += 1)
				{
					if (other.Get(Keys.Get(i)) is JsonValue value)
					{
						if (!Items.Get(i).SameAs(value))
							return false;
					}
					else
					{
						return false;
					}
				}

				return true;
			}
		}
	}

	/// Compact JSON text.
	string ToJson()
	{
		switch (Kind)
		{
			case JsonKind.Null:
				return "null";
			case JsonKind.Bool:
				return Bool ? "true" : "false";
			case JsonKind.Number:
				return IsInteger ? Integer.ToString() : Number.ToString();
			case JsonKind.String:
				return JsonQuote(Text);
			case JsonKind.Array:
			{
				var builder = StringBuilder.Create();

				builder.Append("[");

				for (var i = 0; i < Items.Count(); i += 1)
				{
					if (i > 0)
						builder.Append(",");

					builder.Append(Items.Get(i).ToJson());
				}

				builder.Append("]");

				return builder.ToString();
			}
			default:
			{
				var builder = StringBuilder.Create();

				builder.Append("{");

				for (var i = 0; i < Items.Count(); i += 1)
				{
					if (i > 0)
						builder.Append(",");

					builder.Append(JsonQuote(Keys.Get(i)) + ":" + Items.Get(i).ToJson());
				}

				builder.Append("}");

				return builder.ToString();
			}
		}
	}
}

string JsonQuote(string text)
{
	var builder = StringBuilder.Create();

	builder.Append('"');

	for (var i = 0; i < text.Length; i += 1)
	{
		char c = text[i];

		if (c == '"')
			builder.Append("\\\"");
		else if (c == '\\')
			builder.Append("\\\\");
		else if (c == '\n')
			builder.Append("\\n");
		else if (c == '\t')
			builder.Append("\\t");
		else if (c == '\r')
			builder.Append("\\r");
		else if ((int)c < 0x20)
			builder.Append("\\u" + Hex((int)c, 4).ToLower());
		else
			builder.Append(c);
	}

	builder.Append('"');

	return builder.ToString();
}

Error<JsonValue> ParseJson(string text)
{
	var reader = JsonReader { Text = text, Position = 0 };
	var value = try reader.ReadValue();

	reader.SkipWhitespace();

	if (reader.Position < text.Length)
		return error("JSON: unexpected text at offset " + reader.Position + ".", (int)ErrorKind.InvalidData);

	return value;
}

struct JsonReader
{
	string Text;
	int Position;

	void SkipWhitespace()
	{
		while (Position < Text.Length && Char.IsWhiteSpace(Text[Position]))
			Position += 1;
	}

	Error<JsonValue> ReadValue()
	{
		SkipWhitespace();

		if (Position >= Text.Length)
			return error("JSON: unexpected end.", (int)ErrorKind.InvalidData);

		char c = Text[Position];

		if (c == '{')
			return ReadObject();

		if (c == '[')
			return ReadArray();

		if (c == '"')
			return JsonValue.OfString(try ReadString());

		if (Text.Substring(Position).StartsWith("true"))
		{
			Position += 4;

			return JsonValue.OfBool(true);
		}

		if (Text.Substring(Position).StartsWith("false"))
		{
			Position += 5;

			return JsonValue.OfBool(false);
		}

		if (Text.Substring(Position).StartsWith("null"))
		{
			Position += 4;

			return JsonValue.Null();
		}

		return ReadNumber();
	}

	Error<JsonValue> ReadNumber()
	{
		int start = Position;
		bool integer = true;

		if (Position < Text.Length && Text[Position] == '-')
			Position += 1;

		while (Position < Text.Length)
		{
			char c = Text[Position];

			if (Char.IsDigit(c))
			{
				Position += 1;
			}
			else if (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-')
			{
				integer = false;
				Position += 1;
			}
			else
			{
				break;
			}
		}

		string number = Text.Substring(start, Position - start);

		if (number.Length == 0)
			return error("JSON: unexpected character at offset " + start + ".", (int)ErrorKind.InvalidData);

		if (integer)
		{
			if (number.ParseInt64() is int64 value)
				return JsonValue.OfInteger(value);
		}

		if (number.ParseDouble() is double real)
			return JsonValue.OfNumber(real);

		return error("JSON: bad number '" + number + "'.", (int)ErrorKind.InvalidData);
	}

	Error<string> ReadString()
	{
		var builder = StringBuilder.Create();

		Position += 1;

		while (Position < Text.Length)
		{
			char c = Text[Position];

			if (c == '"')
			{
				Position += 1;

				return builder.ToString();
			}

			if (c == '\\')
			{
				if (Position + 1 >= Text.Length)
					break;

				char escaped = Text[Position + 1];

				Position += 2;

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
					case 'b':
						builder.Append((char)8);
						break;
					case 'f':
						builder.Append((char)12);
						break;
					case 'u':
					{
						if (Position + 4 > Text.Length)
							return error("JSON: bad escape sequence.", (int)ErrorKind.InvalidData);

						if (TryParseHex(Text.Substring(Position, 4)) is uint64 code)
							builder.Append(CodePointText((int)code));
						else
							return error("JSON: bad escape sequence.", (int)ErrorKind.InvalidData);

						Position += 4;
						break;
					}
					default:
						builder.Append(escaped);
						break;
				}

				continue;
			}

			builder.Append(c);
			Position += 1;
		}

		return error("JSON: unterminated string.", (int)ErrorKind.InvalidData);
	}

	Error<JsonValue> ReadArray()
	{
		var array = JsonValue.NewArray();

		Position += 1;
		SkipWhitespace();

		if (Position < Text.Length && Text[Position] == ']')
		{
			Position += 1;

			return array;
		}

		while (true)
		{
			array.Add(try ReadValue());
			SkipWhitespace();

			if (Position < Text.Length && Text[Position] == ',')
			{
				Position += 1;
				continue;
			}

			if (Position < Text.Length && Text[Position] == ']')
			{
				Position += 1;

				return array;
			}

			return error("JSON: expected ',' or ']' at offset " + Position + ".", (int)ErrorKind.InvalidData);
		}

		return array;
	}

	Error<JsonValue> ReadObject()
	{
		var result = JsonValue.NewObject();

		Position += 1;
		SkipWhitespace();

		if (Position < Text.Length && Text[Position] == '}')
		{
			Position += 1;

			return result;
		}

		while (true)
		{
			SkipWhitespace();

			if (Position >= Text.Length || Text[Position] != '"')
				return error("JSON: expected a key at offset " + Position + ".", (int)ErrorKind.InvalidData);

			string key = try ReadString();

			SkipWhitespace();

			if (Position >= Text.Length || Text[Position] != ':')
				return error("JSON: expected ':' at offset " + Position + ".", (int)ErrorKind.InvalidData);

			Position += 1;
			result.Set(key, try ReadValue());
			SkipWhitespace();

			if (Position < Text.Length && Text[Position] == ',')
			{
				Position += 1;
				continue;
			}

			if (Position < Text.Length && Text[Position] == '}')
			{
				Position += 1;

				return result;
			}

			return error("JSON: expected ',' or '}' at offset " + Position + ".", (int)ErrorKind.InvalidData);
		}

		return result;
	}
}
