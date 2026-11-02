// Pass B: compiles pending groups and bindings to the intermediate representation.

namespace Amber.Script.Compilation;

using System;
using Amber.Base;
using Amber.Script.Common;
using Amber.Script.Syntax;

void CompileScope(Compiler c, ScopeContext scope)
{
	foreach (var pending in scope.Groups)
		scope.Output.Groups.Add(CompileGroup(c, scope, pending));

	foreach (var binding in scope.Bindings)
	{
		if (CompileBinding(c, scope, binding) is IrBinding compiled)
			scope.Output.Bindings.Add(compiled);
	}
}

IrGroup CompileGroup(Compiler c, ScopeContext scope, PendingGroup pending)
{
	var group = IrGroup.Create(pending.Name, pending.Mode, pending.Location);
	var ctx = CompileContext { Scope = scope, Env = pending.Env, HasGroup = true, UsesHere = Cell<bool>.Of(false) };

	group.Origin = pending.Origin;

	for (var i = 0; i < pending.Rules.Length; i += 1)
		group.Rules.Add(CompileRule(c, ctx, pending, pending.Rules[i], i));

	group.UsesHere = ctx.UsesHere.Get();

	return group;
}

IrRule CompileRule(Compiler c, CompileContext ctx, PendingGroup pending, RuleNode rule, int ruleIndex)
{
	var ir = IrRule.Create();

	if (rule.Condition is ConditionNode condition)
		ir.Conditions.AddRange(LowerCondition(c, ctx, condition).ToArray());

	if (rule.Once)
	{
		// "once" is sugar for a private flag: not flag(x) as first clause, set_flag(x) as first action
		var flag = AllocateSlot(c, ctx.Scope, SlotKind.Flag, "__once_" + pending.Name + "_" + ruleIndex, rule.Location);

		ir.Conditions.Insert(0, IrInstruction.Create((uint8)ConditionOp.Flag, new uint16[] { flag.Slot }, false, true));
		ir.Actions.Add(IrInstruction.Create((uint8)ActionOp.SetFlag, new uint16[] { flag.Slot }, false, false));
	}

	foreach (var action in rule.Actions)
		CompileAction(c, ctx, action, ir.Actions);

	if (rule.Then != null)
	{
		string name = rule.Then;

		if (ctx.Env.Params.TryGet(rule.Then) is ArgNode replacement)
		{
			if (replacement.Kind == ArgKind.Ident)
				name = replacement.Name;
		}

		ir.NextName = name;

		if (TryGroupReference(c, ctx.Scope, name, rule.ThenLocation) is uint16 reference)
			ir.Next = reference;
	}

	return ir;
}

Optional<uint16> TryGroupReference(Compiler c, ScopeContext scope, string name, SourceLocation location)
{
	if (scope.NamedGroups.TryGet(name) is PendingGroup local)
		return scope.Kind == ScopeKind.Global ? Wire.GlobalGroup(local.Index) : Wire.LocalGroup(local.Index);

	if (c.Global.NamedGroups.TryGet(name) is PendingGroup globalGroup)
		return Wire.GlobalGroup(globalGroup.Index);

	c.Diagnostics.Error("E004", "Group '" + name + "' does not exist.", location);

	return null;
}

List<IrInstruction> LowerCondition(Compiler c, CompileContext ctx, ConditionNode condition)
{
	var flat = List<IrInstruction>.Create();

	foreach (var clause in LowerConditionCnf(c, ctx, condition))
	{
		for (var i = 0; i < clause.Count(); i += 1)
		{
			var instruction = clause.Get(i);

			instruction.OrNext = i < clause.Count() - 1;
			flat.Add(instruction);
		}
	}

	return flat;
}

List<List<IrInstruction>> LowerConditionCnf(Compiler c, CompileContext ctx, ConditionNode condition)
{
	var clauses = List<List<IrInstruction>>.Create();

	foreach (var clause in condition.Clauses)
	{
		if (clause.Literals.Length == 1)
		{
			if (LowerLiteral(c, ctx, clause.Literals[0]) is List<List<IrInstruction>> single)
			{
				foreach (var part in single)
					clauses.Add(part);
			}

			continue;
		}

		var merged = List<IrInstruction>.Create();

		foreach (var literal in clause.Literals)
		{
			if (LowerLiteral(c, ctx, literal) is List<List<IrInstruction>> cnf)
			{
				if (cnf.Count() != 1)
				{
					c.Diagnostics.Error("E021", "A condition fragment with several clauses cannot be used inside 'or'.", literal.Location);

					continue;
				}

				foreach (var instruction in cnf.Get(0))
					merged.Add(instruction);
			}
		}

		if (merged.Count() > 0)
			clauses.Add(merged);
	}

	return clauses;
}

