// PNG pictures (C#: StbImageSharp and StbImageWriteSharp): reading 8 and 16 bit grayscale, gray with alpha, RGB, RGBA and
// palette pictures (1 to 8 bits, also interlaced), writing RGBA and 8 bit palette pictures. The zlib data is packed with
// Amber.Base's deflate.

namespace Amber.Graphics;

using System;
using Amber.Base;
using Amber.Script.Common;

Error<Image> LoadPng(string path)
{
	var data = File.ReadAllBytes(path);

	if (data is uint8[] bytes)
	{
		var image = DecodePng(bytes);

		if (image is Image result)
			return result;

		return error(path + ": " + image.Message, (int)ErrorKind.InvalidData);
	}

	return error("cannot read '" + path + "': " + data.Message, (int)ErrorKind.Io);
}

Error<void> SavePng(string path, Image image)
{
	return File.WriteAllBytes(path, EncodePng(image));
}

Error<Image> DecodePng(uint8[] data)
{
	var picture = try DecodePngPicture(data);

	return picture.Rgba;
}

/// A decoded PNG: always the RGBA picture; for a palette PNG also the palette indices and the palette of the file.
struct PngPicture
{
	Image Rgba;
	/// One index per pixel (rows from the top), null unless the file is a palette PNG.
	uint8[] Indices;
	/// The entries of the PLTE chunk as RGBA (4 bytes each, alpha from tRNS), PaletteCount of them.
	uint8[] PaletteRgba;
	int PaletteCount;

	bool IsIndexed()
	{
		return Indices != null;
	}
}

