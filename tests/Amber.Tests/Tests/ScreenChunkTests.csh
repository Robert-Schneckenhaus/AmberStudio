namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Screens;
using Amber.Script.Common;

// The binary screen chunk (spec sections 8.2 and 8.3, task 2.3) and the library that reads the YAML screens.

void RegisterScreenChunkTests(ref TestList tests)
{
	tests.Theory("ScreenChunk.EveryScreenRoundTrips", EveryScreenRoundTrips, "examples/screens");
	tests.Theory("ScreenChunk.EveryScreenRoundTrips", EveryScreenRoundTrips, "game/content/screens");
	tests.Fact("ScreenChunk.NodeRecordsCarryTheTypeSpecificFields", NodeRecordsCarryTheTypeSpecificFields);
	tests.Fact("ScreenChunk.TheDetailOfAListIsALocalSource", TheDetailOfAListIsALocalSource);
	tests.Fact("ScreenChunk.TheNameAndDetailOfAnItemGridAreLocalSources", TheNameAndDetailOfAnItemGridAreLocalSources);
	tests.Fact("ScreenChunk.ChildrenPointToTheirParent", ChildrenPointToTheirParent);
	tests.Fact("ScreenChunk.NodesWithoutNameKeepTheirIndex", NodesWithoutNameKeepTheirIndex);
	tests.Fact("ScreenChunk.PassthroughRegionsDecideWhereInputGoesDown", PassthroughRegionsDecideWhereInputGoesDown);
	tests.Fact("ScreenChunk.BrokenFilesAreRejectedByTheLibrary", BrokenFilesAreRejectedByTheLibrary);
	tests.Fact("ScreenChunk.LiteralTextsMustBeLatin1", LiteralTextsMustBeLatin1);
	tests.Fact("ScreenChunk.UnknownHotkeysAreRejected", UnknownHotkeysAreRejected);
	tests.Fact("ScreenChunk.DamagedChunksAreRejected", DamagedChunksAreRejected);
}

/// Hands out IDs in order of first use, like the tables of a cook would. Copies share the IDs.
struct AutoSymbols : IScreenSymbols
{
	Dictionary<string, int> _ids;

	static AutoSymbols Create()
	{
		return AutoSymbols { _ids = Dictionary<string, int>.Create() };
	}

	Error<int> Screen(string name)
	{
		return Id("S." + name);
	}

	Error<int> Text(string name)
	{
		return Id("T." + name);
	}

	Error<int> Graphic(string name)
	{
		return Id("G." + name);
	}

	Error<int> Source(string name)
	{
		return Id("N." + name);
	}

	Error<int> Group(string screen, string group)
	{
		return Id(screen + "." + group);
	}

	Error<int> Cursor(string name)
	{
		return Id("C." + name);
	}

	int Id(string key)
	{
		if (_ids.TryGet(key) is int id)
			return id;

		int next = _ids.Count() + 1;

		_ids.Set(key, next);

		return next;
	}
}

/// Writes the screen with new automatic symbols.
Error<uint8[]> WriteScreen(ScreenDefinition screen)
{
	var symbols = AutoSymbols.Create();

	return ScreenChunk.Write(screen, ref symbols);
}

/// Writes the screen and reads the chunk back.
Error<ScreenChunk> RoundTrip(ScreenDefinition screen)
{
	return ScreenChunk.Read(try WriteScreen(screen));
}

/// A folder with one YAML file (C#: TempFolder).
Error<string> ScreenFolder(string file, string text)
{
	string folder = NewTempFolder("screens");

	try File.WriteAllText(Path.Combine(folder, file), text);

	return folder;
}

/// A screen of the library in the folder (C#: ScreenLibrary.Load(folder).Find(name)!).
Error<ScreenDefinition> LoadScreen(string folder, string name)
{
	return FindScreen(try ScreenLibrary.Load(folder), name);
}

/// A screen of a library (C#: library.Find(name)!).
Error<ScreenDefinition> FindScreen(ScreenLibrary library, string name)
{
	if (library.Find(name) is ScreenDefinition screen)
		return screen;

	return error("the library has no screen " + name, -1);
}