/// A condition as conjunctive normal form with a single literal.
List<List<IrInstruction>> SingleLiteral(IrInstruction instruction)
{
	var clause = List<IrInstruction>.Create();
	var cnf = List<List<IrInstruction>>.Create();

	clause.Add(instruction);
	cnf.Add(clause);

	return cnf;
}

Optional<List<List<IrInstruction>>> LowerLiteral(Compiler c, CompileContext ctx, LiteralNode literal)
{
	switch (literal.Atom.Kind)
	{
		case AtomKind.Call:
		{
			var call = literal.Atom.Call;

			if (FindPreset(c, ctx.Scope, call.Name) is FoundPreset found)
			{
				if (found.Preset.Kind == PresetKind.Condition)
				{
					MarkPresetUsed(c, found.Owner, call.Name);

					if (ExpandConditionFragment(c, ctx, found.Preset, call) is List<List<IrInstruction>> cnf)
					{
						if (!literal.Not)
							return cnf;

						if (cnf.Count() != 1 || cnf.Get(0).Count() != 1)
						{
							c.Diagnostics.Error("E021", "'not " + call.Name + "' is not possible because the fragment consists of several literals.", literal.Location);

							return null;
						}

						var negated = cnf.Get(0).Get(0);

						negated.Neg = !negated.Neg;

						return SingleLiteral(negated);
					}

					return null;
				}
			}

			if (ConditionTable.ByName(call.Name) is OpInfo info)
			{
				var args = call.Args;

				// inside entities "near(range)" refers to the entity itself
				if (info.Op == (uint8)ConditionOp.Near && args.Length == 1 && ctx.Env.ImplicitEntity != null)
					args = new ArgNode[] { ArgNode.Ident(call.Location, ctx.Env.ImplicitEntity), args[0] };

				if (CompileOperands(c, ctx, info, args, call.Location) is uint16[] words)
					return SingleLiteral(IrInstruction.Create(info.Op, words, false, literal.Not));

				return null;
			}

			c.Diagnostics.Error("E001", "Unknown condition '" + call.Name + "'.", call.Location);

			return null;
		}
		default:
		{
			if (LowerCompare(c, ctx, literal.Atom, literal.Not) is IrInstruction instruction)
				return SingleLiteral(instruction);

			return null;
		}
	}
}

/// An expansion context one preset deeper (the parameters of the preset, the rest from the caller).
ExpansionContext NestedEnv(ExpansionContext outer, PresetNode preset, Dictionary<string, ArgNode> parameters)
{
	var stack = List<string>.Create();

	foreach (var name in outer.Stack)
		stack.Add(name);

	stack.Add(preset.Name);

	return ExpansionContext
	{
		Params = parameters,
		InstanceSlots = outer.InstanceSlots,
		ImplicitEntity = outer.ImplicitEntity,
		Depth = outer.Depth + 1,
		Stack = stack
	};
}

Optional<List<List<IrInstruction>>> ExpandConditionFragment(Compiler c, CompileContext ctx, PresetNode preset, CallNode call)
{
	if (ContainsText(ctx.Env.Stack, preset.Name) || ctx.Env.Depth >= MaxPresetDepth)
	{
		c.Diagnostics.Error("E016", "Preset '" + preset.Name + "' is recursive or nested too deeply.", call.Location);

		return null;
	}

	if (BindPresetArguments(c, preset, call.Args, ctx.Env, call.Location) is Dictionary<string, ArgNode> parameters)
	{
		if (preset.ConditionBody is ConditionNode body)
			return LowerConditionCnf(c, ctx.WithEnv(NestedEnv(ctx.Env, preset, parameters)), body);
	}

	return null;
}

