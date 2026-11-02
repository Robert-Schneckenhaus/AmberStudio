namespace Amber.Screens;

using System;
using Amber.Base;
using Amber.Script.Compilation;

/// A screen or prefab file before extends resolution.
struct ScreenEntry
{
	string Name;
	bool IsPrefab;
	YamlNode Data;
	string File;
}

/// A screen or prefab file: its path (only for messages) and its text.
struct ScreenFile
{
	string Path;
	string Text;
}

/// The properties, nodes and parameters after applying extends.
struct MergedScreen
{
	YamlNode Properties;
	List<YamlNode> Nodes;
	List<string> Params;
}

/// Loads the screen and prefab definitions (YAML, spec section 8 and spec/schemas/screen.schema.json) of a folder:
/// resolves extends and use, checks the properties and provides the arguments and node names the script compiler needs
/// (Signatures()). A handle to shared storage.
struct ScreenLibrary
{
	Dictionary<string, ScreenEntry> _entries;
	Dictionary<string, ScreenDefinition> Screens;
	/// The files the library was read from, in their order (a game pack keeps them, see the prototype's PackCook).
	List<ScreenFile> Files;

	static ScreenLibrary Create()
	{
		return ScreenLibrary { _entries = Dictionary<string, ScreenEntry>.Create(), Screens = Dictionary<string, ScreenDefinition>.Create(), Files = List<ScreenFile>.Create() };
	}

	Optional<ScreenDefinition> Find(string name)
	{
		return Screens.TryGet(name);
	}

	Optional<ScreenSignature> Get(string screenName)
	{
		if (Screens.TryGet(screenName) is ScreenDefinition screen)
			return ScreenSignature { Args = screen.Args, Nodes = screen.NodeIds };

		return null;
	}

	/// The signatures of all screens for the script compiler (C#: the library as IScreenSignatureProvider).
	ScreenSignatures Signatures()
	{
		var signatures = ScreenSignatures.Create();

		foreach (var screen in Screens.Values())
			signatures.Add(screen.Name, ScreenSignature { Args = screen.Args, Nodes = screen.NodeIds });

		return signatures;
	}

	/// Reads all *.yaml files of the folder (subfolders included). Every file has to match the screen schema.
	static Error<ScreenLibrary> Load(string folder)
	{
		var files = List<ScreenFile>.Create();

		if (Directory.Exists(folder))
		{
			foreach (var path in Directory.FindFiles(folder, ".yaml"))
				files.Add(ScreenFile { Path = path, Text = try ReadText(path) });
		}

		return LoadFiles(files);
	}

	/// The same from the texts of the files.
	static Error<ScreenLibrary> LoadFiles(List<ScreenFile> files)
	{
		var library = Create();

		foreach (var source in files)
		{
			string file = source.Path;
			string text = source.Text;

			library.Files.Add(source);

			var problems = ScreenSchema.Validate(text);

			if (problems.Count() > 0)
				return error(file + " does not match the screen schema: " + JoinList("; ", problems), (int)ErrorKind.InvalidData);

			var parsed = ParseYaml(text);
			var data = YamlNode.Mapping(0);

			if (parsed is YamlNode document)
				data = try AsMap(document, file, "the document");
			else
				return error(file + parsed.Message, (int)ErrorKind.InvalidData);

			bool isPrefab = data.ContainsKey("prefab");
			string name = data.GetText(isPrefab ? "prefab" : "screen");

			if (name == null)
				return error(file + ": needs 'screen' or 'prefab'.", (int)ErrorKind.InvalidData);

			if (isPrefab == data.ContainsKey("screen"))
				return error(file + ": exactly one of 'screen' and 'prefab' is allowed.", (int)ErrorKind.InvalidData);

			if (library._entries.ContainsKey(name))
				return error(file + ": '" + name + "' is defined twice.", (int)ErrorKind.InvalidData);

			library._entries.Set(name, ScreenEntry { Name = name, IsPrefab = isPrefab, Data = data, File = file });
		}

		foreach (var entry in library._entries.Values())
		{
			if (!entry.IsPrefab)
				library.Screens.Set(entry.Name, try library.Build(entry));
		}

		return library;
	}