Error<PngPicture> DecodePngPicture(uint8[] data)
{
	if (data.Length < 8 || data[0] != 0x89 || data[1] != (uint8)'P' || data[2] != (uint8)'N' || data[3] != (uint8)'G')
		return error("not a PNG file", (int)ErrorKind.InvalidData);

	int width = 0;
	int height = 0;
	int bitDepth = 0;
	int colorType = 0;
	int interlace = 0;
	var palette = new uint8[256 * 4];
	int paletteCount = 0;
	bool hasTransparentColor = false;
	int transparentGray = -1;
	int transparentRed = -1;
	int transparentGreen = -1;
	int transparentBlue = -1;
	var compressed = ByteWriter.Create();
	int position = 8;

	for (var i = 0; i < 256; i += 1)
		palette[i * 4 + 3] = 255;

	while (position + 8 <= data.Length)
	{
		int length = (int)ReadU32(data, position);
		string type = AsciiString(data, position + 4, 4);
		int start = position + 8;

		if (length < 0 || start + length + 4 > data.Length)
			return error("a chunk of the PNG file is truncated", (int)ErrorKind.InvalidData);

		if (type == "IHDR")
		{
			width = (int)ReadU32(data, start);
			height = (int)ReadU32(data, start + 4);
			bitDepth = (int)data[start + 8];
			colorType = (int)data[start + 9];
			interlace = (int)data[start + 12];
		}
		else if (type == "PLTE")
		{
			paletteCount = length / 3;

			for (var i = 0; i < paletteCount && i < 256; i += 1)
			{
				palette[i * 4] = data[start + i * 3];
				palette[i * 4 + 1] = data[start + i * 3 + 1];
				palette[i * 4 + 2] = data[start + i * 3 + 2];
			}
		}
		else if (type == "tRNS")
		{
			if (colorType == 3)
			{
				for (var i = 0; i < length && i < 256; i += 1)
					palette[i * 4 + 3] = data[start + i];
			}
			else if (colorType == 0 && length >= 2)
			{
				hasTransparentColor = true;
				transparentGray = (int)ReadU16(data, start);
			}
			else if (colorType == 2 && length >= 6)
			{
				hasTransparentColor = true;
				transparentRed = (int)ReadU16(data, start);
				transparentGreen = (int)ReadU16(data, start + 2);
				transparentBlue = (int)ReadU16(data, start + 4);
			}
		}
		else if (type == "IDAT")
			compressed.BytesRange(data, start, length);
		else if (type == "IEND")
			break;

		position = start + length + 4;
	}

	if (width <= 0 || height <= 0)
		return error("the PNG file has no header", (int)ErrorKind.InvalidData);

	int channels = colorType == 0 ? 1 : colorType == 2 ? 3 : colorType == 3 ? 1 : colorType == 4 ? 2 : colorType == 6 ? 4 : 0;

	if (channels == 0 || (bitDepth != 1 && bitDepth != 2 && bitDepth != 4 && bitDepth != 8 && bitDepth != 16))
		return error("unsupported PNG color type " + colorType + " with " + bitDepth + " bits", (int)ErrorKind.InvalidData);

	var zlib = compressed.ToArray();

	if (zlib.Length < 6)
		return error("the PNG file has no picture data", (int)ErrorKind.InvalidData);

	int bitsPerPixel = channels * bitDepth;
	int bytesPerPixel = bitsPerPixel < 8 ? 1 : bitsPerPixel / 8;
	int expected = 0;

	for (var pass = 0; pass < (interlace == 1 ? 7 : 1); pass += 1)
	{
		int passWidth = interlace == 1 ? PassSize(width, pass, true) : width;
		int passHeight = interlace == 1 ? PassSize(height, pass, false) : height;

		if (passWidth > 0 && passHeight > 0)
			expected += passHeight * (1 + (passWidth * bitsPerPixel + 7) / 8);
	}

	var raw = try InflateRaw(Slice(zlib, 2, zlib.Length - 2), expected + 1);

	if (raw.Length < expected)
		return error("the picture data of the PNG file is truncated", (int)ErrorKind.InvalidData);

	var image = Image.Create(width, height);
	uint8[] indices = colorType == 3 ? new uint8[width * height] : null;
	int offset = 0;

	for (var pass = 0; pass < (interlace == 1 ? 7 : 1); pass += 1)
	{
		int passWidth = interlace == 1 ? PassSize(width, pass, true) : width;
		int passHeight = interlace == 1 ? PassSize(height, pass, false) : height;

		if (passWidth == 0 || passHeight == 0)
			continue;

		int stride = (passWidth * bitsPerPixel + 7) / 8;
		var previous = new uint8[stride];
		var row = new uint8[stride];

		for (var y = 0; y < passHeight; y += 1)
		{
			int filter = (int)raw[offset];

			offset += 1;

			for (var i = 0; i < stride; i += 1)
			{
				int value = (int)raw[offset + i];
				int left = i >= bytesPerPixel ? (int)row[i - bytesPerPixel] : 0;
				int up = (int)previous[i];
				int upLeft = i >= bytesPerPixel ? (int)previous[i - bytesPerPixel] : 0;

				if (filter == 1)
					value += left;
				else if (filter == 2)
					value += up;
				else if (filter == 3)
					value += (left + up) / 2;
				else if (filter == 4)
					value += Paeth(left, up, upLeft);

				row[i] = (uint8)(value & 0xFF);
			}

			offset += stride;

			int targetY = interlace == 1 ? PassStart(pass, false) + y * PassStep(pass, false) : y;

			for (var x = 0; x < passWidth; x += 1)
			{
				int targetX = interlace == 1 ? PassStart(pass, true) + x * PassStep(pass, true) : x;
				int to = (targetY * width + targetX) * 4;

				if (colorType == 3)
				{
					int index = Sample(row, x, bitDepth);

					indices[targetY * width + targetX] = (uint8)index;
					image.Data[to] = palette[index * 4];
					image.Data[to + 1] = palette[index * 4 + 1];
					image.Data[to + 2] = palette[index * 4 + 2];
					image.Data[to + 3] = palette[index * 4 + 3];
				}
				else if (colorType == 0 || colorType == 4)
				{
					int gray = Sample(row, x * channels, bitDepth);
					int gray8 = ToEightBits(gray, bitDepth);

					image.Data[to] = (uint8)gray8;
					image.Data[to + 1] = (uint8)gray8;
					image.Data[to + 2] = (uint8)gray8;
					image.Data[to + 3] = colorType == 4 ? (uint8)ToEightBits(Sample(row, x * channels + 1, bitDepth), bitDepth)
						: hasTransparentColor && gray == transparentGray ? (uint8)0 : (uint8)255;
				}
				else
				{
					int red = Sample(row, x * channels, bitDepth);
					int green = Sample(row, x * channels + 1, bitDepth);
					int blue = Sample(row, x * channels + 2, bitDepth);

					image.Data[to] = (uint8)ToEightBits(red, bitDepth);
					image.Data[to + 1] = (uint8)ToEightBits(green, bitDepth);
					image.Data[to + 2] = (uint8)ToEightBits(blue, bitDepth);
					image.Data[to + 3] = colorType == 6 ? (uint8)ToEightBits(Sample(row, x * channels + 3, bitDepth), bitDepth)
						: hasTransparentColor && red == transparentRed && green == transparentGreen && blue == transparentBlue ? (uint8)0 : (uint8)255;
				}
			}

			for (var i = 0; i < stride; i += 1)
				previous[i] = row[i];
		}
	}

	return PngPicture { Rgba = image, Indices = indices, PaletteRgba = palette, PaletteCount = paletteCount };
}

int Paeth(int left, int up, int upLeft)
{
	int estimate = left + up - upLeft;
	int toLeft = estimate > left ? estimate - left : left - estimate;
	int toUp = estimate > up ? estimate - up : up - estimate;
	int toUpLeft = estimate > upLeft ? estimate - upLeft : upLeft - estimate;

	if (toLeft <= toUp && toLeft <= toUpLeft)
		return left;

	return toUp <= toUpLeft ? up : upLeft;
}

/// The sample with the index in a row (1, 2, 4, 8 or 16 bits per sample, big endian).
int Sample(uint8[] row, int index, int bits)
{
	if (bits == 8)
		return (int)row[index];

	if (bits == 16)
		return ((int)row[index * 2] << 8) | (int)row[index * 2 + 1];

	int bit = index * bits;
	int value = (int)row[bit / 8] >> (8 - bits - bit % 8);

	return value & ((1 << bits) - 1);
}

