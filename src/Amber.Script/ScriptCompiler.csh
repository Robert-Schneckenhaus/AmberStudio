// Entry point of the AmberScript compiler: parses source files, lowers them and encodes the chunks.

namespace Amber.Script.ScriptCompiler;

using System;
using Amber.Base;
using Amber.Script.Compilation;
using Amber.Script.Syntax;

CompilationResult Compile(SourceFile[] sources, CompileOptions options)
{
	var diagnostics = DiagnosticBag.Create();
	var symbols = SymbolTable.Create(options.LenientSymbols);

	if (options.Symbols is SymbolTable given)
		symbols = given;

	var result = CompilationResult.Create(diagnostics, symbols);
	var programs = List<ProgramNode>.Create();

	foreach (var source in sources)
	{
		var parsed = Parser.Parse(source.Text, source.Path, diagnostics);

		if (parsed.Program is ProgramNode program)
			programs.Add(program);

		if (parsed.SyntaxError is Diagnostic syntaxError)
			diagnostics.Add(syntaxError);
	}

	if (diagnostics.HasErrors())
		return result;

	return Compiler.Create(diagnostics, symbols, options, result).Run(ArrayOf(programs));
}

CompilationResult CompileText(string text, string path, CompileOptions options)
{
	return Compile(new SourceFile[] { SourceFile.Create(path, text) }, options);
}

CompilationResult CompileText(string text)
{
	return CompileText(text, "test.ams", new CompileOptions());
}
