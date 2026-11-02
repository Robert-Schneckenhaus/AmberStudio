namespace Amber.Script.Common;

using System;
using Amber.Base;

/// One entry of a binding table (spec section 3).
struct BindingRecord
{
	TriggerType Trigger;
	TriggerScope Scope;
	uint16 Group;
	uint16 P1;
	uint16 P2;
	uint16 Sx;
	uint16 Sy;
	uint16 Sw;
	uint16 Sh;
}

/// Header of a group record. TotalWords: length of the whole record in words including the header. FirstRuleOffset: byte
/// offset of the first rule inside the groups block.
struct GroupHeader
{
	GroupMode Mode;
	int RuleCount;
	int TotalWords;
	int FirstRuleOffset;
}

/// Header of a rule record. Next: group reference of the follow-up group or Wire.None. The offsets are byte offsets inside
/// the groups block.
struct RuleHeader
{
	int ConditionWords;
	int ActionWords;
	uint16 Next;
	int ConditionOffset;
	int ActionOffset;
	int NextRuleOffset;
}

/// Read access to a group table and a binding table (spec section 6). Global scripts, map chunks and screen chunks all use
/// this layout. All reads are bounds checked and return an error (InvalidChunk) instead of reading outside of the chunk.
struct ScriptChunk
{
	uint8[] Groups;
	uint8[] Bindings;
	int GroupCount;
	int BindingCount;

	static Error<ScriptChunk> Create(uint8[] groups, uint8[] bindings)
	{
		var chunk = ScriptChunk { Groups = groups == null ? new uint8[0] : groups, Bindings = bindings == null ? new uint8[0] : bindings };

		if (chunk.Groups.Length > 0)
			chunk.GroupCount = (int)try ReadWord(chunk.Groups, 0);

		if (chunk.Bindings.Length > 0)
			chunk.BindingCount = (int)try ReadWord(chunk.Bindings, 0);

		if (chunk.Groups.Length > 0 && chunk.Groups.Length < ChunkLayout.GroupTableHeaderSize + chunk.GroupCount * 4)
			return error("Group table is truncated.", (int)ErrorKind.InvalidChunk);

		if (chunk.Bindings.Length > 0 && chunk.Bindings.Length < ChunkLayout.BindingTableHeaderSize + chunk.BindingCount * ChunkLayout.BindingSize)
			return error("Binding table is truncated.", (int)ErrorKind.InvalidChunk);

		return chunk;
	}

	/// A chunk written by the compiler (always valid); a broken one ends the program.
	static ScriptChunk Of(uint8[] groups, uint8[] bindings)
	{
		var result = Create(groups, bindings);

		if (result is ScriptChunk chunk)
			return chunk;

		Environment.Panic(result.Message);

		return new ScriptChunk();
	}

	static ScriptChunk Empty()
	{
		return ScriptChunk { Groups = new uint8[0], Bindings = new uint8[0] };
	}

	static Error<uint16> ReadWord(uint8[] data, int byteOffset)
	{
		if (byteOffset < 0 || data == null || byteOffset + 2 > data.Length)
			return error("Word read outside of the chunk at offset " + byteOffset + ".", (int)ErrorKind.InvalidChunk);

		return ReadU16(data, byteOffset);
	}

	Error<uint16> ReadGroupWord(int byteOffset)
	{
		return ReadWord(Groups, byteOffset);
	}

	Error<BindingRecord> ReadBinding(int index)
	{
		if (index < 0 || index >= BindingCount)
			return error("Binding " + index + " does not exist.", (int)ErrorKind.Argument);

		int offset = ChunkLayout.BindingTableHeaderSize + index * ChunkLayout.BindingSize;
		uint16 first = try ReadWord(Bindings, offset);

		return BindingRecord
		{
			Trigger = (TriggerType)(first >> 8),
			Scope = (TriggerScope)(first & 0xFF),
			Group = try ReadWord(Bindings, offset + 2),
			P1 = try ReadWord(Bindings, offset + 4),
			P2 = try ReadWord(Bindings, offset + 6),
			Sx = try ReadWord(Bindings, offset + 8),
			Sy = try ReadWord(Bindings, offset + 10),
			Sw = try ReadWord(Bindings, offset + 12),
			Sh = try ReadWord(Bindings, offset + 14)
		};
	}

	Error<int> GroupOffset(int index)
	{
		if (index < 0 || index >= GroupCount)
			return error("Group " + index + " does not exist.", (int)ErrorKind.InvalidChunk);

		int entry = ChunkLayout.GroupTableHeaderSize + index * 4;
		uint32 offset = Wire.Combine(try ReadWord(Groups, entry), try ReadWord(Groups, entry + 2));

		if (offset > (uint32)int.MaxValue || (offset & 1) != 0)
			return error("Group " + index + " has an invalid offset.", (int)ErrorKind.InvalidChunk);

		return (int)offset;
	}

	Error<GroupHeader> ReadGroupHeader(int index)
	{
		int offset = try GroupOffset(index);
		uint16 first = try ReadWord(Groups, offset);
		int totalWords = (int)try ReadWord(Groups, offset + 2);

		if (offset + totalWords * 2 > Groups.Length)
			return error("Group " + index + " exceeds the chunk.", (int)ErrorKind.InvalidChunk);

		return GroupHeader
		{
			Mode = (GroupMode)(first >> 8),
			RuleCount = (int)first & 0xFF,
			TotalWords = totalWords,
			FirstRuleOffset = offset + ChunkLayout.GroupHeaderSize
		};
	}

	Error<RuleHeader> ReadRuleHeader(int ruleOffset)
	{
		int conditionWords = (int)try ReadWord(Groups, ruleOffset);
		int actionWords = (int)try ReadWord(Groups, ruleOffset + 2);
		uint16 next = try ReadWord(Groups, ruleOffset + 4);
		int conditionOffset = ruleOffset + ChunkLayout.RuleHeaderSize;
		int actionOffset = conditionOffset + conditionWords * 2;
		int nextRuleOffset = actionOffset + actionWords * 2;

		if (nextRuleOffset > Groups.Length)
			return error("Rule exceeds the chunk.", (int)ErrorKind.InvalidChunk);

		return RuleHeader
		{
			ConditionWords = conditionWords,
			ActionWords = actionWords,
			Next = next,
			ConditionOffset = conditionOffset,
			ActionOffset = actionOffset,
			NextRuleOffset = nextRuleOffset
		};
	}
}
