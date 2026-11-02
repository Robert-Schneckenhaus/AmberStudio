namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Screens;

void RegisterUiThemeTests(ref TestList tests)
{
	tests.Fact("UiTheme.TheThemeIsRead", TheThemeIsRead);
	tests.Theory("UiTheme.MistakesAreNamed", MistakesAreNamed, "looks:\n  a:\n    parts:\n      - rect: { colour: \"#000000\" }", "unknown key 'colour'");
	tests.Theory("UiTheme.MistakesAreNamed", MistakesAreNamed, "looks:\n  a:\n    parts:\n      - image: { sprite: nope }", "sprite 'nope' is not defined");
	tests.Theory("UiTheme.MistakesAreNamed", MistakesAreNamed, "colors:\n  a: \"#12\"", "is not a color");
	tests.Theory("UiTheme.MistakesAreNamed", MistakesAreNamed, "looks:\n  a:\n    fallback: b\n    parts: []", "fallback look 'b' does not exist");
	tests.Theory("UiTheme.MistakesAreNamed", MistakesAreNamed, "looks:\n  a:\n    fallback: b\n    parts: []\n  b:\n    fallback: a\n    parts: []", "cycle");
	tests.Theory("UiTheme.MistakesAreNamed", MistakesAreNamed, "defaults:\n  window: missing", "default look of 'window'");
	tests.Theory("UiTheme.MistakesAreNamed", MistakesAreNamed, "looks:\n  a:\n    parts:\n      - rect: { color: \"#000000\", layer: middle }", "layer is 'back' or 'front'");
	tests.Theory("UiTheme.MistakesAreNamed", MistakesAreNamed, "looks:\n  a:\n    parts:\n      - rect: { color: \"#000000\" }\n        frame: { color: \"#000000\" }", "every part is one of");
	tests.Fact("UiTheme.ALookWithoutItsSpritesFallsBack", ALookWithoutItsSpritesFallsBack);
	tests.Fact("UiTheme.ABorderKeepsTheCornersAndRepeatsTheEdges", ABorderKeepsTheCornersAndRepeatsTheEdges);
	tests.Fact("UiTheme.TheLastPieceEndsAtTheEdgeWhenTheLengthIsNotAMultiple", TheLastPieceEndsAtTheEdgeWhenTheLengthIsNotAMultiple);
	tests.Fact("UiTheme.TheThicknessOfTheBorderDecidesTheInsetOfTheFill", TheThicknessOfTheBorderDecidesTheInsetOfTheFill);
	tests.Fact("UiTheme.AFrameIsFourLinesAndTooSmallAreasAreSkipped", AFrameIsFourLinesAndTooSmallAreasAreSkipped);
	tests.Fact("UiTheme.StatesReplaceTheParts", StatesReplaceTheParts);
	tests.Fact("UiTheme.AnImageCanBeAlignedOrStretched", AnImageCanBeAlignedOrStretched);
	tests.Fact("UiTheme.ATileFillCoversTheAreaWithoutLeavingIt", ATileFillCoversTheAreaWithoutLeavingIt);
	tests.Fact("UiTheme.ColorsHaveSeveralForms", ColorsHaveSeveralForms);
}

const string ThemeText = "sprite_folder: \"UiGfx\"\n"
	+ "sprites:\n"
	+ "  tl: 002.png\n"
	+ "  l: 003.png\n"
	+ "  bl: 004.png\n"
	+ "  t: 005.png\n"
	+ "  b: 006.png\n"
	+ "  tr: 007.png\n"
	+ "  r: 008.png\n"
	+ "  br: 009.png\n"
	+ "  checker: { file: 001.png, x: 0, y: 0, w: 16, h: 6 }\n"
	+ "colors:\n"
	+ "  stone: \"#666655\"\n"
	+ "  dark: \"0x111122\"\n"
	+ "defaults:\n"
	+ "  window: window\n"
	+ "  button: button\n"
	+ "looks:\n"
	+ "  window:\n"
	+ "    fallback: flat\n"
	+ "    parts:\n"
	+ "      - rect: { color: stone, inset: border }\n"
	+ "      - border: { top_left: tl, left: l, bottom_left: bl, top: t, bottom: b, top_right: tr, right: r, bottom_right: br }\n"
	+ "  flat:\n"
	+ "    fallback: none\n"
	+ "    parts:\n"
	+ "      - frame: { color: \"#d6aa5a\", width: 2 }\n"
	+ "      - rect: { color: dark, inset: 2 }\n"
	+ "  button:\n"
	+ "    parts:\n"
	+ "      - rect: { color: \"#888877\" }\n"
	+ "    states:\n"
	+ "      focused:\n"
	+ "        - rect: { color: \"#aaaa99\" }\n"
	+ "        - image: { sprite: checker, align: top_left, dx: 1, dy: 2 }";

