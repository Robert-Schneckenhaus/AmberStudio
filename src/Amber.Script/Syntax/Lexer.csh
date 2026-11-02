namespace Amber.Script.Syntax;

using System;
using Amber.Base;

enum TokenKind : int32
{
	Identifier,
	Integer,
	String,
	/// HH:MM, the value is the number of minutes since midnight.
	Time,
	/// A number with a unit suffix (30t, 2s, 2min, 6h); the unit is in the token text.
	Duration,
	/// Punctuation or operator; the text holds the symbol.
	Symbol,
	EndOfFile
}

struct Token
{
	TokenKind Kind;
	string Text;
	int64 Value;
	SourceLocation Location;

	bool IsSymbol(string text)
	{
		return Kind == TokenKind.Symbol && Text == text;
	}

	bool IsKeyword(string text)
	{
		return Kind == TokenKind.Identifier && Text == text;
	}

	/// C#: ToString().
	string Describe()
	{
		return Kind == TokenKind.EndOfFile ? "end of file" : "'" + Text + "'";
	}
}

const ReadOnlySlice<string> TwoCharSymbols = ["->", "==", "!=", "<=", ">="];

const string SingleCharSymbols = "{}();,.:+-=<>";

/// Splits AmberScript source (spec section 7.1) into tokens. A syntax error (E100) ends the tokenizing: Tokenize returns an
/// error and Failure holds the diagnostic.
struct Lexer
{
	string _source;
	string _file;
	int _position;
	int _line;
	int _column;
	Diagnostic Failure;

	static Lexer Create(string source, string file)
	{
		return Lexer { _source = source, _file = file, _position = 0, _line = 1, _column = 1 };
	}

	Error<List<Token>> Tokenize()
	{
		var tokens = List<Token>.Create();

		while (true)
		{
			try SkipWhitespaceAndComments();

			if (_position >= _source.Length)
			{
				tokens.Add(Token { Kind = TokenKind.EndOfFile, Text = "", Value = 0, Location = Here() });

				return tokens;
			}

			tokens.Add(try ReadToken());
		}

		return tokens;
	}

	SourceLocation Here()
	{
		return SourceLocation.At(_file, _line, _column);
	}

	char Current()
	{
		return _position < _source.Length ? _source[_position] : (char)0;
	}

	char Peek(int offset)
	{
		return _position + offset < _source.Length ? _source[_position + offset] : (char)0;
	}

	void Advance()
	{
		if (Current() == '\n')
		{
			_line += 1;
			_column = 1;
		}
		else if (!IsContinuationByte(Current()))
		{
			// columns count characters, not the bytes of their UTF-8 encoding
			_column += 1;
		}

		_position += 1;
	}

	/// Records the syntax error (E100) and returns its message for error(...).
	string Fail(string message, SourceLocation location)
	{
		Failure = Diagnostic { Code = "E100", Severity = Severity.Error, Message = message, Location = location };

		return message;
	}

	Error<void> SkipWhitespaceAndComments()
	{
		while (_position < _source.Length)
		{
			char c = Current();

			if (Char.IsWhiteSpace(c))
			{
				Advance();
			}
			else if (c == '/' && Peek(1) == '/')
			{
				while (_position < _source.Length && Current() != '\n')
					Advance();
			}
			else if (c == '/' && Peek(1) == '*')
			{
				var start = Here();

				Advance();
				Advance();

				while (!(Current() == '*' && Peek(1) == '/'))
				{
					if (_position >= _source.Length)
						return error(Fail("Unterminated block comment.", start), (int)ErrorKind.Syntax);

					Advance();
				}

				Advance();
				Advance();
			}
			else
			{
				break;
			}
		}

		return;
	}