/// A test screen: the YAML in a new folder, read by the library.
Error<ScreenDefinition> TestScreen(string yaml)
{
	return LoadScreen(try ScreenFolder("test.yaml", yaml), "test");
}

Error<void> EveryScreenRoundTrips(string[] arguments)
{
	var library = try ScreenLibrary.Load(RootPath(arguments[0]));

	try Assert.True(library.Screens.Count() > 0, "the library has screens");

	foreach (var screen in library.Screens.Values())
	{
		var chunk = try RoundTrip(screen);
		var nodes = ScreenDefinition.Flatten(screen.Nodes);

		try Assert.Equal(nodes.Count(), chunk.Nodes.Length);
		try Assert.Equal(screen.Args.Length, chunk.ArgumentCount);
		try Assert.Equal(screen.Passthrough.Length, chunk.Passthrough.Length);
		try Assert.True(ScreenRect.Of(screen.RegionX, screen.RegionY, screen.RegionWidth, screen.RegionHeight).Same(chunk.Region), screen.Name + ": the region");
		try Assert.Equal(screen.Transparent, HasScreenFlag(chunk.Flags, ScreenFlags.Transparent));
		try Assert.Equal(screen.Modal, HasScreenFlag(chunk.Flags, ScreenFlags.Modal));
		try Assert.Equal(ContainsText(screen.CloseOn, "escape"), HasScreenFlag(chunk.Flags, ScreenFlags.CloseOnEscape));

		for (var i = 0; i < nodes.Count(); i += 1)
		{
			var node = nodes.Get(i);
			var record = chunk.Nodes[i];

			try Assert.Equal((int16)node.X, record.X);
			try Assert.Equal((int16)node.Y, record.Y);
			try Assert.Equal((int16)node.Width, record.Width);
			try Assert.Equal((int16)node.Height, record.Height);
			try Assert.Equal(node.Id != null, record.Id != Wire.None);
			try Assert.Equal(node.OnClick != null, record.OnClick != Wire.None);
		}
	}

	return;
}

Error<void> NodeRecordsCarryTheTypeSpecificFields()
{
	var screen = try TestScreen("screen: test\n"
		+ "args: [title]\n"
		+ "region: { at: [8, 112], size: [304, 80] }\n"
		+ "transparent: true\n"
		+ "close_on: [escape]\n"
		+ "passthrough:\n"
		+ "  - { at: [0, 0], size: [320, 16] }\n"
		+ "on_open: opened\n"
		+ "nodes:\n"
		+ "  - window: { id: frame, at: [0, 0], size_tiles: [19, 5], dark: true }\n"
		+ "  - label: { id: heading, at: [8, 4], text: \"$title\", color: 1 }\n"
		+ "  - label: { id: gold, at: [224, 4], bind: \"party[2].gold\", align: right }\n"
		+ "  - label: { id: plain, at: [8, 20], text: \"Hello\" }\n"
		+ "  - button: { id: ok, at: [8, 62], text: T.ok, hotkey: num7, on_click: confirmed }\n"
		+ "  - list: { id: words, at: [8, 17], size: [288, 30], rows: 3, columns: 4, source: \"party.words\", on_select: chosen }\n"
		+ "  - itemgrid: { id: slots, at: [8, 30], cols: 6, rows: 2, source: \"chest.items\", on_select: take, on_drop: drop }\n"
		+ "  - input: { id: answer, at: [8, 50], size: [160, 10], max_length: 24, on_submit: submitted }\n");
	var chunk = try RoundTrip(screen);
	var nodes = chunk.Nodes;

	try Assert.True(ScreenRect.Of(0, 0, 320, 16).Same(chunk.Passthrough[0]), "the passthrough region");
	try Assert.NotEqual(Wire.None, chunk.OnOpen);
	try Assert.Equal(Wire.None, chunk.OnClose);
	try Assert.Strings(new string[] { "Hello" }, chunk.Literals);

	try Assert.Equal((int)NodeType.Window, (int)nodes[0].Type);
	try Assert.Equal((19 << 8) | 5, nodes[0].Extra0);
	try Assert.Equal(1, nodes[0].Extra1);
	try Assert.Equal(304, nodes[0].Width);

	try Assert.True(nodes[1].IsArgumentText());
	try Assert.Equal(0, nodes[1].Text & 0x3FFF);

	try Assert.True(nodes[2].IsBound());
	try Assert.Equal(2, nodes[2].BindArgument);
	try Assert.Equal(2, nodes[2].Extra0);

	try Assert.True(nodes[3].IsLiteralText());
	try Assert.Equal(0, nodes[3].Text & 0x3FFF);

	try Assert.Equal((int)NodeType.Button, (int)nodes[4].Type);
	try Assert.True(nodes[4].IsTableText());
	try Assert.Equal(0x107, nodes[4].Extra0);
	try Assert.NotEqual(Wire.None, nodes[4].OnClick);

	try Assert.Equal((int)NodeType.List, (int)nodes[5].Type);
	try Assert.Equal((4 << 8) | 3, nodes[5].Extra0);
	try Assert.NotEqual(Wire.None, nodes[5].Extra1);

	try Assert.Equal((int)NodeType.ItemGrid, (int)nodes[6].Type);
	try Assert.Equal((6 << 8) | 2, nodes[6].Extra0);
	try Assert.NotEqual(nodes[6].Extra1, nodes[6].Extra2);

	try Assert.Equal((int)NodeType.Input, (int)nodes[7].Type);
	try Assert.Equal(24, nodes[7].Extra0);
	try Assert.NotEqual(Wire.None, nodes[7].Extra1);

	return;
}