/// The checker is 16 x 6, every other sprite 16 x 16 (C#: Size).
SpriteSizes TestSizes()
{
	var sizes = SpriteSizes.WithDefault(16, 16);

	sizes.Set("checker", 16, 6);

	return sizes;
}

Error<LookDefinition> LookOf(UiTheme theme, string name)
{
	if (theme.Looks.TryGet(name) is LookDefinition look)
		return look;

	return error("the theme has no look " + name, -1);
}

/// The elements of a look placed in the area.
Error<List<LookElement>> PlaceLook(UiTheme theme, string look, string state, int x, int y, int width, int height)
{
	return LookLayout.Place(try LookOf(theme, look), state, x, y, width, height, TestSizes());
}

/// There is an element with the sprite at the position (C#: Elements).
bool HasElement(List<LookElement> elements, string sprite, int x, int y)
{
	foreach (var element in elements)
	{
		if (element.Sprite == sprite && element.X == x && element.Y == y)
			return true;
	}

	return false;
}

/// The positions (X or Y) of the elements with the sprite, sorted.
int[] Positions(List<LookElement> elements, string sprite, bool horizontal)
{
	var values = List<int>.Create();

	foreach (var element in elements)
	{
		if (element.Sprite == sprite)
			values.Add(horizontal ? element.X : element.Y);
	}

	return SortArray(ArrayOf(values), CompareInt);
}

int SpriteCount(List<LookElement> elements)
{
	int count = 0;

	foreach (var element in elements)
	{
		if (element.IsSprite())
			count += 1;
	}

	return count;
}

Error<void> SameColor(LookColor expected, LookColor actual)
{
	return Assert.True(expected.Same(actual), "expected the color " + expected.R + "," + expected.G + "," + expected.B + "," + expected.A
		+ ", actual " + actual.R + "," + actual.G + "," + actual.B + "," + actual.A);
}

Error<void> TheThemeIsRead()
{
	var theme = try UiTheme.Parse(ThemeText);

	try Assert.Equal("UiGfx", theme.SpriteFolder);
	try Assert.Equal(9, theme.Sprites.Count());

	var checker = theme.Sprites.GetOrDefault("checker", new SpriteSource());

	try Assert.Equal("001.png", checker.File);
	try Assert.Ints(new int[] { 0, 0, 16, 6 }, new int[] { checker.X, checker.Y, checker.Width, checker.Height });
	try Assert.True(theme.Sprites.GetOrDefault("tl", new SpriteSource()).WholeFile());
	try Assert.Equal("window", theme.Defaults.GetOrDefault("window", null));
	try Assert.Equal(3, theme.Looks.Count());

	var window = try LookOf(theme, "window");
	var flat = try LookOf(theme, "flat");
	var button = try LookOf(theme, "button");

	try SameColor(LookColor.Of(0x66, 0x66, 0x55), window.Parts[0].Color);
	try Assert.True(window.Parts[0].Inset.FromBorder);
	try SameColor(LookColor.Of(0x11, 0x11, 0x22), flat.Parts[1].Color);
	try Assert.Equal(2, flat.Parts[1].Inset.Left);
	try Assert.Equal(8, window.SpriteNames().Count());
	try Assert.Equal(2, button.PartsFor("focused").Length);
	try Assert.Equal(1, button.PartsFor("hover").Length);

	return;
}

Error<void> MistakesAreNamed(string[] arguments)
{
	string message = try Assert.Fails(UiTheme.Parse(arguments[0]), ErrorKind.InvalidData);

	return Assert.Contains(arguments[1], message);
}

/// The name of the resolved look, null if there is none.
string ResolvedName(UiTheme theme, string name, string kind, SpriteAvailability available)
{
	if (theme.Resolve(name, kind, available) is LookDefinition look)
		return look.Name;

	return null;
}

