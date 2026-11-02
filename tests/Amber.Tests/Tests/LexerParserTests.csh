namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Syntax;

void RegisterLexerParserTests(ref TestList tests)
{
	tests.Fact("LexerParser.LexerReadsNumbersTimesAndDurations", LexerReadsNumbersTimesAndDurations);
	tests.Fact("LexerParser.LexerSkipsComments", LexerSkipsComments);

	foreach (var file in AmsFiles())
		tests.Theory("LexerParser.ExamplesParseWithoutErrors", ExamplesParseWithoutErrors, file);

	tests.Fact("LexerParser.ParsesRuleWithConditionsAndThen", ParsesRuleWithConditionsAndThen);
	tests.Fact("LexerParser.BareOrNextToAndIsReported", BareOrNextToAndIsReported);
	tests.Fact("LexerParser.ParenthesizedOrIsAccepted", ParenthesizedOrIsAccepted);
	tests.Fact("LexerParser.SyntaxErrorFails", SyntaxErrorFails);
}

Error<void> LexerReadsNumbersTimesAndDurations()
{
	var tokens = try Lexer.Create("42 0x1B 06:30 30t 2s 2min 6h", "test").Tokenize();

	try Assert.Equal((int)TokenKind.Integer, (int)tokens.Get(0).Kind);
	try Assert.Equal(42, tokens.Get(0).Value);
	try Assert.Equal(0x1B, tokens.Get(1).Value);
	try Assert.Equal((int)TokenKind.Time, (int)tokens.Get(2).Kind);
	try Assert.Equal(6 * 60 + 30, tokens.Get(2).Value);
	try Assert.Equal((int)TokenKind.Duration, (int)tokens.Get(3).Kind);
	try Assert.Equal("t", tokens.Get(3).Text);
	try Assert.Equal("min", tokens.Get(5).Text);
	try Assert.Equal("h", tokens.Get(6).Text);
	try Assert.Equal((int)TokenKind.EndOfFile, (int)tokens.Get(tokens.Count() - 1).Kind);

	return;
}

Error<void> LexerSkipsComments()
{
	var tokens = try Lexer.Create("a // line\n/* block\n */ b", "test").Tokenize();

	try Assert.Equal(3, tokens.Count());
	try Assert.Equal("a", tokens.Get(0).Text);
	try Assert.Equal("b", tokens.Get(1).Text);
	try Assert.Equal(3, tokens.Get(1).Location.Line);

	return;
}

Error<void> ExamplesParseWithoutErrors(string[] arguments)
{
	string file = arguments[0];
	var diagnostics = DiagnosticBag.Create();
	var parsed = Parser.Parse(try ReadRootText(file), file, diagnostics);

	try Assert.Empty(diagnostics.Items);
	try Assert.True(parsed.Program is ProgramNode, "the program is missing");

	if (parsed.Program is ProgramNode program)
		try Assert.NotEmpty(program.Items);

	return;
}

/// Parses a program which must not fail with a syntax error.
Error<ProgramNode> ParseProgram(string source, DiagnosticBag diagnostics)
{
	var parsed = Parser.Parse(source, "test", diagnostics);

	if (parsed.Program is ProgramNode program)
		return program;

	if (parsed.SyntaxError is Diagnostic syntaxError)
		return error("unexpected syntax error: " + syntaxError.Text(), -1);

	return error("the parser returned nothing", -1);
}

Error<void> ParsesRuleWithConditionsAndThen()
{
	string source = "group schrein first {\n"
		+ "\twhen not flag(schrein_benutzt) and hour_in(20, 6)\n"
		+ "\tdo { say(T.geist); set_flag(schrein_benutzt); battle(G.geist, 0); } then danach;\n"
		+ "\telse do { }\n"
		+ "}";
	var diagnostics = DiagnosticBag.Create();
	var item = try Assert.Single((try ParseProgram(source, diagnostics)).Items);

	try Assert.Equal((int)NodeKind.Group, (int)item.Kind);

	var group = item.Group;

	try Assert.True(group.Mode is GroupMode mode && mode == GroupMode.First, "the mode is 'first'");
	try Assert.Equal(2, group.Rules.Length);

	var rule = group.Rules[0];

	try Assert.Equal("danach", rule.Then);
	try Assert.Equal(3, rule.Actions.Length);
	try Assert.True(rule.Condition is ConditionNode, "the rule has a condition");

	if (rule.Condition is ConditionNode condition)
	{
		try Assert.Equal(2, condition.Clauses.Length);
		try Assert.True(condition.Clauses[0].Literals[0].Not);
	}

	try Assert.True(group.Rules[1].IsElse);
	try Assert.Empty(diagnostics.Items);

	return;
}

Error<void> BareOrNextToAndIsReported()
{
	var diagnostics = DiagnosticBag.Create();

	Parser.Parse("group g { when flag(a) or flag(b) and flag(c) do { } }", "test", diagnostics);

	try Assert.True(diagnostics.ContainsCode("E008"), "E008 is reported");

	return;
}

Error<void> ParenthesizedOrIsAccepted()
{
	var diagnostics = DiagnosticBag.Create();

	Parser.Parse("group g { when (flag(a) or flag(b)) and flag(c) do { } }", "test", diagnostics);

	try Assert.Empty(diagnostics.Items);

	return;
}

/// C#: SyntaxErrorThrows (a SyntaxException with the diagnostic).
Error<void> SyntaxErrorFails()
{
	var parsed = Parser.Parse("group g { when flag(a) do { say(T.x) } }", "test", DiagnosticBag.Create());

	try Assert.True(parsed.SyntaxError is Diagnostic, "a syntax error is reported");

	if (parsed.SyntaxError is Diagnostic syntaxError)
		try Assert.Equal("E100", syntaxError.Code);

	return;
}
