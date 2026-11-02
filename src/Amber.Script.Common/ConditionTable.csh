// Condition opcode table (spec section 4).

namespace Amber.Script.Common.ConditionTable;

using System;

OpInfo[] All = new OpInfo[]
{
	O.Op((uint8)ConditionOp.Flag, "flag", O.Ops(O.Flag()), false, -1),
	O.Op((uint8)ConditionOp.Var, "var", O.Ops(O.Var(), O.Cmp(), O.Int16("value")), false, -1),
	O.Op((uint8)ConditionOp.Var32, "var32", O.Ops(O.Var32(), O.Cmp(), O.Int32("value")), false, -1),
	O.Op((uint8)ConditionOp.VarVar, "varvar", O.Ops(O.Var("a"), O.Cmp(), O.Var("b")), false, -1),
	O.Op((uint8)ConditionOp.Result, "result", O.Ops(O.Cmp(), O.Int16("value")), false, -1),
	O.Op((uint8)ConditionOp.Arg, "arg", O.Ops(O.Cmp(), O.Int32("value")), false, -1),
	O.Op((uint8)ConditionOp.Chance, "chance", O.Ops(O.Word("percent")), false, -1),
	O.Op((uint8)ConditionOp.WordKnown, "word_known", O.Ops(O.Sym(SymbolKind.Keyword, "word")), false, -1),
	O.Op((uint8)ConditionOp.HasItem, "has_item", O.Ops(O.Sym(SymbolKind.Item, "item"), O.Word("count")), false, -1),
	O.Op((uint8)ConditionOp.HasMember, "has_member", O.Ops(O.Sym(SymbolKind.Character, "character")), false, -1),
	O.Op((uint8)ConditionOp.PartyClass, "party_class", O.Ops(O.Sym(SymbolKind.Class, "class")), false, -1),
	O.Op((uint8)ConditionOp.PartyRace, "party_race", O.Ops(O.Sym(SymbolKind.Race, "race")), false, -1),
	O.Op((uint8)ConditionOp.PartyLanguage, "party_lang", O.Ops(O.Sym(SymbolKind.Language, "language")), false, -1),
	O.Op((uint8)ConditionOp.PartySize, "party_size", O.Ops(O.Cmp(), O.Int16("value")), false, -1),
	O.Op((uint8)ConditionOp.Gold, "gold", O.Ops(O.Cmp(), O.Int32("value")), false, -1),
	O.Op((uint8)ConditionOp.Attribute, "attr", O.Ops(O.Target(), O.Sym(SymbolKind.Attribute, "attribute"), O.Cmp(), O.Int16("value")), false, -1),
	O.Op((uint8)ConditionOp.Probe, "probe", O.Ops(O.Target(), O.Sym(SymbolKind.Attribute, "attribute")), false, -1),
	O.Op((uint8)ConditionOp.HourIn, "hour_in", O.Ops(O.Word("from"), O.Word("to")), false, -1),
	O.Op((uint8)ConditionOp.DayIn, "day_in", O.Ops(O.Word("from"), O.Word("to")), false, -1),
	O.Op((uint8)ConditionOp.Season, "season", O.Ops(O.Word("season")), false, -1),
	O.Op((uint8)ConditionOp.InMap, "in_map", O.Ops(O.Sym(SymbolKind.Map, "map")), false, -1),
	O.Op((uint8)ConditionOp.Transport, "transport", O.Ops(O.Sym(SymbolKind.Transport, "transport")), false, -1),
	O.Op((uint8)ConditionOp.World, "world", O.Ops(O.Word("world")), false, -1),
	O.Op((uint8)ConditionOp.SpellActive, "spell_active", O.Ops(O.Sym(SymbolKind.Spell, "spell")), false, -1),
	O.Op((uint8)ConditionOp.TileIs, "tile_is", O.Ops(O.Word("layer"), O.Pos(true), O.Sym(SymbolKind.Tile, "tile")), false, -1),
	O.Op((uint8)ConditionOp.ScreenOpen, "screen_open", O.Ops(O.Sym(SymbolKind.Screen, "screen")), false, -1),
	O.Op((uint8)ConditionOp.MemberCondition, "member_condition", O.Ops(O.Target(), O.Word("condition")), false, -1),
	O.Op((uint8)ConditionOp.Near, "near", O.Ops(O.Entity(), O.Word("range")), false, -1),
	O.Op((uint8)ConditionOp.Facing, "facing", O.Ops(O.Dir()), false, -1),
	O.Op((uint8)ConditionOp.InputMatches, "input_matches", O.Ops(O.Var("words")), false, -1)
};

Dictionary<string, int> ByNameIndex = BuildNameIndex();

Dictionary<string, int> BuildNameIndex()
{
	var index = Dictionary<string, int>.Create();

	for (var i = 0; i < All.Length; i += 1)
		index.Set(All[i].Name, i);

	return index;
}

/// The opcode with this source name, or no value.
Optional<OpInfo> ByName(string name)
{
	if (ByNameIndex.TryGet(name) is int index)
		return All[index];

	return null;
}

/// The opcode with this number, or no value.
Optional<OpInfo> ByOp(int op)
{
	for (var i = 0; i < All.Length; i += 1)
	{
		if ((int)All[i].Op == op)
			return All[i];
	}

	return null;
}