Error<void> ALookWithoutItsSpritesFallsBack()
{
	var theme = try UiTheme.Parse(ThemeText);

	try Assert.Equal("window", ResolvedName(theme, null, "window", SpriteAvailability.Everything()));
	try Assert.Equal("flat", ResolvedName(theme, null, "window", SpriteAvailability.AllBut(new string[] { "tl" })));
	try Assert.Equal("flat", ResolvedName(theme, "flat", "button", SpriteAvailability.Nothing()));
	try Assert.Null(ResolvedName(theme, "none", "window", SpriteAvailability.Everything()));
	try Assert.Null(ResolvedName(theme, null, "bar", SpriteAvailability.Everything()));
	try Assert.Null(ResolvedName(theme, null, "button", SpriteAvailability.AllBut(new string[] { "checker" })));
	try Assert.Equal("flat", ResolvedName(theme, "window", "window", SpriteAvailability.Nothing()));

	return;
}

Error<void> ABorderKeepsTheCornersAndRepeatsTheEdges()
{
	var theme = try UiTheme.Parse(ThemeText);
	var elements = try PlaceLook(theme, "window", "normal", 8, 4, 64, 48);

	// fill inside the border
	var fills = List<LookElement>.Create();

	foreach (var element in elements)
	{
		if (!element.IsSprite())
			fills.Add(element);
	}

	var fill = try Assert.Single(fills);

	try Assert.Ints(new int[] { 8 + 16, 4 + 16, 64 - 32, 48 - 32 }, new int[] { fill.X, fill.Y, fill.Width, fill.Height });

	// corners
	try Assert.True(HasElement(elements, "tl", 8, 4));
	try Assert.True(HasElement(elements, "tr", 8 + 64 - 16, 4));
	try Assert.True(HasElement(elements, "bl", 8, 4 + 48 - 16));
	try Assert.True(HasElement(elements, "br", 8 + 64 - 16, 4 + 48 - 16));

	// the top edge is 32 wide between the corners: two pieces; the left edge is 16 high: one piece
	try Assert.Ints(new int[] { 24, 40 }, Positions(elements, "t", true));
	try Assert.Ints(new int[] { 20 }, Positions(elements, "l", false));
	try Assert.Equal(10, SpriteCount(elements));

	return;
}

Error<void> TheLastPieceEndsAtTheEdgeWhenTheLengthIsNotAMultiple()
{
	try Assert.Ints(new int[] { 0, 16, 24 }, LookLayout.Steps(0, 40, 16));
	try Assert.Ints(new int[] { 10 }, LookLayout.Steps(10, 16, 16));
	try Assert.Ints(new int[] { 2 }, LookLayout.Steps(10, 8, 16));
	try Assert.Empty(LookLayout.Steps(0, 0, 16));

	var theme = try UiTheme.Parse(ThemeText);
	var elements = try PlaceLook(theme, "window", "normal", 0, 0, 72, 32);

	// 72 - 32 = 40 between the corners: pieces at 16, 32 and the last one flush at 72 - 16 - 16 = 40
	return Assert.Ints(new int[] { 16, 32, 40 }, Positions(elements, "t", true));
}

Error<void> TheThicknessOfTheBorderDecidesTheInsetOfTheFill()
{
	var theme = try UiTheme.Parse(ThemeText);

	try Assert.True(LookInset.Of(16, 16, 16, 16).Same(LookLayout.BorderThickness((try LookOf(theme, "window")).Parts, TestSizes())), "the border is 16 on every side");
	try Assert.True(LookInset.None().Same(LookLayout.BorderThickness((try LookOf(theme, "button")).Parts, TestSizes())), "the button has no border");

	return;
}

Error<void> AFrameIsFourLinesAndTooSmallAreasAreSkipped()
{
	var theme = try UiTheme.Parse(ThemeText);
	var elements = try PlaceLook(theme, "flat", "normal", 0, 0, 20, 10);
	int rank0 = 0;
	int rank1 = 0;

	foreach (var element in elements)
	{
		if (element.Rank == 0)
			rank0 += 1;

		if (element.Rank == 1)
			rank1 += 1;
	}

	try Assert.Equal(5, elements.Count());
	try Assert.Equal(4, rank0);
	try Assert.Equal(1, rank1);

	var small = try PlaceLook(theme, "window", "normal", 0, 0, 32, 32);

	try Assert.Equal(small.Count(), SpriteCount(small));

	return;
}

