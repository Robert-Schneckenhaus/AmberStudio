// Pattern statistics over compiled rules (task M1.14): the most frequent rule shapes, chain lengths, fan-in, duplicate and
// near-duplicate rules. The result is input for decisions about standard presets and about a "group done" trigger. Run it
// on a compilation without deduplication.

namespace Amber.Script.Compilation.PatternStatistics;

using System;
using Amber.Base;
using Amber.Script.Common;

/// Items grouped by a text key in the order of the first appearance of each key (C#: LINQ GroupBy).
struct TextGroup
{
	string Key;
	int Count;
	/// The indices of the items of the group.
	List<int> Items;
}

List<TextGroup> GroupByText(string[] keys)
{
	var groups = List<TextGroup>.Create();
	var index = Dictionary<string, int>.Create();

	for (var i = 0; i < keys.Length; i += 1)
	{
		if (index.TryGet(keys[i]) is int position)
		{
			var group = groups.Get(position);

			group.Count += 1;
			group.Items.Add(i);
			groups.Set(position, group);
		}
		else
		{
			var items = List<int>.Create();

			items.Add(i);
			index.Set(keys[i], groups.Count());
			groups.Add(TextGroup { Key = keys[i], Count = 1, Items = items });
		}
	}

	return groups;
}

/// Descending by count, equal counts keep their order (C#: OrderByDescending).
int ByCountDescending(TextGroup a, TextGroup b)
{
	return CompareInt(b.Count, a.Count);
}

int DistinctCount(List<string> values)
{
	var seen = HashSet<string>.Create();

	foreach (var value in values)
		seen.Add(value);

	return seen.Count();
}

string Create(CompilationResult result, int top)
{
	var scopes = result.AllScopes();
	var builder = StringBuilder.Create();

	builder.AppendLine("# Pattern statistics");
	builder.AppendLine();

	int groupCount = 0;
	int ruleCount = 0;
	int bindingCount = 0;

	foreach (var scope in scopes)
	{
		groupCount += scope.Groups.Count();
		bindingCount += scope.Bindings.Count();

		foreach (var group in scope.Groups)
			ruleCount += group.Rules.Count();
	}

	builder.AppendLine("Scopes: " + scopes.Count() + ", groups: " + groupCount + ", rules: " + ruleCount + ", bindings: " + bindingCount);
	builder.AppendLine();

	AppendTriggers(builder, scopes);
	AppendShapes(builder, scopes, top);
	AppendChains(builder, scopes);
	AppendDuplicates(builder, scopes);

	return builder.ToString();
}

void AppendTriggers(StringBuilder builder, List<CompiledScope> scopes)
{
	builder.AppendLine("## Bindings per trigger");
	builder.AppendLine();

	var keys = List<string>.Create();

	foreach (var scope in scopes)
	{
		foreach (var binding in scope.Bindings)
			keys.Add(TriggerTypeName(binding.Trigger));
	}

	var groups = GroupByText(ArrayOf(keys));

	SortList(groups, ByCountDescending);

	foreach (var group in groups)
		builder.AppendLine("- " + group.Key + ": " + group.Count);

	builder.AppendLine();
}

string ShapeOf(IrRule rule)
{
	var conditions = List<string>.Create();
	var actions = List<string>.Create();

	foreach (var instruction in rule.Conditions)
	{
		string name = "?";

		if (ConditionTable.ByOp((int)instruction.Op) is OpInfo info)
			name = info.Name;

		conditions.Add(Describe(instruction, name));
	}

	foreach (var instruction in rule.Actions)
	{
		string name = "?";

		if (ActionTable.ByOp((int)instruction.Op) is OpInfo info)
			name = info.Name;

		actions.Add(name);
	}

	string conditionText = JoinList(" ", conditions);
	string actionText = JoinList(" ", actions);

	return (conditionText.Length == 0 ? "-" : conditionText) + " => " + (actionText.Length == 0 ? "-" : actionText) + (rule.Next == Wire.None ? "" : " => then");
}

string Describe(IrInstruction instruction, string name)
{
	return (instruction.Neg ? "not " : "") + name + (instruction.OrNext ? " or" : "");
}