	Error<ScreenDefinition> Build(ScreenEntry entry)
	{
		var merged = try Merge(entry, HashSet<string>.Create());
		var properties = merged.Properties;
		var nodes = List<NodeDefinition>.Create();

		foreach (var node in merged.Nodes)
			nodes.Add(try ParseNode(node, entry.File, Dictionary<string, string>.Create()));

		var ids = List<string>.Create();
		var nodeArray = ArrayOf(nodes);

		foreach (var node in ScreenDefinition.Flatten(nodeArray))
		{
			if (node.Id != null && ContainsText(ids, node.Id))
				return error(entry.File + ": node id '" + node.Id + "' is used twice.", (int)ErrorKind.InvalidData);

			ids.Add(node.Id == null ? "" : node.Id);
		}

		var region = YamlNode.Mapping(0);

		if (properties.GetValue("region") is YamlNode regionValue)
			region = try AsMap(regionValue, entry.File, "region");

		var regionAt = try Pair(region.Get("at"), entry.File, "region.at");
		var regionSize = try Pair(region.Get("size"), entry.File, "region.size");
		var passthrough = List<ScreenRect>.Create();

		foreach (var item in try AsList(properties.Get("passthrough")))
		{
			var rect = try AsMap(item, entry.File, "passthrough");
			var at = try Pair(rect.Get("at"), entry.File, "passthrough.at");
			var size = try Pair(rect.Get("size"), entry.File, "passthrough.size");

			passthrough.Add(ScreenRect.Of(at.First, at.Second, size.First, size.Second));
		}

		var closeOn = List<string>.Create();

		foreach (var value in try AsList(properties.Get("close_on")))
		{
			if (!ContainsText(closeOn, value.Value))
				closeOn.Add(value.Value);
		}

		var args = List<string>.Create();

		foreach (var value in try AsList(properties.Get("args")))
			args.Add(value.Value);

		string fade = properties.GetText("fade");

		return ScreenDefinition
		{
			Name = entry.Name,
			Modal = try Bool(properties, "modal"),
			Transparent = try Bool(properties, "transparent"),
			Fade = fade == null ? "both" : fade,
			AllowCharacterSelect = !properties.ContainsKey("allow_character_select") || try Bool(properties, "allow_character_select"),
			AllowInventory = !properties.ContainsKey("allow_inventory") || try Bool(properties, "allow_inventory"),
			Cursor = properties.GetText("cursor"),
			CloseOn = ArrayOf(closeOn),
			RegionX = regionAt.First,
			RegionY = regionAt.Second,
			RegionWidth = regionSize.First,
			RegionHeight = regionSize.Second,
			Passthrough = ArrayOf(passthrough),
			Args = ArrayOf(args),
			OnOpen = properties.GetText("on_open"),
			OnClose = properties.GetText("on_close"),
			OnResume = properties.GetText("on_resume"),
			Nodes = nodeArray,
			NodeIds = ArrayOf(ids)
		};
	}

