namespace Amber.Script;

using System;

/// Position in a source file (1-based line and column).
struct SourceLocation
{
	string File;
	int Line;
	int Column;

	static SourceLocation None()
	{
		return SourceLocation { File = "", Line = 0, Column = 0 };
	}

	static SourceLocation At(string file, int line, int column)
	{
		return SourceLocation { File = file, Line = line, Column = column };
	}

	/// C#: ToString().
	string Text()
	{
		if (Line == 0)
			return File == null ? "" : File;

		return File + "(" + Line + "," + Column + ")";
	}
}

enum Severity : int32
{
	Warning,
	Error
}

/// A compiler message. Codes follow spec section 13 (E001, W001 ...).
struct Diagnostic
{
	string Code;
	Severity Severity;
	string Message;
	SourceLocation Location;

	/// C#: ToString().
	string Text()
	{
		return Location.Text() + ": " + (Severity == Amber.Script.Severity.Error ? "error" : "warning") + " " + Code + ": " + Message;
	}
}

/// Collects diagnostics during compilation (a handle to shared storage).
struct DiagnosticBag
{
	List<Diagnostic> Items;

	static DiagnosticBag Create()
	{
		return DiagnosticBag { Items = List<Diagnostic>.Create() };
	}

	bool HasErrors()
	{
		foreach (var item in Items)
		{
			if (item.Severity == Severity.Error)
				return true;
		}

		return false;
	}

	void Error(string code, string message, SourceLocation location)
	{
		Items.Add(Diagnostic { Code = code, Severity = Severity.Error, Message = message, Location = location });
	}

	void Warning(string code, string message, SourceLocation location)
	{
		Items.Add(Diagnostic { Code = code, Severity = Severity.Warning, Message = message, Location = location });
	}

	void Add(Diagnostic diagnostic)
	{
		Items.Add(diagnostic);
	}

	int Count()
	{
		return Items.Count();
	}

	int ErrorCount()
	{
		int count = 0;

		foreach (var item in Items)
		{
			if (item.Severity == Severity.Error)
				count += 1;
		}

		return count;
	}

	int WarningCount()
	{
		return Items.Count() - ErrorCount();
	}

	/// True if a diagnostic with the code (and severity) exists.
	bool Contains(string code, Severity severity)
	{
		foreach (var item in Items)
		{
			if (item.Code == code && item.Severity == severity)
				return true;
		}

		return false;
	}

	bool ContainsCode(string code)
	{
		foreach (var item in Items)
		{
			if (item.Code == code)
				return true;
		}

		return false;
	}
}
