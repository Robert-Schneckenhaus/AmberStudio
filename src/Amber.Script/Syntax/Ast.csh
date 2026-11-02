// The syntax tree. CShift has no classes, so the C# record hierarchy (ArgNode, AtomNode, SyntaxNode and their subclasses)
// becomes tagged structs: a Kind field says which of the C# classes a value is, the fields of the other kinds stay empty.
// Nodes that contain other nodes of the same kind hold them in arrays (a struct cannot contain itself directly).

namespace Amber.Script.Syntax;

using System;
using Amber.Script.Common;

// ---------------------------------------------------------------------------------------------------------------------
// Arguments
// ---------------------------------------------------------------------------------------------------------------------

enum ArgKind : int32
{
	/// An integer (C#: IntArg). Signed is set if it was written with an explicit minus sign.
	Int,
	/// A number with an explicit plus sign (+1): relative tile (C#: RelArg, the delta is in Value).
	Rel,
	/// A name (C#: IdentArg).
	Ident,
	/// A prefixed table symbol like T.name (C#: SymbolArg).
	Symbol,
	/// (x, y) (C#: PosArg, x is in Value).
	Pos,
	/// here (C#: HereArg).
	Here
}

struct ArgNode
{
	ArgKind Kind;
	SourceLocation Location;
	/// Int: the value, Rel: the delta, Pos: x.
	int64 Value;
	/// Pos: y.
	int64 Y;
	bool Signed;
	/// Ident and Symbol: the name.
	string Name;
	/// Symbol: the prefix (T, I ...).
	string Prefix;

	static ArgNode Int(SourceLocation location, int64 value, bool signed)
	{
		return ArgNode { Kind = ArgKind.Int, Location = location, Value = value, Signed = signed };
	}

	static ArgNode Rel(SourceLocation location, int64 delta)
	{
		return ArgNode { Kind = ArgKind.Rel, Location = location, Value = delta };
	}

	static ArgNode Ident(SourceLocation location, string name)
	{
		return ArgNode { Kind = ArgKind.Ident, Location = location, Name = name };
	}

	static ArgNode Symbol(SourceLocation location, string prefix, string name)
	{
		return ArgNode { Kind = ArgKind.Symbol, Location = location, Prefix = prefix, Name = name };
	}

	static ArgNode Pos(SourceLocation location, int64 x, int64 y)
	{
		return ArgNode { Kind = ArgKind.Pos, Location = location, Value = x, Y = y };
	}

	static ArgNode Here(SourceLocation location)
	{
		return ArgNode { Kind = ArgKind.Here, Location = location };
	}

	bool IsSymbolWithPrefix(string prefix)
	{
		return Kind == ArgKind.Symbol && Prefix == prefix;
	}
}

/// A call like name(arg, arg): used for actions, condition atoms, trigger heads and preset uses in fragments.
struct CallNode
{
	SourceLocation Location;
	string Name;
	ArgNode[] Args;

	static CallNode Create(SourceLocation location, string name, ArgNode[] args)
	{
		return CallNode { Location = location, Name = name, Args = args };
	}
}

// ---------------------------------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------------------------------

enum AtomKind : int32
{
	/// A condition call like flag(x) (C#: CallAtom).
	Call,
	/// An infix comparison like result == 1 or gold >= 500 (C#: CompareAtom).
	Compare
}

struct AtomNode
{
	AtomKind Kind;
	SourceLocation Location;
	CallNode Call;
	ArgNode Left;
	Comparison Comparison;
	ArgNode Right;
}

struct LiteralNode
{
	SourceLocation Location;
	bool Not;
	AtomNode Atom;
}

/// Literals connected by OR.
struct ClauseNode
{
	SourceLocation Location;
	LiteralNode[] Literals;
}

/// Clauses connected by AND (conjunctive normal form, spec section 4).
struct ConditionNode
{
	SourceLocation Location;
	ClauseNode[] Clauses;
}

// ---------------------------------------------------------------------------------------------------------------------
// Rules, groups, bindings, declarations
// ---------------------------------------------------------------------------------------------------------------------

struct RuleNode
{
	SourceLocation Location;
	bool Once;
	bool IsElse;
	Optional<ConditionNode> Condition;
	CallNode[] Actions;
	/// The name after 'then', or null.
	string Then;
	SourceLocation ThenLocation;
}

struct GroupNode
{
	SourceLocation Location;
	string Name;
	Optional<GroupMode> Mode;
	RuleNode[] Rules;
}

/// "at (x, y)" or "in (x, y, w, h)".
struct BindingPlace
{
	int64 X;
	int64 Y;
	Optional<int64> Width;
	Optional<int64> Height;

	bool IsArea()
	{
		if (Width is int64 width)
			return true;

		return false;
	}
}

struct BindingNode
{
	SourceLocation Location;
	CallNode Trigger;
	Optional<BindingPlace> Place;
	string Group;
}

enum DeclKind : int32
{
	Flag,
	Var,
	Var32
}

struct DeclNode
{
	SourceLocation Location;
	DeclKind Kind;
	string Name;
	Optional<int64> Initial;
}

