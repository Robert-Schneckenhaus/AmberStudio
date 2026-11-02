// Reading parts of a file without loading all of it (C#: FileStream with Seek). CShift's standard library has no seekable
// streams and a hand written extern for fseek is not portable (long is 32 bits on Windows), so a range is reached by
// reading and dropping the bytes in front of it.

namespace Amber.Base;

using System;
using System.Native;

/// The size of a file in bytes.
Error<int64> FileLength(string path)
{
	unsafe
	{
		void* file = fopen(path.CStr(), "rb".CStr());

		if (file == null)
			return error("cannot open file '" + path + "'", (int)ErrorKind.Io);

		var buffer = new uint8[65536];
		int64 length = 0;

		while (true)
		{
			uint64 count = fread(&buffer[0], 1, (nuint)buffer.Length, file);

			if (count == 0)
				break;

			length += (int64)count;
		}

		fclose(file);

		return length;
	}
}

/// The 'count' bytes of the file at 'offset'.
Error<uint8[]> ReadFileRange(string path, int64 offset, int count)
{
	unsafe
	{
		void* file = fopen(path.CStr(), "rb".CStr());

		if (file == null)
			return error("cannot open file '" + path + "'", (int)ErrorKind.Io);

		var buffer = new uint8[65536];
		int64 skipped = 0;

		while (skipped < offset)
		{
			int64 wanted = offset - skipped;

			if (wanted > (int64)buffer.Length)
				wanted = (int64)buffer.Length;

			uint64 read = fread(&buffer[0], 1, (nuint)wanted, file);

			if (read == 0)
			{
				fclose(file);

				return error("the file '" + path + "' ends before offset " + offset + ".", (int)ErrorKind.Io);
			}

			skipped += (int64)read;
		}

		var result = new uint8[count];
		int filled = 0;

		while (filled < count)
		{
			uint64 read = fread(&result[filled], 1, (nuint)(count - filled), file);

			if (read == 0)
				break;

			filled += (int)read;
		}

		fclose(file);

		if (filled < count)
			return error("the file '" + path + "' ends inside the requested range.", (int)ErrorKind.Io);

		return result;
	}
}
