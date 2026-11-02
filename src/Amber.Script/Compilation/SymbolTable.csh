namespace Amber.Script.Compilation;

using System;
using Amber.Base;
using Amber.Script.Common;

/// A source file for the compiler.
struct SourceFile
{
	string Path;
	string Text;

	static SourceFile Create(string path, string text)
	{
		return SourceFile { Path = path, Text = text };
	}
}

/// The key of a table symbol (C#: the tuple (SymbolKind Kind, string Name)).
struct SymbolKey : IEquatable<SymbolKey>, IHashable
{
	SymbolKind Kind;
	string Name;

	bool Equals(SymbolKey other)
	{
		return Kind == other.Kind && Name == other.Name;
	}

	int GetHashCode()
	{
		return unchecked(Name.GetHashCode() * 31 + (int)Kind);
	}
}

/// IDs of the prefixed table symbols (T.text, I.item ...). In lenient mode unknown names get the next free ID so that
/// sources can be compiled before the tables exist; strict mode reports E001. A handle to shared storage.
struct SymbolTable
{
	Dictionary<SymbolKey, uint16> Ids;
	Dictionary<SymbolKind, int> _nextIds;
	bool Lenient;

	static SymbolTable Create(bool lenient)
	{
		return SymbolTable { Ids = Dictionary<SymbolKey, uint16>.Create(), _nextIds = Dictionary<SymbolKind, int>.Create(), Lenient = lenient };
	}

	void Define(SymbolKind kind, string name, uint16 id)
	{
		Ids.Set(SymbolKey { Kind = kind, Name = name }, id);
	}

	/// The ID of the symbol; unknown symbols get the next free ID in lenient mode, else no value.
	Optional<uint16> TryResolve(SymbolKind kind, string name)
	{
		var key = SymbolKey { Kind = kind, Name = name };

		if (Ids.TryGet(key) is uint16 id)
			return id;

		if (!Lenient)
			return null;

		int next = _nextIds.GetOrDefault(kind, 1);

		_nextIds.Set(kind, next + 1);
		Ids.Set(key, (uint16)next);

		return (uint16)next;
	}
}

/// Description of a screen as far as the script compiler needs it: the argument names (screen variables 0..n-1) and the
/// node names (node IDs in order).
struct ScreenSignature
{
	string[] Args;
	string[] Nodes;
}

/// The screen signatures the compiler can look up (C#: IScreenSignatureProvider). The zero value knows no screen.
struct ScreenSignatures
{
	Dictionary<string, ScreenSignature> _signatures;

	static ScreenSignatures Create()
	{
		return ScreenSignatures { _signatures = Dictionary<string, ScreenSignature>.Create() };
	}

	void Add(string screenName, ScreenSignature signature)
	{
		_signatures.Set(screenName, signature);
	}

	/// The signature of the screen or no value if it is unknown.
	Optional<ScreenSignature> Get(string screenName)
	{
		if (_signatures.Count() == 0)
			return null;

		return _signatures.TryGet(screenName);
	}
}

/// The options of a compilation. The zero value is the default: strict symbols, no screen signatures, a new symbol table,
/// deduplication on.
struct CompileOptions
{
	/// Assign IDs to unknown table symbols instead of reporting E001.
	bool LenientSymbols;
	ScreenSignatures Screens;
	Optional<SymbolTable> Symbols;
	/// Do not merge identical groups (spec section 7.6, stage 3). C#: Deduplicate = false.
	bool NoDeduplicate;
}

/// Result of compiling a set of source files.
struct CompilationResult
{
	DiagnosticBag Diagnostics;
	CompiledScope Global;
	List<CompiledScope> Maps;
	List<CompiledScope> Screens;
	SymbolTable Symbols;
	int DuplicateGroupsRemoved;
	/// Text of the state layout (spec section 10.1), one line per slot.
	string LayoutText;
	/// CRC-32 of the layout text; stored in the pack header and in savegames.
	uint32 LayoutHash;

	static CompilationResult Create(DiagnosticBag diagnostics, SymbolTable symbols)
	{
		return CompilationResult
		{
			Diagnostics = diagnostics,
			Global = CompiledScope.Create(0, ScopeKind.Global, "global"),
			Maps = List<CompiledScope>.Create(),
			Screens = List<CompiledScope>.Create(),
			Symbols = symbols,
			DuplicateGroupsRemoved = 0,
			LayoutText = "",
			LayoutHash = 0
		};
	}

	/// The global scope, then the maps, then the screens.
	List<CompiledScope> AllScopes()
	{
		var all = List<CompiledScope>.Create();

		all.Add(Global);

		foreach (var map in Maps)
			all.Add(map);

		foreach (var screen in Screens)
			all.Add(screen);

		return all;
	}

	bool HasErrors()
	{
		return Diagnostics.HasErrors();
	}

	/// The map with the name, or no value.
	Optional<CompiledScope> FindMap(string name)
	{
		foreach (var map in Maps)
		{
			if (map.Name == name)
				return map;
		}

		return null;
	}

	/// The screen with the name, or no value.
	Optional<CompiledScope> FindScreen(string name)
	{
		foreach (var screen in Screens)
		{
			if (screen.Name == name)
				return screen;
		}

		return null;
	}
}