Error<void> StatesReplaceTheParts()
{
	var theme = try UiTheme.Parse(ThemeText);
	var normal = try PlaceLook(theme, "button", "normal", 0, 0, 40, 14);
	var focused = try PlaceLook(theme, "button", "focused", 5, 6, 40, 14);
	var hover = try PlaceLook(theme, "button", "hover", 0, 0, 40, 14);

	try Assert.Equal(1, normal.Count());
	try SameColor(LookColor.Of(0x88, 0x88, 0x77), normal.Get(0).Color);
	try SameColor(LookColor.Of(0xaa, 0xaa, 0x99), focused.Get(0).Color);
	try Assert.True(HasElement(focused, "checker", 6, 8));
	try Assert.Equal(normal.Count(), hover.Count());

	for (var i = 0; i < normal.Count(); i += 1)
		try Assert.True(normal.Get(i).Same(hover.Get(i)), "hover is the same as normal");

	return;
}

Error<void> AnImageCanBeAlignedOrStretched()
{
	var theme = try UiTheme.Parse("sprites:\n"
		+ "  icon: a.png\n"
		+ "looks:\n"
		+ "  centered:\n"
		+ "    parts:\n"
		+ "      - image: { sprite: icon }\n"
		+ "  corner:\n"
		+ "    parts:\n"
		+ "      - image: { sprite: icon, align: bottom_right, inset: 2 }\n"
		+ "  stretched:\n"
		+ "    parts:\n"
		+ "      - image: { sprite: icon, stretch: true, inset: [1, 2] }");

	var centered = (try PlaceLook(theme, "centered", "normal", 0, 0, 40, 20)).Get(0);
	var corner = (try PlaceLook(theme, "corner", "normal", 0, 0, 40, 20)).Get(0);
	var stretched = (try PlaceLook(theme, "stretched", "normal", 0, 0, 40, 20)).Get(0);

	try Assert.Ints(new int[] { 12, 2, 16, 16 }, new int[] { centered.X, centered.Y, centered.Width, centered.Height });
	try Assert.Ints(new int[] { 40 - 2 - 16, 20 - 2 - 16 }, new int[] { corner.X, corner.Y });
	try Assert.Ints(new int[] { 1, 2, 38, 16 }, new int[] { stretched.X, stretched.Y, stretched.Width, stretched.Height });

	return;
}

Error<void> ATileFillCoversTheAreaWithoutLeavingIt()
{
	var theme = try UiTheme.Parse("sprites:\n"
		+ "  bricks: b.png\n"
		+ "looks:\n"
		+ "  wall:\n"
		+ "    parts:\n"
		+ "      - tile: { sprite: bricks, inset: 2 }");
	var elements = try PlaceLook(theme, "wall", "normal", 0, 0, 40, 36);

	// 36 wide and 32 high area: 3 x 2 pieces of 16
	try Assert.Equal(6, elements.Count());

	var xs = List<int>.Create();

	foreach (var element in elements)
	{
		try Assert.True(element.X >= 2 && element.X <= 2 + 36 - 16, "x " + element.X + " inside the area");
		try Assert.True(element.Y >= 2 && element.Y <= 2 + 32 - 16, "y " + element.Y + " inside the area");

		if (!xs.Contains(element.X))
			xs.Add(element.X);
	}

	return Assert.Ints(new int[] { 2, 18, 22 }, SortArray(ArrayOf(xs), CompareInt));
}

Error<void> ColorsHaveSeveralForms()
{
	var colors = Dictionary<string, LookColor>.Create();

	colors.Set("red", LookColor.Of(255, 0, 0));

	try SameColor(LookColor.Of(255, 0, 0), try UiTheme.ParseColor("red", colors, ""));
	try SameColor(LookColor.Of(0x66, 0x66, 0x55), try UiTheme.ParseColor("#666655", colors, ""));
	try SameColor(LookColor.Of(0x66, 0x66, 0x55), try UiTheme.ParseColor("0x666655", colors, ""));
	try SameColor(LookColor.OfAlpha(1, 2, 3, 128), try UiTheme.ParseColor("#01020380", colors, ""));

	return;
}