string OperandKey(IrRule rule)
{
	var parts = List<string>.Create();

	foreach (var instruction in rule.Conditions)
		parts.Add(OperandList(instruction));

	foreach (var instruction in rule.Actions)
		parts.Add(OperandList(instruction));

	return JoinList(";", parts);
}

string OperandList(IrInstruction instruction)
{
	var parts = new string[instruction.Operands.Length];

	for (var i = 0; i < parts.Length; i += 1)
		parts[i] = instruction.Operands[i].ToString();

	return string.Join(",", parts);
}

void AppendShapes(StringBuilder builder, List<CompiledScope> scopes, int top)
{
	var rules = List<IrRule>.Create();

	foreach (var scope in scopes)
	{
		foreach (var group in scope.Groups)
		{
			foreach (var rule in group.Rules)
				rules.Add(rule);
		}
	}

	var shapes = new string[rules.Count()];

	for (var i = 0; i < shapes.Length; i += 1)
		shapes[i] = ShapeOf(rules.Get(i));

	var groups = GroupByText(shapes);

	SortList(groups, ByCountDescending);

	builder.AppendLine("## Most frequent rule shapes (top " + top + " of " + groups.Count() + ")");
	builder.AppendLine();
	builder.AppendLine("Format: uses / distinct operand sets, `conditions => actions`. Shapes with many uses but few distinct operand sets are candidates for shared groups, shapes with many distinct sets for presets.");
	builder.AppendLine();

	for (var g = 0; g < groups.Count() && g < top; g += 1)
	{
		var shape = groups.Get(g);
		var keys = List<string>.Create();

		foreach (var index in shape.Items)
			keys.Add(OperandKey(rules.Get(index)));

		builder.AppendLine("- " + shape.Count + " / " + DistinctCount(keys) + ": `" + shape.Key + "`");
	}

	builder.AppendLine();
}

Optional<GroupKey> ResolveReference(CompiledScope scope, uint16 reference, Optional<CompiledScope> global)
{
	if (reference == Wire.None)
		return null;

	if (Wire.IsLocalGroup(reference))
		return Key(scope.Id, Wire.GroupIndex(reference));

	if (global is CompiledScope globalScope)
		return Key(globalScope.Id, Wire.GroupIndex(reference));

	return null;
}

CompiledScope ScopeWithId(List<CompiledScope> scopes, int id)
{
	foreach (var scope in scopes)
	{
		if (scope.Id == id)
			return scope;
	}

	return scopes.Get(0);
}

void AppendChains(StringBuilder builder, List<CompiledScope> scopes)
{
	builder.AppendLine("## Chains (then)");
	builder.AppendLine();

	var histogram = new int[9];
	var fanIn = Dictionary<GroupKey, int>.Create();
	Optional<CompiledScope> global = null;

	foreach (var scope in scopes)
	{
		if (scope.Kind == ScopeKind.Global)
		{
			global = scope;
			break;
		}
	}

	foreach (var scope in scopes)
	{
		foreach (var binding in scope.Bindings)
		{
			if (ResolveReference(scope, binding.Group, global) is GroupKey target)
				fanIn.Set(target, fanIn.GetOrDefault(target, 0) + 1);
		}

		foreach (var group in scope.Groups)
		{
			foreach (var rule in group.Rules)
			{
				if (ResolveReference(scope, rule.Next, global) is GroupKey target)
					fanIn.Set(target, fanIn.GetOrDefault(target, 0) + 1);
			}
		}

		foreach (var binding in scope.Bindings)
		{
			if (ResolveReference(scope, binding.Group, global) is GroupKey start)
				histogram[Math.Min(ChainLength(scopes, start, HashSet<GroupKey>.Create(), global), histogram.Length - 1)] += 1;
		}
	}

	builder.AppendLine("Longest chain per binding (number of groups, last bucket = longer):");
	builder.AppendLine();

	for (var i = 1; i < histogram.Length; i += 1)
		builder.AppendLine("- " + i + (i == histogram.Length - 1 ? "+" : "") + ": " + histogram[i]);

	builder.AppendLine();

	int shared = 0;

	foreach (var count in fanIn.Values())
	{
		if (count >= 2)
			shared += 1;
	}

	builder.AppendLine("Groups referenced more than once (fan-in >= 2): " + shared + " of " + fanIn.Count() + " referenced groups.");
	builder.AppendLine();

	int withThen = 0;

	foreach (var scope in scopes)
	{
		foreach (var group in scope.Groups)
		{
			foreach (var rule in group.Rules)
			{
				if (rule.Next != Wire.None)
					withThen += 1;
			}
		}
	}

	builder.AppendLine("Rules with `then`: " + withThen);
	builder.AppendLine();
}

