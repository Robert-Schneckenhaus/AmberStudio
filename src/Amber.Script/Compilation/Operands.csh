// Pass B: operands, slot lookup and symbol resolution.

namespace Amber.Script.Compilation;

using System;
using Amber.Base;
using Amber.Script.Common;
using Amber.Script.Syntax;

/// The words of the operands of an instruction, or no value after an error.
Optional<uint16[]> CompileOperands(Compiler c, CompileContext ctx, OpInfo info, ArgNode[] args, SourceLocation location)
{
	var words = List<uint16>.Create();
	int argIndex = 0;

	foreach (var spec in info.Operands)
	{
		if (argIndex >= args.Length)
		{
			c.Diagnostics.Error("E003", "'" + info.Name + "' is missing argument '" + spec.Name + "'.", location);

			return null;
		}

		if (!CompileOperand(c, ctx, spec, args, ref argIndex, words))
			return null;
	}

	if (info.IsVariadic())
	{
		int countWordIndex = 0;

		for (var i = 0; i < info.CountOperand; i += 1)
			countWordIndex += info.Operands[i].Words();

		int expected = (int)words.Get(countWordIndex);
		int remaining = args.Length - argIndex;

		if (remaining != expected)
		{
			string code = info.Name == "push_screen" || info.Name == "replace_screen" ? "E014" : "E003";

			c.Diagnostics.Error(code, "'" + info.Name + "' announces " + expected + " trailing argument(s) but has " + remaining + ".", location);

			return null;
		}

		while (argIndex < args.Length)
		{
			var arg = ResolveArgument(args[argIndex], ctx.Env);

			argIndex += 1;

			switch (arg.Kind)
			{
				case ArgKind.Int:
				case ArgKind.Rel:
				{
					if (TryInteger(c, arg, 0, 0xFFFF, "argument") is int64 value)
					{
						words.Add((uint16)value);
						break;
					}

					return null;
				}
				case ArgKind.Symbol:
				{
					if (TryResolveAnySymbol(c, ctx, arg) is uint16 id)
					{
						words.Add(id);
						break;
					}

					return null;
				}
				default:
					c.Diagnostics.Error("E003", "Unexpected argument in '" + info.Name + "'.", arg.Location);

					return null;
			}
		}
	}
	else if (argIndex < args.Length)
	{
		c.Diagnostics.Error("E003", "'" + info.Name + "' takes " + argIndex + " argument(s) but got " + args.Length + ".", args[argIndex].Location);

		return null;
	}

	var result = words.ToArray();

	if (result == null)
		return new uint16[0];

	return result;
}

bool CompileOperand(Compiler c, CompileContext ctx, OperandSpec spec, ArgNode[] args, ref int argIndex, List<uint16> words)
{
	var arg = ResolveArgument(args[argIndex], ctx.Env);

	argIndex += 1;

	switch (spec.Kind)
	{
		case OperandKind.Word:
		{
			if (TryInteger(c, arg, 0, 0xFFFF, spec.Name) is int64 value)
			{
				words.Add((uint16)value);

				return true;
			}

			return false;
		}
		case OperandKind.Int16:
		{
			if (TryInteger(c, arg, (int64)int16.MinValue, 0xFFFF, spec.Name) is int64 value)
			{
				words.Add((uint16)(value & 0xFFFF));

				return true;
			}

			return false;
		}
		case OperandKind.Int32:
		{
			if (TryInteger32(c, ctx, arg, spec.Name) is int64 value)
			{
				uint32 bits = (uint32)(value & 0xFFFFFFFF);

				words.Add(Wire.High(bits));
				words.Add(Wire.Low(bits));

				return true;
			}

			return false;
		}
		case OperandKind.FlagSlot:
			return TrySlot(c, ctx, arg, SlotKind.Flag, words);
		case OperandKind.VarSlot:
			return TrySlot(c, ctx, arg, SlotKind.Var, words);
		case OperandKind.Var32Slot:
			return TrySlot(c, ctx, arg, SlotKind.Var32, words);
		case OperandKind.Comparison:
			c.Diagnostics.Error("E003", "Comparison operands can only be written with comparison operators (result == 1).", arg.Location);

			return false;
		case OperandKind.Target:
		case OperandKind.Direction:
		case OperandKind.Modifier:
		case OperandKind.MoveSource:
		case OperandKind.FlagMode:
			return TryKeyword(c, arg, spec, words);
		case OperandKind.Entity:
			return TryEntity(c, ctx, arg, words);
		case OperandKind.Pos:
		{
			switch (arg.Kind)
			{
				case ArgKind.Here:
				{
					if (!spec.AllowHere)
					{
						c.Diagnostics.Error("E003", "'here' is not allowed for '" + spec.Name + "'.", arg.Location);

						return false;
					}

					if (ctx.HasGroup)
						ctx.UsesHere.Set(true);

					words.Add(Wire.Here);
					words.Add(Wire.Here);

					return true;
				}
				case ArgKind.Pos:
					words.Add((uint16)arg.Value);
					words.Add((uint16)arg.Y);

					return true;
				case ArgKind.Int:
				{
					if (argIndex >= args.Length)
					{
						c.Diagnostics.Error("E003", "A position needs x and y.", arg.Location);

						return false;
					}

					var second = ResolveArgument(args[argIndex], ctx.Env);

					argIndex += 1;

					if (TryInteger(c, arg, 0, 0xFFFE, "x") is int64 x)
					{
						if (TryInteger(c, second, 0, 0xFFFE, "y") is int64 y)
						{
							words.Add((uint16)x);
							words.Add((uint16)y);

							return true;
						}
					}

					return false;
				}
				default:
					break;
			}

			c.Diagnostics.Error("E003", "Expected a position (x, y) or 'here'.", arg.Location);

			return false;
		}
		case OperandKind.TileRef:
			return TryTile(c, ctx, arg, words);
		case OperandKind.Symbol:
			return TrySymbolOperand(c, ctx, spec, arg, words);
		case OperandKind.Node:
			return TryNode(c, ctx, arg, words);
		case OperandKind.Custom:
		{
			if (arg.Kind != ArgKind.Ident)
			{
				c.Diagnostics.Error("E003", "Expected the name of a custom event.", arg.Location);

				return false;
			}

			words.Add(CustomEventId(c, arg.Name));

			return true;
		}
		default:
			return false;
	}
}

