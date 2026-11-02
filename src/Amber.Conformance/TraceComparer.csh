// Compares two traces line by line (two implementations are conformant if the traces are identical).

namespace Amber.Conformance.TraceComparer;

using System;
using Amber.Base;

/// Returns null if the traces are identical, else a description of the first difference.
string Compare(string[] expected, string[] actual)
{
	for (var i = 0; i < Math.Max(expected.Length, actual.Length); i += 1)
	{
		string left = i < expected.Length ? expected[i] : null;
		string right = i < actual.Length ? actual[i] : null;

		if (left != right)
			return "line " + (i + 1) + ": expected " + (left == null ? "<end of trace>" : "'" + left + "'") + ", got " + (right == null ? "<end of trace>" : "'" + right + "'");
	}

	return null;
}

/// Splits the text of a trace file into lines (line endings do not matter).
string[] Lines(string text)
{
	return NonEmptyLines(text);
}
