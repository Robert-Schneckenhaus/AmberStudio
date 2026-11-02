namespace Amber.Tests;

/// Every test of every file, in the order of the C# test classes.
TestList AllTests()
{
	var tests = TestList.Create();

	RegisterLexerParserTests(ref tests);
	RegisterCompilerTests(ref tests);
	RegisterGrammarTests(ref tests);
	RegisterRuntimeTests(ref tests);
	RegisterReuseTests(ref tests);
	RegisterScreenSchemaTests(ref tests);
	RegisterScenarioTests(ref tests);
	RegisterScreenChunkTests(ref tests);
	RegisterUiThemeTests(ref tests);
	RegisterPaletteTests(ref tests);
	RegisterPackTests(ref tests);
	RegisterSaveTests(ref tests);
	RegisterCookTests(ref tests);
	RegisterCRuntimeTests(ref tests);

	return tests;
}