enum PresetKind : int32
{
	Condition,
	Action,
	Pattern
}

struct PresetParam
{
	string Name;
	/// The parameter kind (sym, int, text ...), or null.
	string Kind;
	Optional<ArgNode> Default;
}

struct PresetNode
{
	SourceLocation Location;
	PresetKind Kind;
	string Name;
	PresetParam[] Params;
	Optional<ConditionNode> ConditionBody;
	/// Action fragments: the calls; null for the other kinds.
	CallNode[] ActionBody;
	Optional<CallNode> Trigger;
	Optional<GroupMode> Mode;
	DeclNode[] Decls;
	RuleNode[] Rules;
}

struct UseNode
{
	SourceLocation Location;
	string Name;
	ArgNode[] Args;
	Optional<BindingPlace> Place;
}

enum DurationUnit : int32
{
	Ticks,
	Seconds,
	GameMinutes,
	GameHours
}

const int TicksPerSecond = 50;
const int TicksPerGameMinute = 100;

struct DurationValue
{
	int64 Amount;
	DurationUnit Unit;

	int64 ToTicks()
	{
		switch (Unit)
		{
			case DurationUnit.Ticks:
				return Amount;
			case DurationUnit.Seconds:
				return Amount * TicksPerSecond;
			case DurationUnit.GameMinutes:
				return Amount * TicksPerGameMinute;
			default:
				return Amount * 60 * TicksPerGameMinute;
		}
	}

	int64 ToGameMinutes()
	{
		switch (Unit)
		{
			case DurationUnit.GameMinutes:
				return Amount;
			case DurationUnit.GameHours:
				return Amount * 60;
			default:
				return ToTicks() / TicksPerGameMinute;
		}
	}
}

enum RoutineStepKind : int32
{
	WalkTo,
	Stay,
	Sleep
}

struct RoutineStep
{
	RoutineStepKind Kind;
	/// walk_to: the waypoint, else null.
	string Target;
	Optional<DurationValue> Duration;
}

struct RoutineEntry
{
	SourceLocation Location;
	int64 Minute;
	RoutineStep[] Steps;
}

struct RoutineNode
{
	SourceLocation Location;
	string Name;
	RoutineEntry[] Entries;
}

struct BarkNode
{
	SourceLocation Location;
	/// The text symbol (T.name).
	ArgNode Text;
	Optional<ConditionNode> Condition;
	DurationValue Every;
}

struct GreetNode
{
	SourceLocation Location;
	/// The text symbol (T.name).
	ArgNode Text;
}

struct TopicNode
{
	SourceLocation Location;
	string Word;
	Optional<ConditionNode> Condition;
	CallNode[] Actions;
}

/// "on show_item(I.x) when ... do { ... }" inside an NPC or conversation.
struct OnItemNode
{
	SourceLocation Location;
	string TriggerName;
	ArgNode Argument;
	Optional<ConditionNode> Condition;
	CallNode[] Actions;
}

enum EntityKind : int32
{
	Entity,
	Npc
}

// ---------------------------------------------------------------------------------------------------------------------
// Items of programs, maps, screens and entities
// ---------------------------------------------------------------------------------------------------------------------

enum NodeKind : int32
{
	Decl,
	Map,
	ScreenBlock,
	Binding,
	Group,
	Conversation,
	Entity,
	Preset,
	Use,
	OnItem,
	Bark,
	Routine,
	Greet,
	Topic
}

/// One item of a program, map, screen block, entity or conversation (C#: the subclasses of SyntaxNode). Kind says which of
/// the fields holds the node; maps, screens, entities and conversations have their own items in Items.
struct SyntaxNode
{
	NodeKind Kind;
	SourceLocation Location;
	/// Map, ScreenBlock, Entity, Conversation: the name.
	string Name;
	/// Map: the template or null.
	string Template;
	/// Entity: the kind and the position.
	EntityKind EntityKind;
	int64 X;
	int64 Y;
	SyntaxNode[] Items;
	DeclNode Decl;
	BindingNode Binding;
	GroupNode Group;
	PresetNode Preset;
	UseNode Use;
	OnItemNode OnItem;
	BarkNode Bark;
	RoutineNode Routine;
	GreetNode Greet;
	TopicNode Topic;

	/// The C# class name without "Node" (for "... is not allowed here").
	string KindName()
	{
		switch (Kind)
		{
			case NodeKind.Decl:
				return "Decl";
			case NodeKind.Map:
				return "Map";
			case NodeKind.ScreenBlock:
				return "ScreenBlock";
			case NodeKind.Binding:
				return "Binding";
			case NodeKind.Group:
				return "Group";
			case NodeKind.Conversation:
				return "Conversation";
			case NodeKind.Entity:
				return "Entity";
			case NodeKind.Preset:
				return "Preset";
			case NodeKind.Use:
				return "Use";
			case NodeKind.OnItem:
				return "OnItem";
			case NodeKind.Bark:
				return "Bark";
			case NodeKind.Routine:
				return "Routine";
			case NodeKind.Greet:
				return "Greet";
			default:
				return "Topic";
		}
	}
}

struct ProgramNode
{
	string File;
	SyntaxNode[] Items;
}
