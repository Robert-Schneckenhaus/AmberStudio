namespace Amber.Script.Common.SymbolKinds;

using System;

struct PrefixEntry
{
	string Prefix;
	SymbolKind Kind;
}

PrefixEntry P(string prefix, SymbolKind kind)
{
	return PrefixEntry { Prefix = prefix, Kind = kind };
}

/// All prefixes of the source language with their kind (the C tables are generated from it), in this order.
PrefixEntry[] Prefixes = new PrefixEntry[]
{
	P("T", SymbolKind.Text),
	P("K", SymbolKind.Keyword),
	P("I", SymbolKind.Item),
	P("W", SymbolKind.WordList),
	P("G", SymbolKind.MonsterGroup),
	P("M", SymbolKind.Map),
	P("C", SymbolKind.Character),
	P("S", SymbolKind.Screen),
	P("SP", SymbolKind.Spell),
	P("E", SymbolKind.Entity),
	P("CL", SymbolKind.Class),
	P("RC", SymbolKind.Race),
	P("LG", SymbolKind.Language),
	P("AT", SymbolKind.Attribute),
	P("PIC", SymbolKind.Picture),
	P("MUS", SymbolKind.Music),
	P("SND", SymbolKind.Sound),
	P("TILE", SymbolKind.Tile),
	P("TR", SymbolKind.Transport),
	P("TRAP", SymbolKind.Trap),
	P("PLACE", SymbolKind.Place),
	P("FX", SymbolKind.Effect),
	P("DELTA", SymbolKind.Delta),
	P("CH", SymbolKind.Chest),
	P("N", SymbolKind.Native),
	P("PAL", SymbolKind.Palette)
};

/// The kind of a prefix (T, I, SP ...), or no value.
Optional<SymbolKind> FromPrefix(string prefix)
{
	for (var i = 0; i < Prefixes.Length; i += 1)
	{
		if (Prefixes[i].Prefix == prefix)
			return Prefixes[i].Kind;
	}

	return null;
}

string Prefix(SymbolKind kind)
{
	for (var i = 0; i < Prefixes.Length; i += 1)
	{
		if (Prefixes[i].Kind == kind)
			return Prefixes[i].Prefix;
	}

	return SymbolKindName(kind);
}
