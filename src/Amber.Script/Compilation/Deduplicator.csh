// Stage 3 of the reuse concept (spec section 7.6): groups with byte-identical content are merged into one. Bindings and
// "then" references are remapped. Semantics do not change because only groups without individual state (identical
// operands) can be identical.

namespace Amber.Script.Compilation.Deduplicator;

using System;
using Amber.Base;
using Amber.Script.Common;

/// Merges identical groups of the global scope and of all other scopes (maps, then screens). Returns the number of removed
/// groups.
int Run(CompiledScope global, List<CompiledScope> maps, List<CompiledScope> screens)
{
	int before = global.Groups.Count();
	var globalMapping = Merge(global, true, null);
	int removed = before - global.Groups.Count();

	foreach (var scope in maps)
	{
		int count = scope.Groups.Count();

		Merge(scope, false, globalMapping);
		removed += count - scope.Groups.Count();
	}

	foreach (var scope in screens)
	{
		int count = scope.Groups.Count();

		Merge(scope, false, globalMapping);
		removed += count - scope.Groups.Count();
	}

	return removed;
}

/// Records the (unchanged) group references when deduplication is switched off.
void RecordReferences(CompiledScope scope)
{
	for (var i = 0; i < scope.Groups.Count(); i += 1)
		scope.GroupRefs.Set(scope.Groups.Get(i).Name, scope.Kind == ScopeKind.Global ? Wire.GlobalGroup(i) : Wire.LocalGroup(i));
}

/// Merges the groups of one scope and returns the mapping from old to new group indices. For non-global scopes the global
/// references are remapped with the given mapping first.
int[] Merge(CompiledScope scope, bool isGlobal, int[] globalMapping)
{
	if (globalMapping != null)
		RemapGlobalReferences(scope, globalMapping);

	int count = scope.Groups.Count();
	var representative = new int[count];

	for (var i = 0; i < count; i += 1)
		representative[i] = i;

	bool changed = true;

	while (changed)
	{
		changed = false;

		var seen = Dictionary<string, int>.Create();

		for (var i = 0; i < count; i += 1)
		{
			string signature = Signature(scope.Groups.Get(i), representative, isGlobal);

			if (seen.TryGet(signature) is int first)
			{
				if (representative[i] != first)
				{
					representative[i] = first;
					changed = true;
				}
			}
			else
			{
				seen.Set(signature, i);
			}
		}
	}

	var kept = List<int>.Create();

	for (var i = 0; i < count; i += 1)
	{
		if (representative[i] == i)
			kept.Add(i);
	}

	var newIndex = new int[count];

	for (var i = 0; i < kept.Count(); i += 1)
		newIndex[kept.Get(i)] = i;

	var mapping = new int[count];

	for (var i = 0; i < count; i += 1)
		mapping[i] = newIndex[representative[i]];

	for (var i = 0; i < count; i += 1)
		scope.GroupRefs.Set(scope.Groups.Get(i).Name, isGlobal ? Wire.GlobalGroup(mapping[i]) : Wire.LocalGroup(mapping[i]));

	for (var i = 0; i < count; i += 1)
	{
		if (representative[i] != i)
			scope.Groups.Get(representative[i]).Aliases.Add(scope.Groups.Get(i).Name);
	}

	var newGroups = List<IrGroup>.Create();

	foreach (var index in kept)
		newGroups.Add(scope.Groups.Get(index));

	foreach (var group in newGroups)
	{
		for (var r = 0; r < group.Rules.Count(); r += 1)
		{
			var rule = group.Rules.Get(r);

			rule.Next = Remap(rule.Next, isGlobal, mapping);
			group.Rules.Set(r, rule);
		}
	}

	for (var b = 0; b < scope.Bindings.Count(); b += 1)
	{
		var binding = scope.Bindings.Get(b);

		binding.Group = Remap(binding.Group, isGlobal, mapping);
		scope.Bindings.Set(b, binding);
	}

	scope.Groups.Clear();

	foreach (var group in newGroups)
		scope.Groups.Add(group);

	return mapping;
}

uint16 Remap(uint16 reference, bool isGlobal, int[] mapping)
{
	if (reference == Wire.None)
		return reference;

	if (isGlobal)
		return Wire.GlobalGroup(mapping[Wire.GroupIndex(reference)]);

	if (Wire.IsLocalGroup(reference))
		return Wire.LocalGroup(mapping[Wire.GroupIndex(reference)]);

	return reference;
}

uint16 MapGlobal(uint16 reference, int[] mapping)
{
	if (reference == Wire.None || Wire.IsLocalGroup(reference))
		return reference;

	return Wire.GlobalGroup(mapping[Wire.GroupIndex(reference)]);
}

void RemapGlobalReferences(CompiledScope scope, int[] globalMapping)
{
	foreach (var group in scope.Groups)
	{
		for (var r = 0; r < group.Rules.Count(); r += 1)
		{
			var rule = group.Rules.Get(r);

			rule.Next = MapGlobal(rule.Next, globalMapping);
			group.Rules.Set(r, rule);
		}
	}

	for (var b = 0; b < scope.Bindings.Count(); b += 1)
	{
		var binding = scope.Bindings.Get(b);

		binding.Group = MapGlobal(binding.Group, globalMapping);
		scope.Bindings.Set(b, binding);
	}
}

string Signature(IrGroup group, int[] representative, bool isGlobal)
{
	var builder = StringBuilder.Create();

	builder.Append(((int)group.Mode).ToString());

	foreach (var rule in group.Rules)
	{
		builder.Append('|');
		AppendInstructions(builder, rule.Conditions);
		builder.Append('>');
		AppendInstructions(builder, rule.Actions);
		builder.Append('~');

		if (rule.Next == Wire.None)
		{
			builder.Append('-');
		}
		else if (isGlobal || Wire.IsLocalGroup(rule.Next))
		{
			builder.Append(isGlobal ? 'G' : 'L');
			builder.Append(representative[Wire.GroupIndex(rule.Next)].ToString());
		}
		else
		{
			builder.Append('G');
			builder.Append(Wire.GroupIndex(rule.Next).ToString());
		}
	}

	return builder.ToString();
}

void AppendInstructions(StringBuilder builder, List<IrInstruction> instructions)
{
	foreach (var instruction in instructions)
	{
		builder.Append(instruction.Op.ToString());
		builder.Append(instruction.Neg ? 'n' : '.');
		builder.Append(instruction.OrNext ? 'o' : '.');

		foreach (var operand in instruction.Operands)
		{
			builder.Append(',');
			builder.Append(operand.ToString());
		}

		builder.Append(';');
	}
}