Error<void> TheDetailOfAListIsALocalSource()
{
	var nodes = (try RoundTrip(try TestScreen("screen: test\n"
		+ "region: { at: [0, 0], size: [10, 10] }\n"
		+ "nodes:\n"
		+ "  - list: { id: items, at: [0, 0], rows: 3, source: \"party.items\" }\n"
		+ "  - label: { id: detail, at: [0, 20], bind: \"items.detail\" }\n"
		+ "  - label: { id: gold, at: [0, 30], bind: \"party.gold\" }\n"))).Nodes;

	try Assert.False(nodes[0].IsLocalSource());
	try Assert.True(nodes[1].IsLocalSource());
	try Assert.Equal(0, nodes[1].LocalSourceNode());
	try Assert.False(nodes[2].IsLocalSource());

	return;
}

Error<void> TheNameAndDetailOfAnItemGridAreLocalSources()
{
	var nodes = (try RoundTrip(try TestScreen("screen: test\n"
		+ "region: { at: [0, 0], size: [10, 10] }\n"
		+ "nodes:\n"
		+ "  - itemgrid: { id: items, at: [0, 0], cols: 7, rows: 3, source: \"party.items\" }\n"
		+ "  - label: { id: name, at: [0, 20], bind: \"items.name\" }\n"
		+ "  - label: { id: detail, at: [0, 30], bind: \"items.detail\" }\n"
		+ "  - bar: { id: hp_bar, at: [0, 40], size: [40, 8], kind: hp, slot: 1 }\n"))).Nodes;

	try Assert.True(nodes[1].IsLocalSource());
	try Assert.True(nodes[1].IsLocalName());
	try Assert.Equal(0, nodes[1].LocalSourceNode());
	try Assert.True(nodes[2].IsLocalSource());
	try Assert.False(nodes[2].IsLocalName());
	try Assert.Equal(0, nodes[2].LocalSourceNode());
	try Assert.Equal((int)NodeType.Bar, (int)nodes[3].Type);

	return;
}

Error<void> ChildrenPointToTheirParent()
{
	var screen = try TestScreen("screen: test\n"
		+ "region: { at: [0, 0], size: [10, 10] }\n"
		+ "nodes:\n"
		+ "  - container:\n"
		+ "      id: outer\n"
		+ "      nodes:\n"
		+ "        - label: { id: inner, text: \"x\" }\n"
		+ "  - label: { id: last, text: \"y\" }\n");
	var nodes = (try RoundTrip(screen)).Nodes;

	try Assert.Strings(new string[] { "outer", "inner", "last" }, screen.NodeIds);
	try Assert.Equal(Wire.None, nodes[0].Parent);
	try Assert.Equal(0, nodes[1].Parent);
	try Assert.Equal(Wire.None, nodes[2].Parent);

	return;
}

