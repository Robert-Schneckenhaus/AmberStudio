// The pictures of the actors: placeholder figures made of colored rectangles, or characters of the Mana Seed character base
// ("paper doll", a licensed pack which is not part of the repository) composed from their layers.

namespace Amber.Player.Graphics;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Game;
using Amber.Player.Platform;

const int CharacterFrameSize = 64;
const string CharacterPackName = "FREE Mana Seed Character Base Demo 2.0";

/// The folder of the character pack, or null if it is not installed or AMBERWORLDS_DUMMY_CHARACTERS=1.
string CharacterPackDirectory()
{
	if (Process.GetEnv("AMBERWORLDS_DUMMY_CHARACTERS") is string dummy && dummy == "1")
		return null;

	string path = Path.Combine(Path.Combine(RepositoryRoot, "assets"), CharacterPackName);

	return Directory.Exists(path) ? path : null;
}

/// The file of a layer written as "layer/part/variant", for example "4har/bob1/3" for char_a_p1/4har/char_a_p1_4har_bob1_v03.png.
Error<string> CharacterLayerPath(string pack, string layer)
{
	var parts = layer.Split("/");

	int variant = -1;

	if (parts.Length == 3 && TryParseInt(parts[2].ToString()) is int value)
		variant = value;

	if (variant < 0)
		return error("Character layer '" + layer + "' must be written as layer/part/variant.", (int)ErrorKind.InvalidData);
	string page = "char_a_p1";
	string file = page + "_" + parts[0] + "_" + parts[1] + "_v" + ZeroPad(variant, 2) + ".png";

	// the body sits in the page folder, all other layers in a folder named like the layer
	return parts[0] == "0bas" ? Path.Combine(Path.Combine(pack, page), file) : Path.Combine(Path.Combine(Path.Combine(pack, page), parts[0].ToString()), file);
}

/// Composes the layers (lowest first) into one sheet (straight alpha "over").
Error<Image> ComposeCharacter(string pack, string[] layers)
{
	bool first = true;
	var canvas = Image.Empty();

	foreach (var layer in layers)
	{
		var sheet = try LoadPng(try CharacterLayerPath(pack, layer));
		var source = sheet.Data;

		if (first)
		{
			canvas = Image.Create(sheet.Width, sheet.Height);
			first = false;
		}

		for (var i = 0; i + 3 < source.Length && i + 3 < canvas.Data.Length; i += 4)
		{
			int alpha = (int)source[i + 3];

			if (alpha == 0)
				continue;

			if (alpha == 255 || canvas.Data[i + 3] == 0)
			{
				canvas.Data[i] = source[i];
				canvas.Data[i + 1] = source[i + 1];
				canvas.Data[i + 2] = source[i + 2];
				canvas.Data[i + 3] = source[i + 3];

				continue;
			}

			int back = (int)canvas.Data[i + 3];
			int outAlpha = alpha + back * (255 - alpha) / 255;

			for (var channel = 0; channel < 3; channel += 1)
				canvas.Data[i + channel] = (uint8)(((int)source[i + channel] * alpha + (int)canvas.Data[i + channel] * back * (255 - alpha) / 255) / (outAlpha > 1 ? outAlpha : 1));

			canvas.Data[i + 3] = (uint8)outAlpha;
		}
	}

	if (first)
		return error("A character needs at least one layer.", (int)ErrorKind.InvalidData);

	return canvas;
}

/// A placeholder figure: head, body, legs and eyes which show the direction (C#: DummyActorArt).
ActorArt DummyActorArt(Color body, Color hair)
{
	var stand = new Image[4];
	var walk = new Image[16];
	var walkSequence = new int[] { 1, 0, 2, 0 };

	for (var d = 0; d < 4; d += 1)
	{
		var frames = new Image[3];

		for (var frame = 0; frame < 3; frame += 1)
			frames[frame] = DrawDummy((Direction)d, frame, body, hair);

		stand[d] = frames[0];

		for (var i = 0; i < 4; i += 1)
			walk[d * 4 + i] = frames[walkSequence[i]];
	}

	return ActorArt { Width = 16, Height = 24, OffsetX = 0, FootMargin = 0, WalkFrameCount = 4, TicksPerFrame = 4, Stand = stand, Walk = walk, Run = walk };
}