int ChainLength(List<CompiledScope> scopes, GroupKey start, HashSet<GroupKey> visited, Optional<CompiledScope> global)
{
	if (!visited.Add(start))
		return 0;

	int longest = 0;
	var scope = ScopeWithId(scopes, start.Scope);

	foreach (var rule in scope.Groups.Get(start.Index).Rules)
	{
		if (ResolveReference(scope, rule.Next, global) is GroupKey next)
			longest = Math.Max(longest, ChainLength(scopes, next, visited, global));
	}

	visited.Remove(start);

	return 1 + longest;
}

struct ScopedGroup
{
	CompiledScope Scope;
	IrGroup Group;
}

int InstructionWords(List<IrInstruction> instructions)
{
	int sum = 0;

	foreach (var instruction in instructions)
		sum += instruction.Words();

	return sum;
}

void AppendDuplicates(StringBuilder builder, List<CompiledScope> scopes)
{
	builder.AppendLine("## Duplicates");
	builder.AppendLine();

	var groups = List<ScopedGroup>.Create();

	foreach (var scope in scopes)
	{
		foreach (var group in scope.Groups)
			groups.Add(ScopedGroup { Scope = scope, Group = group });
	}

	var contentKeys = new string[groups.Count()];
	var shapeKeys = new string[groups.Count()];
	var operandKeys = new string[groups.Count()];

	for (var i = 0; i < groups.Count(); i += 1)
	{
		var content = List<string>.Create();
		var shape = List<string>.Create();
		var operands = List<string>.Create();

		foreach (var rule in groups.Get(i).Group.Rules)
		{
			content.Add(ShapeOf(rule) + "@" + OperandKey(rule));
			shape.Add(ShapeOf(rule));
			operands.Add(OperandKey(rule));
		}

		contentKeys[i] = JoinList("|", content);
		shapeKeys[i] = JoinList("|", shape);
		operandKeys[i] = JoinList("|", operands);
	}

	int redundant = 0;
	int64 duplicateBytes = 0;

	foreach (var duplicate in GroupByText(contentKeys))
	{
		if (duplicate.Count <= 1)
			continue;

		int words = 2;

		foreach (var rule in groups.Get(duplicate.Items.Get(0)).Group.Rules)
			words += 4 + InstructionWords(rule.Conditions) + InstructionWords(rule.Actions);

		redundant += duplicate.Count - 1;
		duplicateBytes += (int64)(duplicate.Count - 1) * words * 2;
	}

	builder.AppendLine("Groups with identical rules (before deduplication): " + redundant + " redundant, about " + duplicateBytes + " bytes.");
	builder.AppendLine();

	var near = List<TextGroup>.Create();

	foreach (var candidate in GroupByText(shapeKeys))
	{
		if (candidate.Count <= 1)
			continue;

		var sets = List<string>.Create();

		foreach (var index in candidate.Items)
			sets.Add(operandKeys[index]);

		if (DistinctCount(sets) > 1)
			near.Add(candidate);
	}

	SortList(near, ByCountDescending);

	builder.AppendLine("Groups of the same shape with different operands (preset candidates):");
	builder.AppendLine();

	for (var n = 0; n < near.Count() && n < 10; n += 1)
	{
		var candidate = near.Get(n);
		var sets = List<string>.Create();
		var names = List<string>.Create();

		foreach (var index in candidate.Items)
		{
			sets.Add(operandKeys[index]);

			if (names.Count() < 4)
				names.Add(groups.Get(index).Group.Name);
		}

		builder.AppendLine("- " + candidate.Count + " groups, " + DistinctCount(sets) + " operand sets: " + JoinList(", ", names) + (candidate.Count > 4 ? ", ..." : ""));
	}

	builder.AppendLine();
}