uint16 CustomEventId(Compiler c, string name)
{
	if (c.CustomEvents.TryGet(name) is uint16 id)
		return id;

	uint16 next = (uint16)c.CustomEvents.Count();

	c.CustomEvents.Set(name, next);

	return next;
}

/// The integer value of the argument if it is a number in the range (C#: TryInteger with out value).
Optional<int64> TryInteger(Compiler c, ArgNode arg, int64 min, int64 max, string what)
{
	if (arg.Kind != ArgKind.Int && arg.Kind != ArgKind.Rel)
	{
		c.Diagnostics.Error("E003", "Expected a number for '" + what + "'.", arg.Location);

		return null;
	}

	int64 value = arg.Value;

	if (value == int64.MinValue)
	{
		c.Diagnostics.Error("E003", "Expected a number for '" + what + "'.", arg.Location);

		return null;
	}

	if (value < min || value > max)
	{
		c.Diagnostics.Error("E003", "Value " + value + " of '" + what + "' is out of range (" + min + ".." + max + ").", arg.Location);

		return null;
	}

	return value;
}

Optional<int64> TryInteger32(Compiler c, CompileContext ctx, ArgNode arg, string what)
{
	if (arg.Kind == ArgKind.Symbol)
	{
		if (TryResolveAnySymbol(c, ctx, arg) is uint16 id)
			return (int64)id;

		return null;
	}

	return TryInteger(c, arg, (int64)int.MinValue, (int64)uint.MaxValue, what);
}

bool TryKeyword(Compiler c, ArgNode arg, OperandSpec spec, List<uint16> words)
{
	if (arg.Kind == ArgKind.Ident)
	{
		if (KeywordConstants.Get(spec.Kind, arg.Name) is uint16 value)
		{
			words.Add(value);

			return true;
		}

		c.Diagnostics.Error("E001", "Unknown value '" + arg.Name + "' for '" + spec.Name + "'.", arg.Location);

		return false;
	}

	if (arg.Kind == ArgKind.Int && arg.Value >= 0 && arg.Value <= 0xFFFF)
	{
		words.Add((uint16)arg.Value);

		return true;
	}

	c.Diagnostics.Error("E003", "Expected a keyword for '" + spec.Name + "'.", arg.Location);

	return false;
}

bool TryEntity(Compiler c, CompileContext ctx, ArgNode arg, List<uint16> words)
{
	string name = null;

	if (arg.Kind == ArgKind.Ident)
		name = arg.Name;
	else if (arg.IsSymbolWithPrefix("E"))
		name = arg.Name;

	if (arg.Kind == ArgKind.Int && arg.Value >= 0 && arg.Value <= 0xFFFF)
	{
		words.Add((uint16)arg.Value);

		return true;
	}

	if (name == null)
	{
		c.Diagnostics.Error("E003", "Expected an entity name.", arg.Location);

		return false;
	}

	if (KeywordConstants.Get(OperandKind.Entity, name) is uint16 party)
	{
		words.Add(party);

		return true;
	}

	if (ctx.Scope.Entities.TryGet(name) is int id)
	{
		words.Add((uint16)id);

		return true;
	}

	c.Diagnostics.Error("E001", "Unknown entity '" + name + "' (entities are local to their map).", arg.Location);

	return false;
}

