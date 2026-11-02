namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Script.Common;

// The VS Code extension (tools/vscode-amberscript) highlights the names of the opcode tables. These tests fail when a name
// or a symbol prefix of the tables is missing in the TextMate grammar.

void RegisterGrammarTests(ref TestList tests)
{
	tests.Fact("Grammar.EveryActionIsInTheGrammar", EveryActionIsInTheGrammar);
	tests.Fact("Grammar.EveryConditionIsInTheGrammar", EveryConditionIsInTheGrammar);
	tests.Fact("Grammar.EveryTriggerIsInTheGrammar", EveryTriggerIsInTheGrammar);
	tests.Fact("Grammar.EverySymbolPrefixIsInTheGrammar", EverySymbolPrefixIsInTheGrammar);
}

Error<string> Grammar()
{
	return ReadRootText("tools/vscode-amberscript/syntaxes/amberscript.tmLanguage.json");
}

bool IsWordCharacter(char c)
{
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_';
}

/// The name occurs as a whole word (C#: the regex (?<![A-Za-z0-9_])name(?![A-Za-z0-9_])).
bool ContainsWord(string grammar, string name)
{
	int start = 0;

	while (true)
	{
		int index = grammar.IndexOf(name, start);

		if (index < 0)
			return false;

		int end = index + name.Length;

		if ((index == 0 || !IsWordCharacter(grammar[index - 1])) && (end >= grammar.Length || !IsWordCharacter(grammar[end])))
			return true;

		start = index + 1;
	}
}

Error<void> MissingNames(List<string> missing)
{
	return Assert.True(missing.Count() == 0, "missing in the grammar: " + JoinList(", ", missing));
}

Error<void> EveryActionIsInTheGrammar()
{
	string grammar = try Grammar();
	var missing = List<string>.Create();

	foreach (var info in ActionTable.All)
	{
		if (!ContainsWord(grammar, info.Name))
			missing.Add(info.Name);
	}

	return MissingNames(missing);
}

Error<void> EveryConditionIsInTheGrammar()
{
	string grammar = try Grammar();
	var missing = List<string>.Create();

	foreach (var info in ConditionTable.All)
	{
		if (!ContainsWord(grammar, info.Name))
			missing.Add(info.Name);
	}

	return MissingNames(missing);
}

Error<void> EveryTriggerIsInTheGrammar()
{
	string grammar = try Grammar();
	var missing = List<string>.Create();

	foreach (var info in TriggerTable.All)
	{
		if (!ContainsWord(grammar, info.Name))
			missing.Add(info.Name);
	}

	return MissingNames(missing);
}

Error<void> EverySymbolPrefixIsInTheGrammar()
{
	string grammar = try Grammar();
	var missing = List<string>.Create();

	foreach (var entry in SymbolKindNames)
	{
		var kind = (SymbolKind)entry.Value;

		if (kind == SymbolKind.None || kind == SymbolKind.Routine || kind == SymbolKind.CustomEvent || kind == SymbolKind.Node)
			continue;

		string prefix = SymbolKinds.Prefix(kind);

		if (!ContainsWord(grammar, prefix))
			missing.Add(prefix);
	}

	return MissingNames(missing);
}
