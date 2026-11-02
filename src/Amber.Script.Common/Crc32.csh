namespace Amber.Script.Common;

using System;

uint32[] Crc32Table = BuildCrc32Table();

uint32[] BuildCrc32Table()
{
	var result = new uint32[256];

	for (uint32 i = 0; i < 256; i += 1)
	{
		uint32 entry = i;

		for (var bit = 0; bit < 8; bit += 1)
			entry = (entry & 1) != 0 ? 0xEDB88320 ^ (entry >> 1) : entry >> 1;

		result[(int)i] = entry;
	}

	return result;
}

/// CRC-32 (IEEE 802.3) for state hashes of golden traces. A value type: pass it with ref to add to it elsewhere.
struct Crc32
{
	uint32 _value;

	static Crc32 Create()
	{
		return Crc32 { _value = 0xFFFFFFFF };
	}

	uint32 Value()
	{
		return _value ^ 0xFFFFFFFF;
	}

	void Add(uint8[] data)
	{
		if (data == null)
			return;

		AddRange(data, 0, data.Length);
	}

	void AddRange(uint8[] data, int start, int count)
	{
		for (var i = start; i < start + count; i += 1)
			_value = Crc32Table[(int)((_value ^ (uint32)data[i]) & 0xFF)] ^ (_value >> 8);
	}

	void AddByte(uint8 value)
	{
		_value = Crc32Table[(int)((_value ^ (uint32)value) & 0xFF)] ^ (_value >> 8);
	}

	void AddWord(uint16 word)
	{
		AddByte((uint8)(word >> 8));
		AddByte((uint8)(word & 0xFF));
	}

	void AddDword(uint32 dword)
	{
		AddWord(Wire.High(dword));
		AddWord(Wire.Low(dword));
	}
}

/// The CRC-32 of the bytes.
uint32 Crc32Of(uint8[] data)
{
	var crc = Crc32.Create();

	crc.Add(data);

	return crc.Value();
}
