namespace Amber.Runtime;

using System;
using Amber.Script.Common;

/// Sizes of the state arrays of a scope.
struct StateSizes
{
	int Flags;
	int Vars;
	int Vars32;

	static StateSizes Of(int flags, int vars, int vars32)
	{
		return StateSizes { Flags = flags, Vars = vars, Vars32 = vars32 };
	}

	bool Same(StateSizes other)
	{
		return Flags == other.Flags && Vars == other.Vars && Vars32 == other.Vars32;
	}
}

/// The flags, variables and 32 bit variables of one namespace instance (global, one map, one screen). A handle: copies
/// share the values.
struct StateStore
{
	uint8[] _flags;
	int16[] _vars;
	int32[] _vars32;
	StateSizes Sizes;

	static StateStore Create(StateSizes sizes)
	{
		return StateStore
		{
			_flags = new uint8[(sizes.Flags + 7) / 8],
			_vars = new int16[sizes.Vars],
			_vars32 = new int32[sizes.Vars32],
			Sizes = sizes
		};
	}

	bool IsValidFlag(int index)
	{
		return index >= 0 && index < Sizes.Flags;
	}

	bool IsValidVar(int index)
	{
		return index >= 0 && index < Sizes.Vars;
	}

	bool IsValidVar32(int index)
	{
		return index >= 0 && index < Sizes.Vars32;
	}

	bool GetFlag(int index)
	{
		return ((int)_flags[index >> 3] & (1 << (index & 7))) != 0;
	}

	/// Sets a flag and returns true if the value changed.
	bool SetFlag(int index, bool value)
	{
		if (GetFlag(index) == value)
			return false;

		if (value)
			_flags[index >> 3] = (uint8)((int)_flags[index >> 3] | (1 << (index & 7)));
		else
			_flags[index >> 3] = (uint8)((int)_flags[index >> 3] & ~(1 << (index & 7)));

		return true;
	}

	int16 GetVar(int index)
	{
		return _vars[index];
	}

	bool SetVar(int index, int16 value)
	{
		if (_vars[index] == value)
			return false;

		_vars[index] = value;

		return true;
	}

	int GetVar32(int index)
	{
		return _vars32[index];
	}

	bool SetVar32(int index, int value)
	{
		if (_vars32[index] == value)
			return false;

		_vars32[index] = value;

		return true;
	}

	/// Adds the state to a checksum: flag bytes, variables and 32 bit variables (big-endian).
	void AddToHash(ref Crc32 crc)
	{
		crc.Add(_flags);

		foreach (var value in _vars)
			crc.AddWord((uint16)value);

		foreach (var value in _vars32)
			crc.AddDword((uint32)value);
	}
}