	/// Applies extends: the properties of the parent, overwritten by the child; the nodes of the parent first.
	Error<MergedScreen> Merge(ScreenEntry entry, HashSet<string> visiting)
	{
		if (!visiting.Add(entry.Name))
			return error(entry.File + ": '" + entry.Name + "' extends itself.", (int)ErrorKind.InvalidData);

		var properties = YamlNode.Mapping(0);
		var nodes = List<YamlNode>.Create();
		string parentName = entry.Data.GetText("extends");

		if (parentName != null)
		{
			if (_entries.TryGet(parentName) is ScreenEntry parent)
			{
				var inherited = try Merge(parent, visiting);

				for (var i = 0; i < inherited.Properties.Count(); i += 1)
					properties.Set(inherited.Properties.KeyAt(i), inherited.Properties.ItemAt(i));

				foreach (var node in inherited.Nodes)
					nodes.Add(node);
			}
			else
			{
				return error(entry.File + ": '" + entry.Name + "' extends unknown '" + parentName + "'.", (int)ErrorKind.InvalidData);
			}
		}

		for (var i = 0; i < entry.Data.Count(); i += 1)
		{
			string key = entry.Data.KeyAt(i);

			if (key != "screen" && key != "prefab" && key != "extends" && key != "nodes" && key != "params")
				properties.Set(key, entry.Data.ItemAt(i));
		}

		foreach (var node in try AsList(entry.Data.Get("nodes")))
			nodes.Add(node);

		visiting.Remove(entry.Name);

		var parameters = List<string>.Create();

		foreach (var value in try AsList(entry.Data.Get("params")))
			parameters.Add(value.Value);

		return MergedScreen { Properties = properties, Nodes = nodes, Params = parameters };
	}

	Error<NodeDefinition> ParseNode(YamlNode raw, string file, Dictionary<string, string> parameters)
	{
		var wrapper = try AsMap(raw, file, "a node");

		if (wrapper.Count() != 1)
			return error(file + ": a node has exactly one kind (window, label, button ...).", (int)ErrorKind.InvalidData);

		string kind = wrapper.KeyAt(0);
		var body = wrapper.ItemAt(0);

		if (kind == "use")
			return ExpandPrefab(try AsMap(body, file, "use"), file, parameters);

		var data = try AsMap(Substitute(body, parameters), file, kind);
		var at = IntPair { First = 0, Second = 0 };
		var size = IntPair { First = 0, Second = 0 };

		if (data.ContainsKey("at"))
			at = try Pair(data.Get("at"), file, "at");

		if (data.ContainsKey("size"))
			size = try Pair(data.Get("size"), file, "size");

		if (kind == "window" && size.First == 0)
		{
			if (data.GetValue("size_tiles") is YamlNode tiles)
			{
				var tileCount = try Pair(tiles, file, "size_tiles");

				size = IntPair { First = tileCount.First * 16, Second = tileCount.Second * 16 };
			}
		}

		int layer = 0;

		if (data.ContainsKey("layer"))
		{
			if (TryParseInt(data.GetText("layer")) is int value)
				layer = value;
			else
				return error(file + ": 'layer' must be a number.", (int)ErrorKind.InvalidData);
		}

		var children = List<NodeDefinition>.Create();

		foreach (var child in try AsList(data.Get("nodes")))
			children.Add(try ParseNode(child, file, parameters));

		return NodeDefinition
		{
			Kind = kind,
			Id = data.GetText("id"),
			X = at.First,
			Y = at.Second,
			Width = size.First,
			Height = size.Second,
			Layer = layer,
			Visible = !data.ContainsKey("visible") || try Bool(data, "visible"),
			Enabled = !data.ContainsKey("enabled") || try Bool(data, "enabled"),
			OnClick = data.GetText("on_click"),
			OnHover = data.GetText("on_hover"),
			Properties = data,
			Children = ArrayOf(children)
		};
	}