Optional<IrInstruction> LowerCompare(Compiler c, CompileContext ctx, AtomNode compare, bool neg)
{
	var left = ResolveArgument(compare.Left, ctx.Env);
	var right = ResolveArgument(compare.Right, ctx.Env);
	uint16 cmp = (uint16)compare.Comparison;

	if (left.Kind != ArgKind.Ident)
	{
		c.Diagnostics.Error("E003", "The left side of a comparison must be 'result', 'arg', 'gold', 'party_size' or a variable.", left.Location);

		return null;
	}

	string leftName = left.Name;

	if (leftName == "result" && TryLookupSlot(c, ctx, "result") == null)
		return CompareWithInt16(c, ctx, ConditionOp.Result, new uint16[] { cmp }, right, neg);

	if (leftName == "party_size" && TryLookupSlot(c, ctx, "party_size") == null)
		return CompareWithInt16(c, ctx, ConditionOp.PartySize, new uint16[] { cmp }, right, neg);

	if (leftName == "arg" && TryLookupSlot(c, ctx, "arg") == null)
		return CompareWithInt32(c, ctx, ConditionOp.Arg, new uint16[] { cmp }, right, neg);

	if (leftName == "gold" && TryLookupSlot(c, ctx, "gold") == null)
		return CompareWithInt32(c, ctx, ConditionOp.Gold, new uint16[] { cmp }, right, neg);

	if (TryLookupSlot(c, ctx, leftName) is SlotInfo slot)
	{
		switch (slot.Kind)
		{
			case SlotKind.Var:
			{
				if (right.Kind == ArgKind.Ident)
				{
					var words = List<uint16>.Create();

					words.Add(slot.Slot);
					words.Add(cmp);

					if (!TrySlot(c, ctx, right, SlotKind.Var, words))
						return null;

					return IrInstruction.Create((uint8)ConditionOp.VarVar, words.ToArray(), false, neg);
				}

				return CompareWithInt16(c, ctx, ConditionOp.Var, new uint16[] { slot.Slot, cmp }, right, neg);
			}
			case SlotKind.Var32:
				return CompareWithInt32(c, ctx, ConditionOp.Var32, new uint16[] { slot.Slot, cmp }, right, neg);
			default:
				break;
		}

		c.Diagnostics.Error("E003", "'" + leftName + "' is a flag; use flag(" + leftName + ").", left.Location);

		return null;
	}

	c.Diagnostics.Error("E001", "Unknown variable '" + leftName + "'.", left.Location);

	return null;
}

/// The prefix words followed by the extra words.
uint16[] Append(uint16[] prefix, uint16[] extra)
{
	var words = new uint16[prefix.Length + extra.Length];

	for (var i = 0; i < prefix.Length; i += 1)
		words[i] = prefix[i];

	for (var i = 0; i < extra.Length; i += 1)
		words[prefix.Length + i] = extra[i];

	return words;
}

Optional<IrInstruction> CompareWithInt16(Compiler c, CompileContext ctx, ConditionOp op, uint16[] prefix, ArgNode right, bool neg)
{
	if (TryInteger(c, right, (int64)int16.MinValue, 0xFFFF, "value") is int64 value)
		return IrInstruction.Create((uint8)op, Append(prefix, new uint16[] { (uint16)(value & 0xFFFF) }), false, neg);

	return null;
}

Optional<IrInstruction> CompareWithInt32(Compiler c, CompileContext ctx, ConditionOp op, uint16[] prefix, ArgNode right, bool neg)
{
	if (TryInteger32(c, ctx, right, "value") is int64 value)
	{
		uint32 bits = (uint32)(value & 0xFFFFFFFF);

		return IrInstruction.Create((uint8)op, Append(prefix, new uint16[] { Wire.High(bits), Wire.Low(bits) }), false, neg);
	}

	return null;
}

void CompileAction(Compiler c, CompileContext ctx, CallNode call, List<IrInstruction> output)
{
	if (ActionTable.ByName(call.Name) is OpInfo info)
	{
		if (CompileOperands(c, ctx, info, call.Args, call.Location) is uint16[] words)
			output.Add(IrInstruction.Create(info.Op, words, false, false));

		return;
	}

	if (FindPreset(c, ctx.Scope, call.Name) is FoundPreset found)
	{
		if (found.Preset.Kind == PresetKind.Action)
		{
			var preset = found.Preset;

			MarkPresetUsed(c, found.Owner, call.Name);

			if (ContainsText(ctx.Env.Stack, preset.Name) || ctx.Env.Depth >= MaxPresetDepth)
			{
				c.Diagnostics.Error("E016", "Preset '" + preset.Name + "' is recursive or nested too deeply.", call.Location);

				return;
			}

			if (BindPresetArguments(c, preset, call.Args, ctx.Env, call.Location) is Dictionary<string, ArgNode> parameters)
			{
				var inner = ctx.WithEnv(NestedEnv(ctx.Env, preset, parameters));

				foreach (var bodyCall in preset.ActionBody)
					CompileAction(c, inner, bodyCall, output);
			}

			return;
		}
	}

	c.Diagnostics.Error("E001", "Unknown action '" + call.Name + "'.", call.Location);
}

/// Triggers whose parameter may be left out (then it matches every value).
bool HasOptionalParameter(TriggerType type)
{
	switch (type)
	{
		case TriggerType.UseItem:
		case TriggerType.CastSpell:
		case TriggerType.Hour:
		case TriggerType.WeatherChange:
		case TriggerType.BattleEnd:
		case TriggerType.ItemGained:
		case TriggerType.MemberJoined:
		case TriggerType.MemberLeft:
		case TriggerType.Click:
		case TriggerType.RegionClick:
			return true;
		default:
			return false;
	}
}

