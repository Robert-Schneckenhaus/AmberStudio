namespace Amber.Script.Compilation;

using System;
using Amber.Base;
using Amber.Script.Common;
using Amber.Script.Syntax;

/// A declared state slot.
struct SlotInfo
{
	SlotKind Kind;
	uint16 Slot;
}

/// Substitution and context of a preset expansion. Parameters are replaced when arguments are compiled.
struct ExpansionContext
{
	Dictionary<string, ArgNode> Params;
	Dictionary<string, SlotInfo> InstanceSlots;
	/// Entity which "near(range)" refers to inside NPC blocks and barks, or null.
	string ImplicitEntity;
	/// Expansion depth of nested preset fragments.
	int Depth;
	List<string> Stack;

	static ExpansionContext Empty()
	{
		return ExpansionContext
		{
			Params = Dictionary<string, ArgNode>.Create(),
			InstanceSlots = Dictionary<string, SlotInfo>.Create(),
			ImplicitEntity = null,
			Depth = 0,
			Stack = List<string>.Create()
		};
	}

	static ExpansionContext ForEntity(string entity)
	{
		var env = Empty();

		env.ImplicitEntity = entity;

		return env;
	}
}

/// A group whose rules are still syntax nodes (compiled in the second pass when all names are known).
struct PendingGroup
{
	string Name;
	GroupMode Mode;
	RuleNode[] Rules;
	SourceLocation Location;
	ExpansionContext Env;
	string Origin;
	int Index;
}

/// A binding whose group name is resolved in the second pass.
struct PendingBinding
{
	string TriggerName;
	ArgNode[] TriggerArgs;
	Optional<BindingPlace> Place;
	string GroupName;
	SourceLocation Location;
	ExpansionContext Env;
	/// The entity of an entity binding, or null.
	string EntityName;
	string Origin;
}

/// Conversation content collected from NPC blocks and conversation blocks of one entity.
struct ConversationData
{
	string Entity;
	SourceLocation Location;
	Optional<GreetNode> Greet;
	List<TopicNode> Topics;
	List<OnItemNode> OnItems;

	bool HasContent()
	{
		if (Greet is GreetNode greet)
			return true;

		return Topics.Count() > 0 || OnItems.Count() > 0;
	}
}

/// All names and pending items of one scope (global, one map or one screen). A handle to shared storage.
struct ScopeContext
{
	ScopeKind Kind;
	string Name;
	CompiledScope Output;
	Dictionary<string, SlotInfo> Slots;
	Dictionary<string, PendingGroup> NamedGroups;
	List<PendingGroup> Groups;
	List<PendingBinding> Bindings;
	Dictionary<string, PresetNode> Presets;
	Dictionary<string, int> Entities;
	Dictionary<string, int> Routines;
	Dictionary<string, int> Nodes;
	Dictionary<string, ConversationData> Conversations;
	List<RoutineNode> RoutineNodes;
	Cell<uint16> ScreenId;

	static ScopeContext Create(ScopeKind kind, string name, CompiledScope output)
	{
		return ScopeContext
		{
			Kind = kind,
			Name = name,
			Output = output,
			Slots = Dictionary<string, SlotInfo>.Create(),
			NamedGroups = Dictionary<string, PendingGroup>.Create(),
			Groups = List<PendingGroup>.Create(),
			Bindings = List<PendingBinding>.Create(),
			Presets = Dictionary<string, PresetNode>.Create(),
			Entities = Dictionary<string, int>.Create(),
			Routines = Dictionary<string, int>.Create(),
			Nodes = Dictionary<string, int>.Create(),
			Conversations = Dictionary<string, ConversationData>.Create(),
			RoutineNodes = List<RoutineNode>.Create(),
			ScreenId = Cell<uint16>.Of(0)
		};
	}

	StateNamespace Namespace()
	{
		switch (Kind)
		{
			case ScopeKind.Global:
				return StateNamespace.Global;
			case ScopeKind.Map:
				return StateNamespace.Map;
			default:
				return StateNamespace.Screen;
		}
	}

	/// The next index of the kind (and counts it).
	int NextIndex(SlotKind kind)
	{
		switch (kind)
		{
			case SlotKind.Flag:
			{
				int index = Output.FlagCount.Get();

				Output.FlagCount.Set(index + 1);

				return index;
			}
			case SlotKind.Var:
			{
				int index = Output.VarCount.Get();

				Output.VarCount.Set(index + 1);

				return index;
			}
			default:
			{
				int index = Output.Var32Count.Get();

				Output.Var32Count.Set(index + 1);

				return index;
			}
		}
	}

	/// True for the same scope (C#: reference equality).
	bool Is(ScopeContext other)
	{
		return Output.Id == other.Output.Id;
	}
}

/// Everything a compiled item needs to know about where it is compiled. UsesHere is shared by all copies of the context of
/// one group: a "here" operand sets it (C#: the IrGroup of the context).
struct CompileContext
{
	ScopeContext Scope;
	ExpansionContext Env;
	bool HasGroup;
	Cell<bool> UsesHere;

	CompileContext WithEnv(ExpansionContext env)
	{
		return CompileContext { Scope = Scope, Env = env, HasGroup = HasGroup, UsesHere = UsesHere };
	}
}
