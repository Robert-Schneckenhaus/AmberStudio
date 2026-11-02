// Writes the binary chunk layout of spec section 6 (big-endian, all offsets even).

namespace Amber.Script.Binary.ScriptEncoder;

using System;
using Amber.Base;
using Amber.Script.Common;
using Amber.Script.Compilation;

uint8[] EncodeGroups(List<IrGroup> groups)
{
	var words = List<uint16>.Create();
	var offsets = List<int>.Create();

	if (groups.Count() > Wire.MaxLocalGroupIndex)
		Environment.Panic("Too many groups in one chunk.");

	int headerBytes = ChunkLayout.GroupTableHeaderSize + groups.Count() * 4;

	foreach (var group in groups)
	{
		offsets.Add(headerBytes + words.Count() * 2);
		WriteGroup(words, group);
	}

	var data = new uint8[headerBytes + words.Count() * 2];

	WriteU16(data, 0, groups.Count());

	for (var i = 0; i < offsets.Count(); i += 1)
	{
		int entry = ChunkLayout.GroupTableHeaderSize + i * 4;

		WriteU16(data, entry, (int)Wire.High((uint32)offsets.Get(i)));
		WriteU16(data, entry + 2, (int)Wire.Low((uint32)offsets.Get(i)));
	}

	for (var i = 0; i < words.Count(); i += 1)
		WriteU16(data, headerBytes + i * 2, (int)words.Get(i));

	return data;
}

uint8[] EncodeBindings(List<IrBinding> bindings)
{
	var data = new uint8[ChunkLayout.BindingTableHeaderSize + bindings.Count() * ChunkLayout.BindingSize];

	WriteU16(data, 0, bindings.Count());

	for (var i = 0; i < bindings.Count(); i += 1)
	{
		var binding = bindings.Get(i);
		int offset = ChunkLayout.BindingTableHeaderSize + i * ChunkLayout.BindingSize;
		var values = new uint16[]
		{
			(uint16)(((int)binding.Trigger << 8) | (int)binding.Scope), binding.Group, binding.P1, binding.P2,
			binding.Sx, binding.Sy, binding.Sw, binding.Sh
		};

		for (var j = 0; j < values.Length; j += 1)
			WriteU16(data, offset + j * 2, (int)values[j]);
	}

	return data;
}

int InstructionWords(List<IrInstruction> instructions)
{
	int sum = 0;

	foreach (var instruction in instructions)
		sum += instruction.Words();

	return sum;
}

void WriteGroup(List<uint16> words, IrGroup group)
{
	int start = words.Count();

	words.Add((uint16)(((int)group.Mode << 8) | group.Rules.Count()));
	words.Add(0);

	foreach (var rule in group.Rules)
	{
		words.Add((uint16)InstructionWords(rule.Conditions));
		words.Add((uint16)InstructionWords(rule.Actions));
		words.Add(rule.Next);
		words.Add(0);

		foreach (var instruction in rule.Conditions)
			WriteInstruction(words, instruction);

		foreach (var instruction in rule.Actions)
			WriteInstruction(words, instruction);
	}

	words.Set(start + 1, (uint16)(words.Count() - start));
}

void WriteInstruction(List<uint16> words, IrInstruction instruction)
{
	words.Add(Wire.Instruction(instruction.Op, instruction.Operands.Length, instruction.OrNext, instruction.Neg));

	foreach (var operand in instruction.Operands)
		words.Add(operand);
}
