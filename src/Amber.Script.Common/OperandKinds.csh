namespace Amber.Script.Common;

using System;

/// Kinds of operands of conditions, actions and trigger parameters. They drive parsing, encoding and dumping so that the
/// opcode tables are the single source of truth.
enum OperandKind : uint8
{
	/// 16 bit unsigned value.
	Word,
	/// 16 bit signed value.
	Int16,
	/// 32 bit value written as one number in source, stored as two words (high, low).
	Int32,
	FlagSlot,
	VarSlot,
	Var32Slot,
	Comparison,
	Target,
	Direction,
	Entity,
	/// Two words (x, y). "here" is only allowed if the operand spec says so.
	Pos,
	TileRef,
	/// A prefixed symbol from the tables (T.text, I.item ...); see OperandSpec.Symbol.
	Symbol,
	/// Node of the screen block that is compiled.
	Node,
	Modifier,
	MoveSource,
	/// ID of a custom event (raise/custom).
	Custom,
	FlagMode
}

/// Kinds of table symbols. The prefix is the part before the dot in source (T.name).
enum SymbolKind : uint8
{
	None,
	Text,
	Keyword,
	Item,
	WordList,
	MonsterGroup,
	Map,
	Character,
	Screen,
	Spell,
	Entity,
	Class,
	Race,
	Language,
	Attribute,
	Picture,
	Music,
	Sound,
	Tile,
	Transport,
	Trap,
	Place,
	Effect,
	Delta,
	/// Content of a chest (screen chest, spec section 8).
	Chest,
	/// Native functions and data sources of the host (native action, spec 9.4).
	Native,
	/// Routine names are scoped to a map and have no prefix.
	Routine,
	/// Custom event names are global and have no prefix.
	CustomEvent,
	/// Screen node names are scoped to a screen and have no prefix.
	Node,
	/// Palettes (set_palette, fade_palette; Ziele Z4).
	Palette
}

EnumEntry[] SymbolKindNames = new EnumEntry[]
{
	En("None", 0), En("Text", 1), En("Keyword", 2), En("Item", 3), En("WordList", 4), En("MonsterGroup", 5), En("Map", 6),
	En("Character", 7), En("Screen", 8), En("Spell", 9), En("Entity", 10), En("Class", 11), En("Race", 12),
	En("Language", 13), En("Attribute", 14), En("Picture", 15), En("Music", 16), En("Sound", 17), En("Tile", 18),
	En("Transport", 19), En("Trap", 20), En("Place", 21), En("Effect", 22), En("Delta", 23), En("Chest", 24),
	En("Native", 25), En("Routine", 26), En("CustomEvent", 27), En("Node", 28), En("Palette", 29)
};

string SymbolKindName(SymbolKind value)
{
	return EnumName(SymbolKindNames, (int)value);
}

/// Describes a single operand of an opcode.
struct OperandSpec
{
	string Name;
	OperandKind Kind;
	SymbolKind Symbol;
	bool AllowHere;

	/// Number of 16 bit words this operand occupies.
	int Words()
	{
		return Kind == OperandKind.Int32 || Kind == OperandKind.Pos ? 2 : 1;
	}
}

/// Describes a condition or an action opcode. Blocking: the instruction can suspend the running thread. CountOperand: index
/// of the fixed operand which holds the number of trailing variadic words, or -1.
struct OpInfo
{
	uint8 Op;
	string Name;
	OperandSpec[] Operands;
	bool Blocking;
	int CountOperand;

	bool IsVariadic()
	{
		return CountOperand >= 0;
	}

	int FixedWords()
	{
		int sum = 0;

		for (var i = 0; i < Operands.Length; i += 1)
			sum += Operands[i].Words();

		return sum;
	}
}

/// Trigger definition: parameters and allowed scopes (spec section 3). NodeFirst: the first source argument is a node
/// (scope Node) and the parameters start after it.
struct TriggerInfo
{
	TriggerType Type;
	string Name;
	TriggerScopes Scopes;
	Optional<OperandSpec> P1;
	Optional<OperandSpec> P2;
	bool NodeFirst;
}
