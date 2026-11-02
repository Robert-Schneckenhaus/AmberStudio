// Writes a TiledMap as TMX (CSV tile layers, tilesets by reference). The result can be opened in Tiled and read by the
// loader; layers, object layers and properties are kept. The text is the one System.Xml.XmlWriter of the C# version
// writes (indented by one space, "\n" line ends, " />" for empty elements, no line end after the last tag).

namespace Amber.Player.Tiled.TiledWriter;

using System;
using Amber.Base;
using Amber.Player.Tiled;

extern "C" double log10(double x);
extern "C" double pow(double x, double y);
extern "C" double floor(double x);

Error<void> Save(TiledMap map, string path)
{
	var root = XmlElement.Create("map");
	int layerId = 1;
	int objectId = 1;
	int objectCount = 0;

	foreach (var objectLayer in map.ObjectLayers)
		objectCount += objectLayer.Objects.Count();

	root.SetAttribute("version", "1.9");
	root.SetAttribute("tiledversion", "1.9.1");
	root.SetAttribute("orientation", "orthogonal");
	root.SetAttribute("renderorder", "right-down");
	root.SetAttribute("width", "" + map.Width);
	root.SetAttribute("height", "" + map.Height);
	root.SetAttribute("tilewidth", "" + map.TileWidth);
	root.SetAttribute("tileheight", "" + map.TileHeight);
	root.SetAttribute("infinite", "0");
	root.SetAttribute("nextlayerid", "" + (map.Layers.Count() + map.ObjectLayers.Count() + 1));
	root.SetAttribute("nextobjectid", "" + (objectCount + 1));
	AddProperties(root, map.Properties);

	foreach (var reference in map.Tilesets)
	{
		if (reference.Source == null)
			return error("Embedded tilesets cannot be saved.", (int)ErrorKind.InvalidOperation);

		var tileset = XmlElement.Create("tileset");

		tileset.SetAttribute("firstgid", "" + reference.FirstGid);
		tileset.SetAttribute("source", reference.Source);
		root.Children.Add(tileset);
	}

	foreach (var layer in map.Layers)
	{
		var element = XmlElement.Create("layer");

		element.SetAttribute("id", "" + layerId);
		layerId += 1;
		element.SetAttribute("name", layer.Name);
		element.SetAttribute("width", "" + layer.Width);
		element.SetAttribute("height", "" + layer.Height);

		if (!layer.Visible)
			element.SetAttribute("visible", "0");

		AddProperties(element, layer.Properties);

		var builder = StringBuilder.Create();

		builder.Append('\n');

		for (var y = 0; y < layer.Height; y += 1)
		{
			for (var x = 0; x < layer.Width; x += 1)
			{
				if (x > 0)
					builder.Append(',');

				builder.Append("" + layer.Data[y * layer.Width + x]);
			}

			builder.Append(y < layer.Height - 1 ? ",\n" : "\n");
		}

		var data = XmlElement.Create("data");

		data.SetAttribute("encoding", "csv");
		data.Text = builder.ToString();
		element.Children.Add(data);
		root.Children.Add(element);
	}

	foreach (var objectLayer in map.ObjectLayers)
	{
		var group = XmlElement.Create("objectgroup");

		group.SetAttribute("id", "" + layerId);
		layerId += 1;
		group.SetAttribute("name", objectLayer.Name);

		foreach (var item in objectLayer.Objects)
		{
			var element = XmlElement.Create("object");

			element.SetAttribute("id", "" + objectId);
			objectId += 1;
			element.SetAttribute("name", item.Name);

			if (item.Type != "")
				element.SetAttribute("type", item.Type);

			element.SetAttribute("x", FormatFloat(item.X));
			element.SetAttribute("y", FormatFloat(item.Y));

			if (item.Width > 0.0f || item.Height > 0.0f)
			{
				element.SetAttribute("width", FormatFloat(item.Width));
				element.SetAttribute("height", FormatFloat(item.Height));
			}

			AddProperties(element, item.Properties);

			if (item.Width == 0.0f && item.Height == 0.0f)
				element.Children.Add(XmlElement.Create("point"));

			group.Children.Add(element);
		}

		root.Children.Add(group);
	}

	var text = StringBuilder.Create();

	text.Append("<?xml version=\"1.0\" encoding=\"utf-8\"?>");
	WriteElement(text, root, 0);

	return File.WriteAllText(path, text.ToString());
}