	Error<NodeDefinition> ExpandPrefab(YamlNode use, string file, Dictionary<string, string> outer)
	{
		string name = use.GetText("prefab");

		if (name == null)
			return error(file + ": 'use' needs a prefab.", (int)ErrorKind.InvalidData);

		if (_entries.TryGet(name) is ScreenEntry prefab)
		{
			if (!prefab.IsPrefab)
				return error(file + ": unknown prefab '" + name + "'.", (int)ErrorKind.InvalidData);

			var merged = try Merge(prefab, HashSet<string>.Create());
			var parameters = Dictionary<string, string>.Create();

			foreach (var entry in outer.Entries())
				parameters.Set(entry.Key, entry.Value);

			if (use.GetValue("params") is YamlNode given)
			{
				var map = try AsMap(given, file, "params");

				for (var i = 0; i < map.Count(); i += 1)
				{
					var value = map.ItemAt(i);

					parameters.Set(map.KeyAt(i), value.IsScalar() ? value.Value : "");
				}
			}

			var at = IntPair { First = 0, Second = 0 };

			if (use.ContainsKey("at"))
				at = try Pair(use.Get("at"), file, "at");

			var children = List<NodeDefinition>.Create();

			foreach (var node in merged.Nodes)
				children.Add(try ParseNode(node, prefab.File, parameters));

			return NodeDefinition
			{
				Kind = "container", Id = null, X = at.First, Y = at.Second, Width = 0, Height = 0, Layer = 0, Visible = true, Enabled = true,
				OnClick = null, OnHover = null, Properties = YamlNode.Mapping(0), Children = ArrayOf(children)
			};
		}

		return error(file + ": unknown prefab '" + name + "'.", (int)ErrorKind.InvalidData);
	}
}

/// Replaces "$name" scalars with the parameter values (in copies of mappings and sequences).
YamlNode Substitute(YamlNode value, Dictionary<string, string> parameters)
{
	switch (value.Kind)
	{
		case YamlKind.Scalar:
		{
			if (value.Value.StartsWith("$"))
			{
				if (parameters.TryGet(value.Value.Substring(1)) is string replacement)
					return YamlNode.Scalar(replacement, true, value.Line);
			}

			return value;
		}
		case YamlKind.Mapping:
		{
			var result = YamlNode.Mapping(value.Line);

			for (var i = 0; i < value.Count(); i += 1)
				result.Set(value.KeyAt(i), Substitute(value.ItemAt(i), parameters));

			return result;
		}
		case YamlKind.Sequence:
		{
			var result = YamlNode.Sequence(value.Line);

			for (var i = 0; i < value.Count(); i += 1)
				result.Add(Substitute(value.ItemAt(i), parameters));

			return result;
		}
		default:
			return value;
	}
}

Error<YamlNode> AsMap(YamlNode value, string file, string what)
{
	if (value.Kind != YamlKind.Mapping)
		return error(file + ": " + what + " must be a mapping.", (int)ErrorKind.InvalidData);

	return value;
}

/// The items of a sequence; a missing or null value is an empty list.
Error<List<YamlNode>> AsList(Optional<YamlNode> value)
{
	var items = List<YamlNode>.Create();

	if (value is YamlNode node)
	{
		if (node.IsNull())
			return items;

		if (node.Kind != YamlKind.Sequence)
			return error("A list was expected.", (int)ErrorKind.InvalidData);

		for (var i = 0; i < node.Count(); i += 1)
			items.Add(node.ItemAt(i));
	}

	return items;
}

Error<IntPair> Pair(Optional<YamlNode> value, string file, string what)
{
	if (value is YamlNode node)
	{
		if (node.Kind == YamlKind.Sequence && node.Count() == 2)
		{
			if (TryParseInt(node.ItemAt(0).Value) is int first)
			{
				if (TryParseInt(node.ItemAt(1).Value) is int second)
					return IntPair { First = first, Second = second };
			}

			return error(file + ": " + what + " must be a list of two numbers.", (int)ErrorKind.InvalidData);
		}
	}

	return error(file + ": " + what + " must be a list of two numbers.", (int)ErrorKind.InvalidData);
}

Error<bool> Bool(YamlNode map, string key)
{
	string text = map.GetText(key);

	if (text == null)
		return false;

	if (TryParseBool(text) is bool flag)
		return flag;

	return error("'" + text + "' is not a boolean.", (int)ErrorKind.InvalidData);
}

/// The text of a file (C#: File.ReadAllText); a missing file is an Io error.
Error<string> ReadText(string path)
{
	var text = File.ReadAllText(path);

	if (text is string content)
		return content;

	return error("cannot read '" + path + "': " + text.Message, (int)ErrorKind.Io);
}