bool TryTile(Compiler c, CompileContext ctx, ArgNode arg, List<uint16> words)
{
	if (arg.Kind == ArgKind.Rel)
		return AddRelativeTile(c, arg.Value, arg.Location, words);

	if (arg.Kind == ArgKind.Int && arg.Signed && arg.Value < 0)
		return AddRelativeTile(c, arg.Value, arg.Location, words);

	if (arg.Kind == ArgKind.Int)
	{
		if (arg.Value < 0 || arg.Value > 0x7FFF)
		{
			c.Diagnostics.Error("E003", "Tile ID " + arg.Value + " is out of range (0..32767).", arg.Location);

			return false;
		}

		words.Add((uint16)arg.Value);

		return true;
	}

	if (arg.IsSymbolWithPrefix("TILE"))
	{
		if (TryResolveSymbol(c, ctx, arg, SymbolKind.Tile) is uint16 id)
		{
			if (id > 0x7FFF)
			{
				c.Diagnostics.Error("E003", "Tile ID " + id + " is out of range (0..32767).", arg.Location);

				return false;
			}

			words.Add(id);

			return true;
		}

		return false;
	}

	c.Diagnostics.Error("E003", "Expected a tile (TILE.name, a number, or +n / -n for a relative tile).", arg.Location);

	return false;
}

bool AddRelativeTile(Compiler c, int64 delta, SourceLocation location, List<uint16> words)
{
	if (delta < -0x4000 || delta > 0x3FFF)
	{
		c.Diagnostics.Error("E003", "Relative tile " + delta + " is out of range (-16384..16383).", location);

		return false;
	}

	words.Add(Wire.RelativeTile((int)delta));

	return true;
}

bool TryNode(Compiler c, CompileContext ctx, ArgNode arg, List<uint16> words)
{
	if (arg.Kind == ArgKind.Int && arg.Value >= 0 && arg.Value <= 0xFFFF)
	{
		words.Add((uint16)arg.Value);

		return true;
	}

	if (arg.Kind != ArgKind.Ident)
	{
		c.Diagnostics.Error("E003", "Expected a node name.", arg.Location);

		return false;
	}

	if (ctx.Scope.Nodes.TryGet(arg.Name) is int id)
	{
		words.Add((uint16)id);

		return true;
	}

	if (ctx.Scope.Kind == ScopeKind.Screen && c.Options.LenientSymbols && c.Options.Screens.Get(ctx.Scope.Name) == null)
	{
		int next = ctx.Scope.Nodes.Count();

		ctx.Scope.Nodes.Set(arg.Name, next);
		words.Add((uint16)next);

		return true;
	}

	c.Diagnostics.Error("E001", "Unknown node '" + arg.Name + "'.", arg.Location);

	return false;
}

bool TrySymbolOperand(Compiler c, CompileContext ctx, OperandSpec spec, ArgNode arg, List<uint16> words)
{
	if (spec.Symbol == SymbolKind.Routine)
	{
		if (arg.Kind != ArgKind.Ident)
		{
			c.Diagnostics.Error("E003", "Expected the name of a routine.", arg.Location);

			return false;
		}

		if (ctx.Scope.Routines.TryGet(arg.Name) is int routine)
		{
			words.Add((uint16)routine);

			return true;
		}

		c.Diagnostics.Error("E001", "Unknown routine '" + arg.Name + "' (routines are local to their map).", arg.Location);

		return false;
	}

	if (arg.Kind == ArgKind.Symbol)
	{
		if (TryResolveSymbol(c, ctx, arg, spec.Symbol) is uint16 id)
		{
			words.Add(id);

			return true;
		}

		return false;
	}

	if (arg.Kind == ArgKind.Int && arg.Value >= 0 && arg.Value <= 0xFFFF)
	{
		words.Add((uint16)arg.Value);

		return true;
	}

	c.Diagnostics.Error("E003", "Expected a " + SymbolKinds.Prefix(spec.Symbol) + ".name symbol for '" + spec.Name + "'.", arg.Location);

	return false;
}

Optional<uint16> TryResolveAnySymbol(Compiler c, CompileContext ctx, ArgNode symbol)
{
	if (SymbolKinds.FromPrefix(symbol.Prefix) is SymbolKind kind)
		return TryResolveSymbol(c, ctx, symbol, kind);

	c.Diagnostics.Error("E001", "Unknown symbol prefix '" + symbol.Prefix + "'.", symbol.Location);

	return null;
}

