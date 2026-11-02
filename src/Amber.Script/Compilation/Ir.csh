namespace Amber.Script.Compilation;

using System;
using Amber.Base;
using Amber.Script.Common;
using Amber.Script.Syntax;

/// One condition or action instruction before it is written as words.
struct IrInstruction
{
	uint8 Op;
	uint16[] Operands;
	bool OrNext;
	bool Neg;

	static IrInstruction Create(uint8 op, uint16[] operands, bool orNext, bool neg)
	{
		return IrInstruction { Op = op, Operands = operands, OrNext = orNext, Neg = neg };
	}

	int Words()
	{
		return 1 + Operands.Length;
	}
}

struct IrRule
{
	List<IrInstruction> Conditions;
	List<IrInstruction> Actions;
	/// Group reference of the follow-up group or Wire.None.
	uint16 Next;
	/// Name of the follow-up group as written in source (for dumps and analysis), or null.
	string NextName;

	static IrRule Create()
	{
		return IrRule { Conditions = List<IrInstruction>.Create(), Actions = List<IrInstruction>.Create(), Next = Wire.None, NextName = null };
	}

	bool IsUnconditional()
	{
		return Conditions.Count() == 0;
	}
}

struct IrGroup
{
	string Name;
	GroupMode Mode;
	SourceLocation Location;
	/// Human readable origin like "lever @ file.ams:12" for presets and generated groups, or null.
	string Origin;
	/// True if a "here" operand is used. Bindings which reach this group must provide a trigger position (E015).
	bool UsesHere;
	List<IrRule> Rules;
	/// Names of identical groups which were merged into this one.
	List<string> Aliases;

	static IrGroup Create(string name, GroupMode mode, SourceLocation location)
	{
		return IrGroup { Name = name, Mode = mode, Location = location, Origin = null, UsesHere = false, Rules = List<IrRule>.Create(), Aliases = List<string>.Create() };
	}
}

struct IrBinding
{
	TriggerType Trigger;
	TriggerScope Scope;
	uint16 Group;
	string GroupName;
	uint16 P1;
	uint16 P2;
	uint16 Sx;
	uint16 Sy;
	uint16 Sw;
	uint16 Sh;
	SourceLocation Location;
	/// Where a generated binding comes from, or null.
	string Origin;

	bool HasTriggerPosition()
	{
		return Scope == TriggerScope.Tile || Scope == TriggerScope.Area || Scope == TriggerScope.Entity;
	}
}

enum SlotKind : int32
{
	Flag,
	Var,
	Var32
}

EnumEntry[] SlotKindNames = new EnumEntry[] { En("Flag", 0), En("Var", 1), En("Var32", 2) };

string SlotKindName(SlotKind kind)
{
	return EnumName(SlotKindNames, (int)kind);
}

/// A slot in the state layout (spec section 10.1).
struct LayoutEntry
{
	StateNamespace Namespace;
	SlotKind Kind;
	string Name;
	int Index;
}

/// An entity (entity/npc block) with its position, for hosts which place actors on the map.
struct EntityInfo
{
	string Name;
	int Id;
	int X;
	int Y;
	EntityKind Kind;
}

/// A routine of an NPC (spec section 7.4). The first routine of an entity is its default routine.
struct RoutineInfo
{
	int Id;
	string Name;
	string Entity;
	RoutineNode Node;
}

/// The conversation content of an entity as far as a conversation screen needs it. Greeting is the name of the greeting
/// text or null.
struct ConversationInfo
{
	string Entity;
	string Greeting;
	string[] Topics;
}

/// Compilation result of one scope (global scripts, one map or one screen). A handle: copies share the lists and the
/// counters, like the C# class.
struct CompiledScope
{
	/// The position of the scope in CompilationResult.AllScopes (the global scope is 0); identifies the scope.
	int Id;
	ScopeKind Kind;
	string Name;
	List<IrGroup> Groups;
	List<IrBinding> Bindings;
	List<LayoutEntry> Layout;
	Dictionary<string, int> Entities;
	List<EntityInfo> EntityInfos;
	List<RoutineInfo> RoutineInfos;
	Dictionary<string, ConversationInfo> Conversations;
	List<RoutineNode> Routines;
	/// Final group reference for every group name of the scope (after deduplication several names can share one group).
	Dictionary<string, uint16> GroupRefs;
	Cell<int> FlagCount;
	Cell<int> VarCount;
	Cell<int> Var32Count;
	Cell<uint8[]> GroupsChunk;
	Cell<uint8[]> BindingsChunk;

	static CompiledScope Create(int id, ScopeKind kind, string name)
	{
		return CompiledScope
		{
			Id = id,
			Kind = kind,
			Name = name,
			Groups = List<IrGroup>.Create(),
			Bindings = List<IrBinding>.Create(),
			Layout = List<LayoutEntry>.Create(),
			Entities = Dictionary<string, int>.Create(),
			EntityInfos = List<EntityInfo>.Create(),
			RoutineInfos = List<RoutineInfo>.Create(),
			Conversations = Dictionary<string, ConversationInfo>.Create(),
			Routines = List<RoutineNode>.Create(),
			GroupRefs = Dictionary<string, uint16>.Create(),
			FlagCount = Cell<int>.Of(0),
			VarCount = Cell<int>.Of(0),
			Var32Count = Cell<int>.Of(0),
			GroupsChunk = Cell<uint8[]>.Of(new uint8[0]),
			BindingsChunk = Cell<uint8[]>.Of(new uint8[0])
		};
	}

	ScriptChunk ToChunk()
	{
		return ScriptChunk.Of(GroupsChunk.Get(), BindingsChunk.Get());
	}

	/// The group with the name, or no value.
	Optional<IrGroup> FindGroup(string name)
	{
		foreach (var group in Groups)
		{
			if (group.Name == name)
				return group;
		}

		return null;
	}
}
