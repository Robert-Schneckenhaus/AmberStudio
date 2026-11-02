// Checks that need the complete program: trigger positions (E015), chain cycles (E006, W006), unreachable groups (W001),
// flag usage (W002, W003) and autosave placement (W004).

namespace Amber.Script.Compilation;

using System;
using Amber.Base;
using Amber.Script.Common;
using Amber.Script.Syntax;

/// A group of a scope (C#: record struct GroupKey(CompiledScope Scope, int Index)); Scope is the ID of the scope.
struct GroupKey : IEquatable<GroupKey>, IHashable
{
	int Scope;
	int Index;

	bool Equals(GroupKey other)
	{
		return Scope == other.Scope && Index == other.Index;
	}

	int GetHashCode()
	{
		return unchecked(Scope * 65599 + Index);
	}
}

GroupKey Key(int scope, int index)
{
	return GroupKey { Scope = scope, Index = index };
}

IrGroup GroupOf(Compiler c, GroupKey key)
{
	return c.ScopeById(key.Scope).Output.Groups.Get(key.Index);
}

void Analyze(Compiler c)
{
	var referenced = HashSet<GroupKey>.Create();

	foreach (var scope in c.AllScopes)
	{
		foreach (var binding in scope.Output.Bindings)
		{
			if (ResolveGroup(c, scope.Output, binding.Group) is GroupKey target)
			{
				referenced.Add(target);
				CheckTriggerPosition(c, binding, target);
			}
		}

		foreach (var group in scope.Output.Groups)
		{
			foreach (var rule in group.Rules)
			{
				if (ResolveGroup(c, scope.Output, rule.Next) is GroupKey target)
					referenced.Add(target);
			}
		}
	}

	foreach (var scope in c.AllScopes)
	{
		// screen handlers are referenced from the screen definitions (YAML), which the compiler does not read yet
		if (scope.Kind == ScopeKind.Screen)
			continue;

		for (var i = 0; i < scope.Output.Groups.Count(); i += 1)
		{
			if (!referenced.Contains(Key(scope.Output.Id, i)))
			{
				var group = scope.Output.Groups.Get(i);

				c.Diagnostics.Warning("W001", "Group '" + group.Name + "' is not reachable from any binding or 'then'.", group.Location);
			}
		}
	}

	FindCycles(c);
	CheckFlagUsage(c);
	CheckAutosave(c);
}

/// A flag slot of a namespace instance (C#: the tuple (StateNamespace, CompiledScope?, int)); Scope is -1 for global slots.
struct FlagKey : IEquatable<FlagKey>, IHashable
{
	int Namespace;
	int Scope;
	int Index;

	bool Equals(FlagKey other)
	{
		return Namespace == other.Namespace && Scope == other.Scope && Index == other.Index;
	}

	int GetHashCode()
	{
		return unchecked((Namespace * 31 + Scope) * 65599 + Index);
	}
}

FlagKey KeyOfFlag(CompiledScope owner, uint16 slot)
{
	var ns = Wire.SlotNamespace(slot);

	return FlagKey { Namespace = (int)ns, Scope = ns == StateNamespace.Global ? -1 : owner.Id, Index = Wire.SlotIndex(slot) };
}

/// W002 (a declared flag is set but never read) and W003 (read but never set). Only flags the author declared are reported;
/// the generated flags of 'once' and presets are always set and read.
void CheckFlagUsage(Compiler c)
{
	var read = HashSet<FlagKey>.Create();
	var written = HashSet<FlagKey>.Create();

	foreach (var scope in c.AllScopes)
	{
		foreach (var binding in scope.Output.Bindings)
		{
			if (binding.Trigger == TriggerType.FlagChanged)
				read.Add(KeyOfFlag(scope.Output, binding.P1));
		}

		foreach (var group in scope.Output.Groups)
		{
			foreach (var rule in group.Rules)
			{
				foreach (var condition in rule.Conditions)
				{
					if (condition.Op == (uint8)ConditionOp.Flag)
						read.Add(KeyOfFlag(scope.Output, condition.Operands[0]));
				}

				foreach (var action in rule.Actions)
				{
					if (action.Op != (uint8)ActionOp.SetFlag && action.Op != (uint8)ActionOp.ClearFlag && action.Op != (uint8)ActionOp.ToggleFlag)
						continue;

					var key = KeyOfFlag(scope.Output, action.Operands[0]);

					written.Add(key);

					// a toggle depends on the old value
					if (action.Op == (uint8)ActionOp.ToggleFlag)
						read.Add(key);
				}
			}
		}
	}

	foreach (var flag in c.DeclaredFlags)
	{
		var key = KeyOfFlag(flag.Scope.Output, flag.Slot);

		if (written.Contains(key) && !read.Contains(key))
			c.Diagnostics.Warning("W002", "Flag '" + flag.Name + "' is set but never read.", flag.Location);
		else if (read.Contains(key) && !written.Contains(key))
			c.Diagnostics.Warning("W003", "Flag '" + flag.Name + "' is read but never set.", flag.Location);
	}
}

