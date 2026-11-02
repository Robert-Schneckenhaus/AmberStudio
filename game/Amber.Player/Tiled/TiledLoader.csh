// Reads Tiled maps (TMX) and tilesets (TSX). Layers can be CSV or Base64 (uncompressed or zlib; gzip is not supported).
// A tileset file which is not installed (the third party packs are not part of the repository) becomes a placeholder
// tileset instead of an error, so the game runs without the assets.

namespace Amber.Player.Tiled.TiledLoader;

using System;
using Amber.Base;
using Amber.Player.Platform;
using Amber.Player.Tiled;

Dictionary<string, TiledTileset> TilesetCache = Dictionary<string, TiledTileset>.Create();

/// The images searched below the assets folder by file name (file name to path), read once.
Dictionary<string, string> AssetImages = Dictionary<string, string>.Create();
bool AssetImagesRead = false;

Error<TiledMap> Load(string path)
{
	string directory = Path.GetDirectory(path);
	var root = try LoadXml(path);
	var map = TiledMap.Create(try Int(root, "width"), try Int(root, "height"), try Int(root, "tilewidth"), try Int(root, "tileheight"));

	map.Path = path;

	foreach (var element in root.Elements("tileset"))
	{
		int firstGid = try Int(element, "firstgid");
		string source = element.Attribute("source");
		var tileset = source != null ? try LoadTileset(NormalizePath(Path.Combine(directory, source)), map) : try ParseTileset(element, directory);

		map.Tilesets.Add(TiledTilesetReference { Source = source, FirstGid = firstGid, Tileset = tileset });
	}

	// a placeholder tileset covers the IDs up to the next tileset
	for (var i = 0; i < map.Tilesets.Count(); i += 1)
	{
		var reference = map.Tilesets.Get(i);

		if (reference.Tileset.Missing)
		{
			reference.Tileset.TileCount = i + 1 < map.Tilesets.Count() ? map.Tilesets.Get(i + 1).FirstGid - reference.FirstGid : 0x0FFFFFFF - reference.FirstGid;
			map.Tilesets.Set(i, reference);
		}
	}

	foreach (var element in root.Elements("layer"))
	{
		int width = try Int(element, "width");
		int height = try Int(element, "height");

		var data = try Child(element, "data", "layer without data");
		var layer = TiledLayer
		{
			Name = TextOr(element.Attribute("name"), ""), Width = width, Height = height, Data = try ReadData(data, width * height),
			Visible = element.Attribute("visible") != "0", Properties = Dictionary<string, string>.Create()
		};

		ReadProperties(element, layer.Properties);
		map.Layers.Add(layer);
	}

	foreach (var element in root.Elements("objectgroup"))
	{
		var objectLayer = TiledObjectLayer { Name = TextOr(element.Attribute("name"), ""), Objects = List<TiledObject>.Create() };

		foreach (var objectElement in element.Elements("object"))
		{
			string type = objectElement.Attribute("type");

			if (type == null)
				type = TextOr(objectElement.Attribute("class"), "");

			var tiledObject = TiledObject
			{
				Name = TextOr(objectElement.Attribute("name"), ""), Type = type, X = Float(objectElement, "x"), Y = Float(objectElement, "y"),
				Width = Float(objectElement, "width"), Height = Float(objectElement, "height"), Properties = Dictionary<string, string>.Create()
			};

			ReadProperties(objectElement, tiledObject.Properties);
			objectLayer.Objects.Add(tiledObject);
		}

		map.ObjectLayers.Add(objectLayer);
	}

	ReadProperties(root, map.Properties);

	return map;
}

/// A tileset file; a missing one gives a placeholder tileset (named like the file) with the tile size of the map, or the
/// size in its name ("summer trees 80x112", like the Mana Seed files), so that placeholders cover the cells of the real
/// tiles.
Error<TiledTileset> LoadTileset(string path, TiledMap map)
{
	if (TilesetCache.TryGet(path) is TiledTileset cached)
		return cached;

	if (!File.Exists(path))
	{
		string name = Path.GetStem(path);
		int width = map.TileWidth;
		int height = map.TileHeight;
		var words = name.Split(" ");

		foreach (var word in words)
		{
			var size = word.Split("x");

			if (size.Length == 2 && TryParseInt(size[0].ToString()) is int w && TryParseInt(size[1].ToString()) is int h)
			{
				if (w > 0 && h > 0 && w <= 512 && h <= 512)
				{
					width = w;
					height = h;
				}
			}
		}

		return TiledTileset
		{
			Name = name, TileWidth = width, TileHeight = height, TileCount = 0, Columns = 1, ImagePath = null, Missing = true,
			Animations = Dictionary<int, TileFrame[]>.Create(), Wang = null
		};
	}

	var root = try LoadXml(path);
	var tileset = try ParseTileset(root, Path.GetDirectory(path));

	TilesetCache.Set(path, tileset);

	return tileset;
}

