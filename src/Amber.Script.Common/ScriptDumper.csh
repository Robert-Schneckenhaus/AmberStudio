// Turns chunks back into readable text (spec section 4.7, dump tool). Symbol IDs are shown as prefix.#id because the
// chunks do not contain names.

namespace Amber.Script.Common.ScriptDumper;

using System;
using Amber.Base;

const ReadOnlySlice<string> Comparisons = ["==", "!=", "<", "<=", ">", ">="];

Error<string> Dump(ScriptChunk chunk)
{
	var builder = StringBuilder.Create();

	for (var i = 0; i < chunk.BindingCount; i += 1)
		builder.AppendLine(DumpBinding(i, try chunk.ReadBinding(i)));

	if (chunk.BindingCount > 0)
		builder.AppendLine();

	for (var i = 0; i < chunk.GroupCount; i += 1)
		try DumpGroup(builder, chunk, i);

	return builder.ToString();
}

string DumpBinding(int index, BindingRecord binding)
{
	string name = "trigger#" + Hex((int)binding.Trigger, 2);

	if (TriggerTable.ByType(binding.Trigger) is TriggerInfo info)
		name = info.Name;

	string scope;

	switch (binding.Scope)
	{
		case TriggerScope.Tile:
			scope = "at (" + binding.Sx + ", " + binding.Sy + ")";
			break;
		case TriggerScope.Area:
			scope = "in (" + binding.Sx + ", " + binding.Sy + ", " + binding.Sw + ", " + binding.Sh + ")";
			break;
		case TriggerScope.Entity:
			scope = "entity " + binding.Sx;
			break;
		case TriggerScope.Screen:
			scope = "screen " + binding.Sx;
			break;
		case TriggerScope.Node:
			scope = "node " + binding.Sx;
			break;
		default:
			scope = TriggerScopeName(binding.Scope).ToLower();
			break;
	}

	return "binding " + index + ": on " + name + "(" + HexOrAny(binding.P1) + ", " + HexOrAny(binding.P2) + ") " + scope + " -> "
		+ GroupName(binding.Group);
}

Error<void> DumpGroup(StringBuilder builder, ScriptChunk chunk, int index)
{
	var header = try chunk.ReadGroupHeader(index);

	builder.AppendLine("group " + index + " [" + GroupModeName(header.Mode).ToLower() + "] (" + header.RuleCount + " rule(s))");

	int ruleOffset = header.FirstRuleOffset;

	for (var r = 0; r < header.RuleCount; r += 1)
	{
		var rule = try chunk.ReadRuleHeader(ruleOffset);

		builder.AppendLine(rule.Next == Wire.None ? "  rule " + r : "  rule " + r + " then " + GroupName(rule.Next));

		if (rule.ConditionWords > 0)
		{
			builder.AppendLine("    when");
			try DumpStream(builder, chunk, rule.ConditionOffset, rule.ActionOffset, true);
		}

		builder.AppendLine("    do");
		try DumpStream(builder, chunk, rule.ActionOffset, rule.NextRuleOffset, false);

		ruleOffset = rule.NextRuleOffset;
	}

	return;
}

Error<void> DumpStream(StringBuilder builder, ScriptChunk chunk, int start, int end, bool isCondition)
{
	int offset = start;

	while (offset < end)
	{
		uint16 instruction = try chunk.ReadGroupWord(offset);
		uint8 op = Wire.InstructionOp(instruction);
		int length = Wire.InstructionLength(instruction);
		var operands = new uint16[length];

		for (var i = 0; i < length; i += 1)
			operands[i] = try chunk.ReadGroupWord(offset + 2 + i * 2);

		offset += 2 + length * 2;

		Optional<OpInfo> found = isCondition ? ConditionTable.ByOp((int)op) : ActionTable.ByOp((int)op);
		string text;

		if (found is OpInfo info)
		{
			text = FormatOperands(info, operands);
		}
		else
		{
			var parts = new string[length];

			for (var i = 0; i < length; i += 1)
				parts[i] = HexOrAny(operands[i]);

			text = "op#" + Hex((int)op, 2) + "(" + string.Join(", ", parts) + ")";
		}

		string prefix = isCondition && Wire.InstructionNeg(instruction) ? "not " : "";
		string suffix = isCondition && Wire.InstructionOrNext(instruction) ? " or" : "";

		builder.AppendLine("      " + prefix + text + suffix);
	}

	return;
}

string FormatOperands(OpInfo info, uint16[] words)
{
	var parts = List<string>.Create();
	int index = 0;

	foreach (var spec in info.Operands)
	{
		if (index + spec.Words() > words.Length)
			break;

		parts.Add(FormatOperand(spec, words, index));
		index += spec.Words();
	}

	while (index < words.Length)
	{
		parts.Add(words[index].ToString());
		index += 1;
	}

	return info.Name + "(" + JoinList(", ", parts) + ")";
}

string FormatOperand(OperandSpec spec, uint16[] words, int index)
{
	uint16 value = words[index];

	switch (spec.Kind)
	{
		case OperandKind.Int16:
			return ((int16)value).ToString();
		case OperandKind.Int32:
			return ((int)Wire.Combine(words[index], words[index + 1])).ToString();
		case OperandKind.FlagSlot:
		case OperandKind.VarSlot:
		case OperandKind.Var32Slot:
			return StateNamespaceName(Wire.SlotNamespace(value)).ToLower() + "[" + Wire.SlotIndex(value) + "]";
		case OperandKind.Comparison:
			return (int)value < Comparisons.Length ? Comparisons[(int)value] : "cmp#" + value;
		case OperandKind.Target:
			if (value == 0)
				return "active";
			if (value == 1)
				return "any";
			if (value == 2)
				return "all";
			if (value == 3)
				return "leader";
			if (value >= 4 && value <= 9)
				return "slot" + ((int)value - 3);
			return value.ToString();
		case OperandKind.Direction:
			if (value == 0)
				return "up";
			if (value == 1)
				return "right";
			if (value == 2)
				return "down";
			if (value == 3)
				return "left";
			if (value == 0xFF)
				return "keep/random";
			return value.ToString();
		case OperandKind.Entity:
			return value == Wire.None ? "party" : "entity " + value;
		case OperandKind.Pos:
			return words[index] == Wire.Here && words[index + 1] == Wire.Here ? "here" : "(" + words[index] + ", " + words[index + 1] + ")";
		case OperandKind.TileRef:
			return Wire.IsRelativeTile(value) ? SignedText(Wire.RelativeTileDelta(value)) : "#" + value;
		case OperandKind.Symbol:
			return SymbolKinds.Prefix(spec.Symbol) + ".#" + value;
		case OperandKind.Node:
			return "node " + value;
		case OperandKind.Custom:
			return "event " + value;
		default:
			return value.ToString();
	}
}

string GroupName(uint16 reference)
{
	if (reference == Wire.None)
		return "none";

	return Wire.IsLocalGroup(reference) ? "local group " + Wire.GroupIndex(reference) : "global group " + Wire.GroupIndex(reference);
}

string HexOrAny(uint16 value)
{
	return value == Wire.None ? "any" : value.ToString();
}