	Error<Token> ReadToken()
	{
		var location = Here();
		char c = Current();

		if (Char.IsLetter(c) || c == '_')
		{
			int start = _position;

			while (Char.IsLetterOrDigit(Current()) || Current() == '_')
				Advance();

			return Token { Kind = TokenKind.Identifier, Text = _source.Substring(start, _position - start), Value = 0, Location = location };
		}

		if (Char.IsDigit(c))
			return ReadNumber(location);

		if (c == '"')
			return ReadString(location);

		foreach (var symbol in TwoCharSymbols)
		{
			if (c == symbol[0] && Peek(1) == symbol[1])
			{
				Advance();
				Advance();

				return Token { Kind = TokenKind.Symbol, Text = symbol, Value = 0, Location = location };
			}
		}

		if (SingleCharSymbols.Contains(c))
		{
			Advance();

			return Token { Kind = TokenKind.Symbol, Text = _source.Substring(_position - 1, 1), Value = 0, Location = location };
		}

		var point = DecodeUtf8(_source, _position);

		return error(Fail("Unexpected character '" + _source.Substring(_position, point.Length) + "'.", location), (int)ErrorKind.Syntax);
	}

	Error<Token> ReadNumber(SourceLocation location)
	{
		int start = _position;

		if (Current() == '0' && (Peek(1) == 'x' || Peek(1) == 'X'))
		{
			Advance();
			Advance();

			int digitsStart = _position;

			while (Char.IsHexDigit(Current()))
				Advance();

			if (_position == digitsStart)
				return error(Fail("Hexadecimal number without digits.", location), (int)ErrorKind.Syntax);

			var hex = TryParseHex(_source.Substring(digitsStart, _position - digitsStart));

			if (hex == null)
				return error(Fail("Number '" + _source.Substring(start, _position - start) + "' is too large.", location), (int)ErrorKind.Syntax);

			uint64 hexValue = 0;

			if (hex is uint64 parsed)
				hexValue = parsed;

			return Token { Kind = TokenKind.Integer, Text = _source.Substring(start, _position - start), Value = (int64)hexValue, Location = location };
		}

		while (Char.IsDigit(Current()))
			Advance();

		int64 value = try ParseNumber(_source.Substring(start, _position - start), location);

		// time of day, e.g. 06:00
		if (Current() == ':' && Char.IsDigit(Peek(1)))
		{
			Advance();

			int minutesStart = _position;

			while (Char.IsDigit(Current()))
				Advance();

			int64 minutes = try ParseNumber(_source.Substring(minutesStart, _position - minutesStart), location);

			if (value > 23 || minutes > 59)
				return error(Fail("Invalid time of day '" + _source.Substring(start, _position - start) + "'.", location), (int)ErrorKind.Syntax);

			return Token { Kind = TokenKind.Time, Text = _source.Substring(start, _position - start), Value = value * 60 + minutes, Location = location };
		}

		// duration, e.g. 30t, 2s, 2min, 6h
		if (Char.IsLetter(Current()))
		{
			int unitStart = _position;

			while (Char.IsLetter(Current()))
				Advance();

			string unit = _source.Substring(unitStart, _position - unitStart);

			if (unit != "t" && unit != "s" && unit != "min" && unit != "h")
				return error(Fail("Unknown number suffix '" + unit + "'.", location), (int)ErrorKind.Syntax);

			return Token { Kind = TokenKind.Duration, Text = unit, Value = value, Location = location };
		}

		return Token { Kind = TokenKind.Integer, Text = _source.Substring(start, _position - start), Value = value, Location = location };
	}

	Error<int64> ParseNumber(string digits, SourceLocation location)
	{
		if (digits.ParseInt64() is int64 value)
			return value;

		return error(Fail("Number '" + digits + "' is too large.", location), (int)ErrorKind.Syntax);
	}

	Error<Token> ReadString(SourceLocation location)
	{
		var builder = StringBuilder.Create();

		Advance();

		while (Current() != '"')
		{
			if (_position >= _source.Length || Current() == '\n')
				return error(Fail("Unterminated string.", location), (int)ErrorKind.Syntax);

			if (Current() == '\\')
			{
				Advance();

				switch (Current())
				{
					case 'n':
						builder.Append('\n');
						break;
					case 't':
						builder.Append('\t');
						break;
					case '"':
						builder.Append('"');
						break;
					case '\\':
						builder.Append('\\');
						break;
					default:
					{
						var point = DecodeUtf8(_source, _position);

						return error(Fail("Unknown escape sequence '\\" + _source.Substring(_position, point.Length) + "'.", Here()), (int)ErrorKind.Syntax);
					}
				}
			}
			else
			{
				builder.Append(Current());
			}

			Advance();
		}

		Advance();

		return Token { Kind = TokenKind.String, Text = builder.ToString(), Value = 0, Location = location };
	}
}