Error<TiledTileset> ParseTileset(XmlElement element, string directory)
{
	var imageElement = try Child(element, "image", "tileset without image");
	var tileset = TiledTileset
	{
		Name = TextOr(element.Attribute("name"), ""), TileWidth = try Int(element, "tilewidth"), TileHeight = try Int(element, "tileheight"),
		TileCount = try Int(element, "tilecount"), Columns = try Int(element, "columns"),
		ImagePath = ResolveImage(NormalizePath(Path.Combine(directory, TextOr(imageElement.Attribute("source"), "")))), Missing = false,
		Animations = Dictionary<int, TileFrame[]>.Create(), Wang = null
	};

	foreach (var tile in element.Elements("tile"))
	{
		if (tile.Element("animation") is XmlElement animation)
		{
			var frames = List<TileFrame>.Create();

			foreach (var frame in animation.Elements("frame"))
				frames.Add(TileFrame { TileId = try Int(frame, "tileid"), DurationMs = try Int(frame, "duration") });

			tileset.Animations.Set(try Int(tile, "id"), ArrayOf(frames));
		}
	}

	if (element.Element("wangsets") is XmlElement wangsets)
	{
		foreach (var set in wangsets.Elements("wangset"))
		{
			if (set.Attribute("type") != "corner")
				continue;

			var wang = WangSet.Create();

			foreach (var color in set.Elements("wangcolor"))
				wang.ColorNames.Add(TextOr(color.Attribute("name"), ""));

			foreach (var wangTile in set.Elements("wangtile"))
			{
				var parts = TextOr(wangTile.Attribute("wangid"), "").Split(",");

				if (parts.Length < 8)
					return error("A wang tile needs eight corner values.", (int)ErrorKind.InvalidData);

				// wangid: top, top right, right, bottom right, bottom, bottom left, left, top left
				wang.Add(try Int(wangTile, "tileid"), try NumberText(parts[7].ToString()), try NumberText(parts[1].ToString()), try NumberText(parts[3].ToString()), try NumberText(parts[5].ToString()));
			}

			tileset.Wang = wang;

			break;
		}
	}

	return tileset;
}

/// The Mana Seed TSX files point to ../summer sheets/ relative to their own folder, which does not exist in the pack layout.
/// If the image is missing it is searched by file name below the assets folder (Tiled asks for the same fix). Null if it
/// is not found.
string ResolveImage(string path)
{
	if (File.Exists(path))
		return path;

	if (!AssetImagesRead)
	{
		AssetImagesRead = true;

		string assets = Path.Combine(RepositoryRoot, "assets");

		if (Directory.Exists(assets))
		{
			foreach (var file in Directory.FindFiles(assets, ".png"))
			{
				string name = Path.GetFileName(file);

				if (!file.Contains("_old stuff") && !AssetImages.ContainsKey(name))
					AssetImages.Set(name, file);
			}
		}
	}

	string found = AssetImages.GetOrDefault(Path.GetFileName(path), null);

	if (found == null)
		Console.WriteErrorLine("Tileset image not found: " + path + " (placeholder tiles are drawn)");

	return found;
}