Optional<IrBinding> CompileBinding(Compiler c, ScopeContext scope, PendingBinding binding)
{
	var found = TriggerTable.ByName(binding.TriggerName);

	if (found == null)
	{
		c.Diagnostics.Error("E001", "Unknown trigger '" + binding.TriggerName + "'.", binding.Location);

		return null;
	}

	var trigger = new TriggerInfo();

	if (found is TriggerInfo info)
		trigger = info;

	var ctx = CompileContext { Scope = scope, Env = binding.Env, HasGroup = false, UsesHere = Cell<bool>.Of(false) };
	var triggerScope = TriggerScope.Global;
	uint16 sx = 0;
	uint16 sy = 0;
	uint16 sw = 0;
	uint16 sh = 0;
	var args = binding.TriggerArgs;
	int argIndex = 0;

	if (binding.Place is BindingPlace place)
	{
		triggerScope = place.IsArea() ? TriggerScope.Area : TriggerScope.Tile;
		sx = (uint16)place.X;
		sy = (uint16)place.Y;

		if (place.Width is int64 width)
			sw = (uint16)width;

		if (place.Height is int64 height)
			sh = (uint16)height;
	}
	else if (binding.EntityName != null)
	{
		triggerScope = TriggerScope.Entity;
		sx = (uint16)scope.Entities.GetOrDefault(binding.EntityName, 0);
	}
	else if (scope.Kind == ScopeKind.Map)
	{
		triggerScope = TriggerScope.Map;
	}
	else if (scope.Kind == ScopeKind.Screen)
	{
		if (trigger.NodeFirst)
		{
			triggerScope = TriggerScope.Node;

			if (args.Length == 0)
			{
				c.Diagnostics.Error("E003", "'" + trigger.Name + "' needs the node as first argument.", binding.Location);

				return null;
			}

			var nodeWords = List<uint16>.Create();
			var nodeArg = ResolveArgument(args[argIndex], binding.Env);

			argIndex += 1;

			if (!TryNode(c, ctx, nodeArg, nodeWords))
				return null;

			sx = nodeWords.Get(0);
		}
		else
		{
			triggerScope = TriggerScope.Screen;
			sx = scope.ScreenId.Get();
		}
	}

	if (((int)trigger.Scopes & (int)ScopeFlag(triggerScope)) == 0)
	{
		c.Diagnostics.Error("E020", "Trigger '" + trigger.Name + "' is not allowed here (scope " + TriggerScopeName(triggerScope)
			+ "); check 'at'/'in' or the surrounding block.", binding.Location);

		return null;
	}

	uint16 p1 = 0;
	uint16 p2 = 0;

	if (!CompileTriggerParameter(c, ctx, trigger, trigger.P1, args, ref argIndex, ref p1, binding.Location))
		return null;

	if (!CompileTriggerParameter(c, ctx, trigger, trigger.P2, args, ref argIndex, ref p2, binding.Location))
		return null;

	if (argIndex < args.Length)
	{
		c.Diagnostics.Error("E003", "Trigger '" + trigger.Name + "' takes " + argIndex + " argument(s) but got " + args.Length + ".", binding.Location);

		return null;
	}

	if (TryGroupReference(c, scope, binding.GroupName, binding.Location) is uint16 group)
	{
		return IrBinding
		{
			Trigger = trigger.Type,
			Scope = triggerScope,
			Group = group,
			GroupName = binding.GroupName,
			P1 = p1,
			P2 = p2,
			Sx = sx,
			Sy = sy,
			Sw = sw,
			Sh = sh,
			Location = binding.Location,
			Origin = binding.Origin
		};
	}

	return null;
}

bool CompileTriggerParameter(Compiler c, CompileContext ctx, TriggerInfo trigger, Optional<OperandSpec> parameter, ArgNode[] args, ref int argIndex, ref uint16 value, SourceLocation location)
{
	value = 0;

	if (parameter is OperandSpec spec)
	{
		if (argIndex >= args.Length)
		{
			if (spec.Kind == OperandKind.FlagMode)
				return true;

			if (HasOptionalParameter(trigger.Type))
			{
				value = Wire.None;

				return true;
			}

			c.Diagnostics.Error("E003", "Trigger '" + trigger.Name + "' needs the argument '" + spec.Name + "'.", location);

			return false;
		}

		var words = List<uint16>.Create();

		if (!CompileOperand(c, ctx, spec, args, ref argIndex, words))
			return false;

		value = words.Get(0);
	}

	return true;
}
