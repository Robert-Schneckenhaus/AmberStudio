// Encoding helpers for the wire format (spec sections 1.3 and 6).

namespace Amber.Script.Common.Wire;

using System;

/// NONE value for IDs and group references.
const uint16 None = 0xFFFF;

/// Value of both coordinate words for "here" (spec section 1.4).
const uint16 Here = 0xFFFF;

/// Bit 15 of a tile reference marks a relative tile.
const uint16 RelativeTileFlag = 0x8000;

const int MaxSlotIndex = 0x3FFF;
const int MaxLocalGroupIndex = 0x7FFE;
const int MaxOperandWords = 63;

uint16 Slot(StateNamespace ns, int index)
{
	return (uint16)(((int)ns << 14) | (index & MaxSlotIndex));
}

StateNamespace SlotNamespace(uint16 slot)
{
	return (StateNamespace)(slot >> 14);
}

int SlotIndex(uint16 slot)
{
	return (int)slot & MaxSlotIndex;
}

uint16 GlobalGroup(int index)
{
	return (uint16)index;
}

uint16 LocalGroup(int index)
{
	return (uint16)(0x8000 | index);
}

bool IsLocalGroup(uint16 group)
{
	return group != None && ((int)group & 0x8000) != 0;
}

int GroupIndex(uint16 group)
{
	return (int)group & 0x7FFF;
}

uint16 RelativeTile(int delta)
{
	return (uint16)((int)RelativeTileFlag | (delta & 0x7FFF));
}

/// Sign-extends the 15 bit delta of a relative tile reference.
int RelativeTileDelta(uint16 tile)
{
	return ((int)tile & 0x4000) != 0 ? ((int)tile & 0x7FFF) - 0x8000 : ((int)tile & 0x7FFF);
}

bool IsRelativeTile(uint16 tile)
{
	return ((int)tile & (int)RelativeTileFlag) != 0;
}

/// Builds an instruction word: [op:8][len:6][or_next:1][neg:1]. The operand count must be 0..63.
uint16 Instruction(uint8 op, int operandWords, bool orNext, bool neg)
{
	if (operandWords < 0 || operandWords > MaxOperandWords)
		Environment.Panic("operandWords is out of range");

	return (uint16)(((int)op << 8) | (operandWords << 2) | (orNext ? 2 : 0) | (neg ? 1 : 0));
}

uint8 InstructionOp(uint16 instruction)
{
	return (uint8)(instruction >> 8);
}

int InstructionLength(uint16 instruction)
{
	return ((int)instruction >> 2) & 0x3F;
}

bool InstructionOrNext(uint16 instruction)
{
	return ((int)instruction & 2) != 0;
}

bool InstructionNeg(uint16 instruction)
{
	return ((int)instruction & 1) != 0;
}

uint16 High(uint32 value)
{
	return (uint16)(value >> 16);
}

uint16 Low(uint32 value)
{
	return (uint16)(value & 0xFFFF);
}

uint32 Combine(uint16 high, uint16 low)
{
	return ((uint32)high << 16) | (uint32)low;
}