Error<uint32[]> ReadData(XmlElement data, int count)
{
	string encoding = TextOr(data.Attribute("encoding"), "");
	string compression = TextOr(data.Attribute("compression"), "");

	if (encoding == "csv")
	{
		var values = new uint32[count];
		int index = 0;
		// int64: the flip flags make IDs up to 2^32 - 1
		int64 value = -1;
		string text = data.Text;

		for (var i = 0; i <= text.Length; i += 1)
		{
			char c = i < text.Length ? text[i] : ',';

			if (c >= '0' && c <= '9')
			{
				value = (value < 0 ? 0 : value * 10) + (int64)(int)(c - '0');

				if (value > (int64)4294967295)
					return error("A tile ID of the layer data is too big.", (int)ErrorKind.InvalidData);

				continue;
			}

			if (value >= 0)
			{
				if (index >= count)
					return error("Layer data has more than " + count + " tiles.", (int)ErrorKind.InvalidData);

				values[index] = (uint32)value;
				index += 1;
				value = -1;
			}
		}

		if (index != count)
			return error("Layer data has " + index + " tiles, expected " + count + ".", (int)ErrorKind.InvalidData);

		return values;
	}

	if (encoding == "base64")
	{
		var bytes = try DecodeBase64(data.Text.Trim().ToString());

		if (compression == "zlib")
			bytes = try InflateRaw(Slice(bytes, 2, bytes.Length - 2), count * 4);
		else if (compression != "")
			return error("Tile layer compression '" + compression + "' is not supported; use CSV or zlib.", (int)ErrorKind.InvalidData);

		var values = new uint32[bytes.Length / 4];

		for (var i = 0; i < values.Length; i += 1)
			values[i] = (uint32)bytes[i * 4] | ((uint32)bytes[i * 4 + 1] << 8) | ((uint32)bytes[i * 4 + 2] << 16) | ((uint32)bytes[i * 4 + 3] << 24);

		return values;
	}

	return error("Tile layers must use CSV or Base64 encoding.", (int)ErrorKind.InvalidData);
}

Error<uint8[]> DecodeBase64(string text)
{
	var result = ByteWriter.Create();
	int buffer = 0;
	int bits = 0;

	for (var i = 0; i < text.Length; i += 1)
	{
		char c = text[i];
		int value = c >= 'A' && c <= 'Z' ? (int)(c - 'A') : c >= 'a' && c <= 'z' ? (int)(c - 'a') + 26 : c >= '0' && c <= '9' ? (int)(c - '0') + 52
			: c == '+' ? 62 : c == '/' ? 63 : -1;

		if (c == '=' || c == ' ' || c == '\n' || c == '\r' || c == '\t')
			continue;

		if (value < 0)
			return error("Invalid Base64 data.", (int)ErrorKind.InvalidData);

		buffer = (buffer << 6) | value;
		bits += 6;

		if (bits >= 8)
		{
			bits -= 8;
			result.Byte((buffer >> bits) & 0xFF);
		}
	}

	return result.ToArray();
}

/// The first child element with the name; the message is the error if there is none.
Error<XmlElement> Child(XmlElement element, string name, string message)
{
	if (element.Element(name) is XmlElement child)
		return child;

	return error(message + ".", (int)ErrorKind.InvalidData);
}

void ReadProperties(XmlElement element, Dictionary<string, string> target)
{
	if (element.Element("properties") is XmlElement properties)
	{
		foreach (var property in properties.Elements("property"))
		{
			string value = property.Attribute("value");

			target.Set(TextOr(property.Attribute("name"), ""), value != null ? value : property.Text);
		}
	}
}

string TextOr(string text, string fallback)
{
	return text != null ? text : fallback;
}

Error<int> Int(XmlElement element, string name)
{
	string text = element.Attribute(name);

	if (text == null)
		return error("<" + element.Name + "> has no attribute '" + name + "'.", (int)ErrorKind.InvalidData);

	return (int)ParseFloat(text);
}

Error<int> NumberText(string text)
{
	if (TryParseInt(text.Trim().ToString()) is int value)
		return value;

	return error("'" + text + "' is not a number.", (int)ErrorKind.InvalidData);
}

float Float(XmlElement element, string name)
{
	string text = element.Attribute(name);

	return text == null ? 0.0f : ParseFloat(text);
}

/// A decimal number like "240", "-3.5" or "1e3" (C#: float.Parse, invariant culture); 0 for anything else.
float ParseFloat(string text)
{
	if (text.Trim().ParseDouble() is double value)
		return (float)value;

	return 0.0f;
}

/// Resolves "." and ".." in a path with '/' separators (C#: Path.GetFullPath for the cache keys).
string NormalizePath(string path)
{
	string normalized = Path.Normalize(path);
	var parts = normalized.Split("/");
	var result = List<string>.Create();
	bool absolute = normalized.StartsWith("/");

	foreach (var part in parts)
	{
		if (part.Length == 0 || part == ".")
			continue;

		if (part == ".." && result.Count() > 0 && result.Get(result.Count() - 1) != "..")
			result.RemoveAt(result.Count() - 1);
		else
			result.Add(part.ToString());
	}

	string joined = JoinList("/", result);

	return absolute ? "/" + joined : joined.Length == 0 ? "." : joined;
}