/// W004: autosave saves at the end of the chain, so it belongs at the end of a rule without 'then'.
void CheckAutosave(Compiler c)
{
	foreach (var scope in c.AllScopes)
	{
		foreach (var group in scope.Output.Groups)
		{
			foreach (var rule in group.Rules)
			{
				int index = -1;

				for (var i = 0; i < rule.Actions.Count(); i += 1)
				{
					if (rule.Actions.Get(i).Op == (uint8)ActionOp.Autosave)
					{
						index = i;
						break;
					}
				}

				if (index >= 0 && (index != rule.Actions.Count() - 1 || rule.Next != Wire.None))
					c.Diagnostics.Warning("W004", "'autosave' in group '" + group.Name + "' is not the last action of a rule without 'then'.", group.Location);
			}
		}
	}
}

Optional<GroupKey> ResolveGroup(Compiler c, CompiledScope scope, uint16 reference)
{
	if (reference == Wire.None)
		return null;

	if (Wire.IsLocalGroup(reference))
	{
		int index = Wire.GroupIndex(reference);

		if (index < scope.Groups.Count())
			return Key(scope.Id, index);

		return null;
	}

	int globalIndex = Wire.GroupIndex(reference);

	if (globalIndex < c.Result.Global.Groups.Count())
		return Key(c.Result.Global.Id, globalIndex);

	return null;
}

void CheckTriggerPosition(Compiler c, IrBinding binding, GroupKey start)
{
	if (binding.HasTriggerPosition())
		return;

	var visited = HashSet<GroupKey>.Create();
	var pending = List<GroupKey>.Create();

	pending.Add(start);

	while (pending.Count() > 0)
	{
		var key = pending.Get(pending.Count() - 1);

		pending.RemoveAt(pending.Count() - 1);

		if (!visited.Add(key))
			continue;

		var scope = c.ScopeById(key.Scope).Output;
		var group = scope.Groups.Get(key.Index);

		if (group.UsesHere)
		{
			c.Diagnostics.Error("E015", "Group '" + group.Name + "' uses 'here' but binding '" + TriggerTypeName(binding.Trigger) + "' (scope "
				+ TriggerScopeName(binding.Scope) + ") has no trigger position.", binding.Location);

			return;
		}

		foreach (var rule in group.Rules)
		{
			if (ResolveGroup(c, scope, rule.Next) is GroupKey next)
				pending.Add(next);
		}
	}
}

void FindCycles(Compiler c)
{
	// edges of rules which are always selected first (unconditional first rule) can form an endless chain (E006)
	var sure = Dictionary<GroupKey, List<GroupKey>>.Create();
	var possible = Dictionary<GroupKey, List<GroupKey>>.Create();

	foreach (var scope in c.AllScopes)
	{
		for (var i = 0; i < scope.Output.Groups.Count(); i += 1)
		{
			var key = Key(scope.Output.Id, i);
			var group = scope.Output.Groups.Get(i);
			var sureEdges = List<GroupKey>.Create();
			var possibleEdges = List<GroupKey>.Create();

			for (var r = 0; r < group.Rules.Count(); r += 1)
			{
				var rule = group.Rules.Get(r);

				if (ResolveGroup(c, scope.Output, rule.Next) is GroupKey next)
				{
					possibleEdges.Add(next);

					if (r == 0 && rule.IsUnconditional())
						sureEdges.Add(next);
				}
			}

			sure.Set(key, sureEdges);
			possible.Set(key, possibleEdges);
		}
	}

	var reported = HashSet<GroupKey>.Create();

	foreach (var key in sure.Keys())
	{
		if (Reaches(sure, key, key))
		{
			if (reported.Add(key))
			{
				var group = GroupOf(c, key);

				c.Diagnostics.Error("E006", "Group '" + group.Name + "' is part of an endless 'then' chain (all rules are unconditional).", group.Location);
			}
		}
	}

	foreach (var key in possible.Keys())
	{
		if (!reported.Contains(key) && Reaches(possible, key, key))
		{
			if (reported.Add(key))
			{
				var group = GroupOf(c, key);

				c.Diagnostics.Warning("W006", "Group '" + group.Name + "' is part of a 'then' cycle (limited by maxChainSteps at runtime).", group.Location);
			}
		}
	}
}

bool Reaches(Dictionary<GroupKey, List<GroupKey>> graph, GroupKey from, GroupKey target)
{
	var visited = HashSet<GroupKey>.Create();
	var pending = List<GroupKey>.Create();

	foreach (var next in graph.GetOrDefault(from, List<GroupKey>.Create()))
		pending.Add(next);

	while (pending.Count() > 0)
	{
		var key = pending.Get(pending.Count() - 1);

		pending.RemoveAt(pending.Count() - 1);

		if (key.Equals(target))
			return true;

		if (!visited.Add(key))
			continue;

		foreach (var next in graph.GetOrDefault(key, List<GroupKey>.Create()))
			pending.Add(next);
	}

	return false;
}
