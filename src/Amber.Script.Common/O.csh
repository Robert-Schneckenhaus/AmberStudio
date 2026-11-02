// Short factory functions for operand specs (used by the opcode tables).

namespace Amber.Script.Common.O;

OperandSpec Spec(string name, OperandKind kind)
{
	return OperandSpec { Name = name, Kind = kind, Symbol = SymbolKind.None, AllowHere = false };
}

OperandSpec Word(string name)
{
	return Spec(name, OperandKind.Word);
}

OperandSpec Int16(string name)
{
	return Spec(name, OperandKind.Int16);
}

OperandSpec Int32(string name)
{
	return Spec(name, OperandKind.Int32);
}

OperandSpec Flag()
{
	return Spec("flag", OperandKind.FlagSlot);
}

OperandSpec Flag(string name)
{
	return Spec(name, OperandKind.FlagSlot);
}

OperandSpec Var()
{
	return Spec("var", OperandKind.VarSlot);
}

OperandSpec Var(string name)
{
	return Spec(name, OperandKind.VarSlot);
}

OperandSpec Var32()
{
	return Spec("var", OperandKind.Var32Slot);
}

OperandSpec Cmp()
{
	return Spec("cmp", OperandKind.Comparison);
}

OperandSpec Target()
{
	return Spec("target", OperandKind.Target);
}

OperandSpec Dir()
{
	return Spec("dir", OperandKind.Direction);
}

OperandSpec Entity()
{
	return Spec("entity", OperandKind.Entity);
}

OperandSpec Pos(bool allowHere)
{
	return OperandSpec { Name = "pos", Kind = OperandKind.Pos, Symbol = SymbolKind.None, AllowHere = allowHere };
}

OperandSpec Tile()
{
	return Spec("tile", OperandKind.TileRef);
}

OperandSpec Sym(SymbolKind kind, string name)
{
	return OperandSpec { Name = name, Kind = OperandKind.Symbol, Symbol = kind, AllowHere = false };
}

OperandSpec Node()
{
	return Spec("node", OperandKind.Node);
}

OperandSpec Modifier()
{
	return Spec("modifier", OperandKind.Modifier);
}

OperandSpec MoveSource()
{
	return Spec("source", OperandKind.MoveSource);
}

OperandSpec Custom()
{
	return Spec("event", OperandKind.Custom);
}

OperandSpec FlagMode()
{
	return Spec("mode", OperandKind.FlagMode);
}

/// An opcode description (conditions and actions).
OpInfo Op(uint8 op, string name, OperandSpec[] operands, bool blocking, int countOperand)
{
	return OpInfo { Op = op, Name = name, Operands = operands, Blocking = blocking, CountOperand = countOperand };
}

OperandSpec[] NoOps()
{
	return new OperandSpec[0];
}

OperandSpec[] Ops(OperandSpec a)
{
	return new OperandSpec[] { a };
}

OperandSpec[] Ops(OperandSpec a, OperandSpec b)
{
	return new OperandSpec[] { a, b };
}

OperandSpec[] Ops(OperandSpec a, OperandSpec b, OperandSpec c)
{
	return new OperandSpec[] { a, b, c };
}

OperandSpec[] Ops(OperandSpec a, OperandSpec b, OperandSpec c, OperandSpec d)
{
	return new OperandSpec[] { a, b, c, d };
}

OperandSpec[] Ops(OperandSpec a, OperandSpec b, OperandSpec c, OperandSpec d, OperandSpec e)
{
	return new OperandSpec[] { a, b, c, d, e };
}