Optional<uint16> TryResolveSymbol(Compiler c, CompileContext ctx, ArgNode symbol, SymbolKind expected)
{
	var found = SymbolKinds.FromPrefix(symbol.Prefix);

	if (found == null)
	{
		c.Diagnostics.Error("E001", "Unknown symbol prefix '" + symbol.Prefix + "'.", symbol.Location);

		return null;
	}

	var kind = SymbolKind.None;

	if (found is SymbolKind known)
		kind = known;

	if (expected != SymbolKind.None && kind != expected)
	{
		c.Diagnostics.Error("E003", "Expected a " + SymbolKinds.Prefix(expected) + ".name symbol but found " + symbol.Prefix + "." + symbol.Name + ".", symbol.Location);

		return null;
	}

	if (kind == SymbolKind.Entity)
	{
		if (ctx.Scope.Entities.TryGet(symbol.Name) is int entity)
			return (uint16)entity;

		c.Diagnostics.Error("E001", "Unknown entity '" + symbol.Name + "'.", symbol.Location);

		return null;
	}

	string name = kind == SymbolKind.Keyword ? symbol.Name.ToLower() : symbol.Name;

	if (c.Symbols.TryResolve(kind, name) is uint16 id)
		return id;

	if (kind == SymbolKind.Native)
		c.Diagnostics.Error("E013", "Unknown native function " + symbol.Prefix + "." + symbol.Name + ".", symbol.Location);
	else
		c.Diagnostics.Error("E001", "Unknown symbol " + symbol.Prefix + "." + symbol.Name + ".", symbol.Location);

	return null;
}

bool TrySlot(Compiler c, CompileContext ctx, ArgNode arg, SlotKind kind, List<uint16> words)
{
	if (arg.Kind != ArgKind.Ident)
	{
		c.Diagnostics.Error("E003", "Expected the name of a " + SlotKindName(kind).ToLower() + ".", arg.Location);

		return false;
	}

	var info = new SlotInfo();
	var looked = TryLookupSlot(c, ctx, arg.Name);

	if (looked is SlotInfo existing)
	{
		info = existing;
	}
	else if (kind == SlotKind.Var && ctx.Scope.Kind == ScopeKind.Screen && c.Options.LenientSymbols && c.Options.Screens.Get(ctx.Scope.Name) == null)
	{
		var declared = DeclareSlot(c, ctx.Scope, SlotKind.Var, arg.Name, arg.Location);

		c.Diagnostics.Warning("W100", "No signature for screen '" + ctx.Scope.Name + "': '" + arg.Name + "' was declared as a screen variable.", arg.Location);

		if (declared is SlotInfo slot)
			info = slot;
		else
			return false;
	}
	else if (ctx.Scope.Kind == ScopeKind.Global && IsMapSlotName(c, arg.Name))
	{
		c.Diagnostics.Error("E007", "'" + arg.Name + "' is a map slot; global scripts cannot use map state.", arg.Location);

		return false;
	}
	else
	{
		c.Diagnostics.Error("E001", "Unknown " + SlotKindName(kind).ToLower() + " '" + arg.Name + "'.", arg.Location);

		return false;
	}

	if (info.Kind != kind)
	{
		c.Diagnostics.Error("E003", "'" + arg.Name + "' is a " + SlotKindName(info.Kind).ToLower() + ", not a " + SlotKindName(kind).ToLower() + ".", arg.Location);

		return false;
	}

	words.Add(info.Slot);

	return true;
}

/// True if a map declares a slot of this name.
bool IsMapSlotName(Compiler c, string name)
{
	foreach (var scope in c.AllScopes)
	{
		if (scope.Kind == ScopeKind.Map && scope.Slots.ContainsKey(name))
			return true;
	}

	return false;
}

Optional<SlotInfo> TryLookupSlot(Compiler c, CompileContext ctx, string name)
{
	if (ctx.Env.InstanceSlots.TryGet(name) is SlotInfo instance)
		return instance;

	if (ctx.Scope.Slots.TryGet(name) is SlotInfo local)
		return local;

	if (c.Global.Slots.TryGet(name) is SlotInfo global)
		return global;

	// t0..t7: the variables of the running thread (spec section 1.2, namespace "thread")
	if (name.Length == 2 && name[0] == 't' && name[1] >= '0' && name[1] <= '7')
		return SlotInfo { Kind = SlotKind.Var, Slot = Wire.Slot(StateNamespace.Thread, name[1] - '0') };

	return null;
}