int ToEightBits(int value, int bits)
{
	if (bits == 8)
		return value;

	if (bits == 16)
		return value >> 8;

	return value * 255 / ((1 << bits) - 1);
}

// Adam7: the start and step of every pass in x and y
int PassStart(int pass, bool horizontal)
{
	return horizontal ? (new int[] { 0, 4, 0, 2, 0, 1, 0 })[pass] : (new int[] { 0, 0, 4, 0, 2, 0, 1 })[pass];
}

int PassStep(int pass, bool horizontal)
{
	return horizontal ? (new int[] { 8, 8, 4, 4, 2, 2, 1 })[pass] : (new int[] { 8, 8, 8, 4, 4, 2, 2 })[pass];
}

int PassSize(int size, int pass, bool horizontal)
{
	int start = PassStart(pass, horizontal);
	int step = PassStep(pass, horizontal);

	return size <= start ? 0 : (size - start + step - 1) / step;
}

/// The picture as a PNG file (RGBA, 8 bits, no filter).
uint8[] EncodePng(Image image)
{
	int stride = image.Width * 4;
	var pixels = new uint8[(stride + 1) * image.Height];

	for (var y = 0; y < image.Height; y += 1)
	{
		int row = y * (stride + 1);

		for (var i = 0; i < stride; i += 1)
			pixels[row + 1 + i] = image.Data[y * stride + i];
	}
	var zlib = ByteWriter.Create();

	zlib.Byte(0x78);
	zlib.Byte(0x9C);
	zlib.Bytes(DeflateRaw(pixels));
	zlib.Dword((int64)Adler32(pixels));

	var header = ByteWriter.Create();

	header.Dword((int64)image.Width);
	header.Dword((int64)image.Height);
	header.Byte(8);
	header.Byte(6);
	header.Byte(0);
	header.Byte(0);
	header.Byte(0);

	var file = ByteWriter.Create();

	file.Bytes(new uint8[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A });
	PngChunk(file, "IHDR", header.ToArray());
	PngChunk(file, "IDAT", zlib.ToArray());
	PngChunk(file, "IEND", new uint8[0]);

	return file.ToArray();
}

/// A palette picture as a PNG file: 8 bits per pixel, PLTE with the colors of the palette, tRNS makes the entries in
/// 'transparent' (one flag per entry, may be null) fully transparent.
uint8[] EncodeIndexedPng(int width, int height, uint8[] indices, uint8[] paletteRgb, int paletteCount, bool[] transparent)
{
	var pixels = new uint8[(width + 1) * height];

	for (var y = 0; y < height; y += 1)
	{
		for (var x = 0; x < width; x += 1)
			pixels[y * (width + 1) + 1 + x] = indices[y * width + x];
	}

	var zlib = ByteWriter.Create();

	zlib.Byte(0x78);
	zlib.Byte(0x9C);
	zlib.Bytes(DeflateRaw(pixels));
	zlib.Dword((int64)Adler32(pixels));

	var header = ByteWriter.Create();

	header.Dword((int64)width);
	header.Dword((int64)height);
	header.Byte(8);
	header.Byte(3);
	header.Byte(0);
	header.Byte(0);
	header.Byte(0);

	var plte = new uint8[paletteCount * 3];

	for (var i = 0; i < paletteCount * 3; i += 1)
		plte[i] = paletteRgb[i];

	// tRNS lists the alpha of the entries up to the last transparent one
	int alphaCount = 0;

	for (var i = 0; transparent != null && i < paletteCount; i += 1)
	{
		if (transparent[i])
			alphaCount = i + 1;
	}

	var file = ByteWriter.Create();

	file.Bytes(new uint8[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A });
	PngChunk(file, "IHDR", header.ToArray());
	PngChunk(file, "PLTE", plte);

	if (alphaCount > 0)
	{
		var alpha = new uint8[alphaCount];

		for (var i = 0; i < alphaCount; i += 1)
			alpha[i] = transparent[i] ? (uint8)0 : (uint8)255;

		PngChunk(file, "tRNS", alpha);
	}

	PngChunk(file, "IDAT", zlib.ToArray());
	PngChunk(file, "IEND", new uint8[0]);

	return file.ToArray();
}

void PngChunk(ByteWriter file, string type, uint8[] data)
{
	var typeBytes = AsciiBytes(type);
	var crc = Crc32.Create();

	crc.Add(typeBytes);
	crc.Add(data);
	file.Dword((int64)data.Length);
	file.Bytes(typeBytes);
	file.Bytes(data);
	file.Dword((int64)crc.Value());
}

uint32 Adler32(uint8[] data)
{
	uint32 a = 1;
	uint32 b = 0;

	for (var i = 0; i < data.Length; i += 1)
	{
		a = (a + (uint32)data[i]) % 65521;
		b = (b + a) % 65521;
	}

	return (b << 16) | a;
}
