namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Screens;

// The screen definitions (YAML) must validate against spec/schemas/screen.schema.json (task 2.1): the examples and the
// screens of the prototype pass, broken files are rejected.

void RegisterScreenSchemaTests(ref TestList tests)
{
	foreach (var file in ScreenFiles())
		tests.Theory("ScreenSchema.ScreenFilesValidate", ScreenFilesValidate, file);

	tests.Theory("ScreenSchema.BrokenFilesAreRejected", BrokenFilesAreRejected, "screen: a\nprefab: b\n", "screen and prefab together");
	tests.Theory("ScreenSchema.BrokenFilesAreRejected", BrokenFilesAreRejected, "region: { at: [0, 0], size: [10, 10] }\n", "neither screen nor prefab");
	tests.Theory("ScreenSchema.BrokenFilesAreRejected", BrokenFilesAreRejected, "screen: a\nnodes:\n  - window: { id: frame, at: [0, 0] }\n", "window without size_tiles");
	tests.Theory("ScreenSchema.BrokenFilesAreRejected", BrokenFilesAreRejected, "screen: a\nnodes:\n  - button: { id: b, at: [0, 0], colour: 3 }\n", "unknown property of a node");
	tests.Theory("ScreenSchema.BrokenFilesAreRejected", BrokenFilesAreRejected, "screen: a\nnodes:\n  - label: { at: [0, 0] }\n  - button: {}\n  - image: {}\n  - blob: {}\n", "unknown node kind");
	tests.Theory("ScreenSchema.BrokenFilesAreRejected", BrokenFilesAreRejected, "screen: a\nfade: sideways\n", "invalid enum value");
	tests.Theory("ScreenSchema.BrokenFilesAreRejected", BrokenFilesAreRejected, "screen: 1bad\n", "invalid name");
	tests.Theory("ScreenSchema.BrokenFilesAreRejected", BrokenFilesAreRejected, "screen: a\nregion: { at: [0], size: [10, 10] }\n", "point with one number");
	tests.Theory("ScreenSchema.BrokenFilesAreRejected", BrokenFilesAreRejected, "screen: a\nnodes:\n  - itemgrid: { id: g, at: [0, 0], cols: 2, rows: 2 }\n", "itemgrid without source");
	tests.Fact("ScreenSchema.ItemGridAndInputAreAccepted", ItemGridAndInputAreAccepted);
}

/// The YAML files directly in examples/screens and game/content/screens, relative to the root.
List<string> ScreenFiles()
{
	var files = List<string>.Create();

	foreach (var folder in new string[] { "examples/screens", "game/content/screens" })
	{
		foreach (var file in RelativeFiles(folder, ".yaml"))
		{
			if (Path.GetDirectory(file) == folder)
				files.Add(file);
		}
	}

	return files;
}

Error<void> ScreenFilesValidate(string[] arguments)
{
	var problems = ScreenSchema.Validate(try ReadRootText(arguments[0]));

	return Assert.True(problems.Count() == 0, arguments[0] + ": " + JoinList("; ", problems));
}

Error<void> BrokenFilesAreRejected(string[] arguments)
{
	return Assert.True(ScreenSchema.Validate(arguments[0]).Count() > 0, arguments[1]);
}

Error<void> ItemGridAndInputAreAccepted()
{
	string yaml = "screen: a\n"
		+ "nodes:\n"
		+ "  - itemgrid: { id: g, at: [0, 0], cols: 2, rows: 2, source: \"party.items\", on_select: pick, on_drop: drop }\n"
		+ "  - input: { id: i, at: [0, 20], max_length: 12, on_submit: submit }";

	return Assert.Empty(ScreenSchema.Validate(yaml));
}