void AddProperties(XmlElement element, Dictionary<string, string> properties)
{
	if (properties.Count() == 0)
		return;

	var group = XmlElement.Create("properties");

	foreach (var pair in properties.Entries())
	{
		var property = XmlElement.Create("property");

		property.SetAttribute("name", pair.Key);
		property.SetAttribute("value", pair.Value);
		group.Children.Add(property);
	}

	element.Children.Add(group);
}

/// An element on its own line, indented by its depth; an element with text keeps the text and its end tag on the lines
/// of the text (mixed content).
void WriteElement(StringBuilder text, XmlElement element, int depth)
{
	text.Append('\n');

	for (var i = 0; i < depth; i += 1)
		text.Append(' ');

	text.Append("<" + element.Name);

	for (var i = 0; i < element.AttributeNames.Count(); i += 1)
		text.Append(" " + element.AttributeNames.Get(i) + "=\"" + EscapeAttribute(element.AttributeValues.Get(i)) + "\"");

	if (element.Children.Count() == 0 && element.Text.Length == 0)
	{
		text.Append(" />");

		return;
	}

	text.Append(">");

	if (element.Text.Length > 0)
	{
		text.Append(EscapeText(element.Text));
		text.Append("</" + element.Name + ">");

		return;
	}

	foreach (var child in element.Children)
		WriteElement(text, child, depth + 1);

	text.Append('\n');

	for (var i = 0; i < depth; i += 1)
		text.Append(' ');

	text.Append("</" + element.Name + ">");
}

string EscapeText(string text)
{
	return text.Replace("\r", "").Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
}

string EscapeAttribute(string text)
{
	return text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;").Replace("\r", "&#xD;").Replace("\n", "&#xA;")
		.Replace("\t", "&#x9;");
}

/// A float like .NET writes it (float.ToString with the invariant culture): the shortest decimal that reads back as the same
/// float, fixed point for exponents -5 < e < 9, else d.dddE+XX.
string FormatFloat(float value)
{
	if (value != value)
		return "NaN";

	if (value == 0.0f)
		return 1.0 / (double)value < 0.0 ? "-0" : "0";

	string sign = value < 0.0f ? "-" : "";
	double magnitude = value < 0.0f ? -(double)value : (double)value;

	if (magnitude > 3.4028235e38)
		return sign + "Infinity";

	int exponent = (int)floor(log10(magnitude));

	if (pow(10.0, (double)exponent) > magnitude)
		exponent -= 1;
	else if (pow(10.0, (double)(exponent + 1)) <= magnitude)
		exponent += 1;

	string digits = "";

	for (var count = 1; count <= 9; count += 1)
	{
		int shift = count - 1 - exponent;
		double scaled = shift >= 0 ? magnitude * pow(10.0, (double)shift) : magnitude / pow(10.0, (double)(-shift));
		int64 mantissa = (int64)floor(scaled + 0.5);
		int digitExponent = exponent;

		if ((double)mantissa >= pow(10.0, (double)count))
		{
			mantissa = mantissa / 10;
			digitExponent += 1;
		}

		string candidate = "" + mantissa;

		if ((candidate + "e" + (digitExponent - count + 1)).ParseDouble() is double parsed && (float)parsed == (float)magnitude)
		{
			digits = candidate;
			exponent = digitExponent;

			break;
		}
	}

	while (digits.Length > 1 && digits[digits.Length - 1] == '0')
		digits = digits.Substring(0, digits.Length - 1);

	if (exponent >= 9 || exponent < -4)
	{
		string mantissaText = digits.Length > 1 ? digits.Substring(0, 1) + "." + digits.Substring(1) : digits;
		int shown = exponent < 0 ? -exponent : exponent;

		return sign + mantissaText + "E" + (exponent < 0 ? "-" : "+") + (shown < 10 ? "0" : "") + shown;
	}

	if (exponent < 0)
	{
		string zeros = "";

		for (var i = 0; i < -exponent - 1; i += 1)
			zeros = zeros + "0";

		return sign + "0." + zeros + digits;
	}

	if (digits.Length <= exponent + 1)
	{
		string padded = digits;

		while (padded.Length < exponent + 1)
			padded = padded + "0";

		return sign + padded;
	}

	return sign + digits.Substring(0, exponent + 1) + "." + digits.Substring(exponent + 1);
}