Image DrawDummy(Direction direction, int frame, Color body, Color hair)
{
	int width = 16;
	int height = 24;
	var image = Image.Create(width, height);
	var skin = Color.Of(240, 200, 160);
	var dark = Color.Of(30, 24, 40);
	var pants = Color.Of(70, 60, 90);

	// legs
	int leftLegTop = frame == 1 ? 19 : 20;
	int rightLegTop = frame == 2 ? 19 : 20;

	image.FillRect(5, leftLegTop, 3, 22 - leftLegTop, pants);
	image.FillRect(9, rightLegTop, 3, 22 - rightLegTop, pants);

	// body and arms
	image.FillRect(4, 11, 9, 9, body);
	image.FillRect(3, 12, 1, 6, body);
	image.FillRect(13, 12, 1, 6, body);

	// head
	image.FillRect(4, 2, 8, 9, skin);

	if (direction == Direction.Up)
		image.FillRect(4, 2, 8, 8, hair);
	else if (direction == Direction.Down)
	{
		image.FillRect(4, 2, 8, 2, hair);
		image.Set(6, 6, dark);
		image.Set(9, 6, dark);
	}
	else if (direction == Direction.Left)
	{
		image.FillRect(4, 2, 8, 2, hair);
		image.FillRect(8, 4, 4, 5, hair);
		image.Set(5, 6, dark);
	}
	else
	{
		image.FillRect(4, 2, 8, 2, hair);
		image.FillRect(4, 4, 4, 5, hair);
		image.Set(10, 6, dark);
	}

	// outline
	var outlined = image.Clone();

	for (var y = 0; y < height; y += 1)
	{
		for (var x = 0; x < width; x += 1)
		{
			if (image.Alpha(x, y) != 0)
				continue;

			bool touches = (x > 0 && image.Alpha(x - 1, y) != 0) || (x < width - 1 && image.Alpha(x + 1, y) != 0) || (y > 0 && image.Alpha(x, y - 1) != 0)
				|| (y < height - 1 && image.Alpha(x, y + 1) != 0);

			if (touches)
				outlined.Set(x, y, dark);
		}
	}

	return outlined;
}

/// A character of the Mana Seed character base, composed from its paper doll layers. Uses the standing frame, the 6 frame
/// walk cycle and the run cycle (walk frames 1, 2, 7, 4, 5, 8) of page 1. All frames are cut to one common box.
Error<ActorArt> SheetActorArt(string pack, string[] layers)
{
	var sheet = try ComposeCharacter(pack, layers);
	// rows of the page: down, up, right, left (by the direction values up, right, down, left)
	var sheetRows = new int[] { 1, 2, 0, 3 };
	var walkColumns = new int[] { 0, 1, 2, 3, 4, 5 };
	var runColumns = new int[] { 0, 1, 6, 3, 4, 7 };
	// the feet stand this many pixels above the bottom edge of their tile
	int feetLift = 2;
	var standFrames = new Image[4];
	var walkFrames = new Image[24];
	var runFrames = new Image[24];

	for (var d = 0; d < 4; d += 1)
	{
		int row = sheetRows[d];

		standFrames[d] = sheet.Slice(0, row * CharacterFrameSize, CharacterFrameSize, CharacterFrameSize);

		for (var i = 0; i < 6; i += 1)
		{
			walkFrames[d * 6 + i] = sheet.Slice(walkColumns[i] * CharacterFrameSize, (4 + row) * CharacterFrameSize, CharacterFrameSize, CharacterFrameSize);
			runFrames[d * 6 + i] = sheet.Slice(runColumns[i] * CharacterFrameSize, (4 + row) * CharacterFrameSize, CharacterFrameSize, CharacterFrameSize);
		}
	}

	int minX = 0x7FFFFFFF;
	int minY = 0x7FFFFFFF;
	int maxX = 0;
	int maxY = 0;
	var all = List<Image>.Create();

	foreach (var frame in standFrames)
		all.Add(frame);

	foreach (var frame in walkFrames)
		all.Add(frame);

	foreach (var frame in runFrames)
		all.Add(frame);

	foreach (var frame in all)
	{
		if (VisibleBounds(frame) is PixelBounds bounds)
		{
			minX = Min(minX, bounds.X);
			minY = Min(minY, bounds.Y);
			maxX = Max(maxX, bounds.X + bounds.Width);
			maxY = Max(maxY, bounds.Y + bounds.Height);
		}
	}

	if (maxX == 0)
		return error("The character has no visible pixels.", (int)ErrorKind.InvalidData);

	int boxWidth = maxX - minX;
	int boxHeight = maxY - minY;
	// the feet are the lowest visible row of the standing image facing down
	int footMargin = 0;

	if (VisibleBounds(standFrames[(int)Direction.Down]) is PixelBounds stand)
		footMargin = minY + boxHeight - (stand.Y + stand.Height) - feetLift;

	var stands = new Image[4];
	var walks = new Image[24];
	var runs = new Image[24];

	for (var i = 0; i < 4; i += 1)
		stands[i] = standFrames[i].Slice(minX, minY, boxWidth, boxHeight);

	for (var i = 0; i < 24; i += 1)
	{
		walks[i] = walkFrames[i].Slice(minX, minY, boxWidth, boxHeight);
		runs[i] = runFrames[i].Slice(minX, minY, boxWidth, boxHeight);
	}

	return ActorArt
	{
		Width = boxWidth, Height = boxHeight, OffsetX = minX - (CharacterFrameSize - 16) / 2, FootMargin = footMargin, WalkFrameCount = 6, TicksPerFrame = 4,
		Stand = stands, Walk = walks, Run = runs
	};
}