Error<void> NodesWithoutNameKeepTheirIndex()
{
	var screen = try TestScreen("screen: test\n"
		+ "region: { at: [0, 0], size: [10, 10] }\n"
		+ "nodes:\n"
		+ "  - label: { text: \"unnamed\" }\n"
		+ "  - label: { id: named, text: \"named\" }\n");

	try Assert.Strings(new string[] { "", "named" }, screen.NodeIds);
	try Assert.Equal(Wire.None, (try RoundTrip(screen)).Nodes[0].Id);
	try Assert.Equal(1, (try RoundTrip(screen)).Nodes[1].Id);

	return;
}

Error<void> PassthroughRegionsDecideWhereInputGoesDown()
{
	var screen = try TestScreen("screen: test\n"
		+ "region: { at: [0, 0], size: [320, 200] }\n"
		+ "transparent: true\n"
		+ "passthrough:\n"
		+ "  - { at: [0, 0], size: [320, 16] }\n"
		+ "  - { at: [300, 100], size: [20, 50] }\n");

	try Assert.True(screen.PassesThrough(10, 10));
	try Assert.True(screen.PassesThrough(310, 120));
	try Assert.False(screen.PassesThrough(10, 16));
	try Assert.False(screen.PassesThrough(299, 120));

	return;
}

Error<void> BrokenFilesAreRejectedByTheLibrary()
{
	string folder = try ScreenFolder("bad.yaml", "screen: bad\nnodes:\n  - window: { id: frame, at: [0, 0] }\n");
	string message = try Assert.Fails(ScreenLibrary.Load(folder), ErrorKind.InvalidData);

	return Assert.Contains("screen schema", message);
}

Error<void> LiteralTextsMustBeLatin1()
{
	var latin1 = try TestScreen("screen: test\nregion: { at: [0, 0], size: [10, 10] }\nnodes:\n  - label: { text: \"café\" }\n");

	try Assert.Strings(new string[] { "café" }, (try RoundTrip(latin1)).Literals);

	var chinese = try TestScreen("screen: test\nregion: { at: [0, 0], size: [10, 10] }\nnodes:\n  - label: { text: \"中文\" }\n");
	string message = try Assert.Fails(WriteScreen(chinese), ErrorKind.InvalidData);

	return Assert.Contains("E012", message);
}

Error<void> UnknownHotkeysAreRejected()
{
	try Assert.Fails(ScreenKeys.Parse("hyper"), ErrorKind.InvalidData);
	try Assert.Equal((int)'G', try ScreenKeys.Parse("g"));
	try Assert.Equal(27, try ScreenKeys.Parse("esc"));
	try Assert.Equal(0x113, try ScreenKeys.Parse("F3"));

	return;
}

Error<void> DamagedChunksAreRejected()
{
	var library = try ScreenLibrary.Load(RootPath("game/content/screens"));
	var data = try WriteScreen(try FindScreen(library, "conversation"));

	try Assert.Fails(ScreenChunk.Read(Slice(data, 0, 20)), ErrorKind.InvalidChunk);
	try Assert.Fails(ScreenChunk.Read(Slice(data, 0, data.Length - 40)), ErrorKind.InvalidChunk);

	var badType = Slice(data, 0, data.Length);

	// the first node record starts after the 16 header words; the high byte of its first word is the type
	badType[ScreenChunkHeaderWords * 2] = 99;
	try Assert.Fails(ScreenChunk.Read(badType), ErrorKind.InvalidChunk);

	var badOffset = Slice(data, 0, data.Length);

	badOffset[14 * 2 + 1] = (uint8)((int)badOffset[14 * 2 + 1] + 1);
	try Assert.Fails(ScreenChunk.Read(badOffset), ErrorKind.InvalidChunk);

	return;
}
