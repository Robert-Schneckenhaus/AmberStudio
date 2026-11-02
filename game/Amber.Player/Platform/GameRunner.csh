// Runs the game on a platform (Platform.csh): headless (an input script drives it tick by tick as fast as possible,
// screenshots are rendered in memory) or in a window (Window.csh). With an input script the run is deterministic: one
// tick per frame.

namespace Amber.Player.Platform;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Editor;
using Amber.Player.Game;
using Amber.Player.Graphics;

/// The game or the map editor, whichever runs (C#: IGame; CShift has no interface values, so this struct forwards to the
/// one that is set).
struct AnyGame
{
	bool IsEditor;
	PrototypeGame Game;
	MapEditorGame Editor;

	static AnyGame OfGame(PrototypeGame game)
	{
		return AnyGame { IsEditor = false, Game = game };
	}

	static AnyGame OfEditor(MapEditorGame editor)
	{
		return AnyGame { IsEditor = true, Editor = editor };
	}

	Error<void> Update(InputState input)
	{
		if (IsEditor)
			return Editor.Update(input);

		return Game.Update(input);
	}

	Error<void> Debug(string command)
	{
		if (IsEditor)
			return Editor.Debug(command);

		return Game.Debug(command);
	}

	void Draw(DrawList list)
	{
		if (IsEditor)
			Editor.Draw(list);
		else
			Game.Draw(list);
	}

	bool QuitRequested()
	{
		return IsEditor ? Editor.QuitRequested() : Game.QuitRequested();
	}
}

/// Renders a draw list into a new frame (320x200, the editor 640x400) with the software renderer.
Image RenderList(DrawList list, int width, int height)
{
	var frame = Image.Create(width, height);

	frame.FillRect(0, 0, width, height, Color.Of(0, 0, 0));
	list.Render(frame);

	return frame;
}

/// The picture scaled up by a whole factor (nearest neighbor).
Image ScaleImage(Image source, int scale)
{
	if (scale <= 1)
		return source;

	var result = Image.Create(source.Width * scale, source.Height * scale);

	for (var y = 0; y < result.Height; y += 1)
	{
		int sourceRow = y / scale * source.Width;

		for (var x = 0; x < result.Width; x += 1)
		{
			int from = (sourceRow + x / scale) * 4;
			int to = (y * result.Width + x) * 4;

			result.Data[to] = source.Data[from];
			result.Data[to + 1] = source.Data[from + 1];
			result.Data[to + 2] = source.Data[from + 2];
			result.Data[to + 3] = 255;
		}
	}

	return result;
}

Error<void> SaveScreenshot(Image frame, string path, int scale)
{
	string directory = Path.GetDirectory(path);

	if (directory.Length > 0 && !Directory.Exists(directory))
		Directory.Create(directory);

	try SavePng(path, ScaleImage(frame, scale));
	Console.WriteLine("Screenshot: " + path);

	return;
}

/// No window: the input comes from the input script only, frames are rendered in memory when a screenshot is taken.
struct HeadlessPlatform : IPlatform
{
	InputState _input;
	int _scale;
	Image[] _frame;

	static HeadlessPlatform Create(int scale)
	{
		return HeadlessPlatform { _input = InputState.Create(), _scale = scale, _frame = new Image[1] };
	}

	InputState Input()
	{
		return _input;
	}

	bool IsOpen()
	{
		return true;
	}

	void Poll()
	{
	}

	double Seconds()
	{
		return 0.0;
	}

	bool ShowsFrames()
	{
		return false;
	}

	void Present(DrawList list)
	{
		_frame[0] = RenderList(list, VirtualScreenWidth, VirtualScreenHeight);
	}

	Error<void> Screenshot(string path)
	{
		return SaveScreenshot(_frame[0], path, _scale);
	}

	void EndFrame()
	{
	}
}

/// Runs the game with the input script without a window. Returns the exit code (a failed expectation is an error).
Error<int> RunHeadless(AnyGame game, LaunchOptions options)
{
	if (options.Script == null)
		return error("--headless needs an input script (--script file).", (int)ErrorKind.Argument);

	Optional<InputScript> script = try InputScript.Load(options.Script);
	var platform = HeadlessPlatform.Create(options.Scale);

	return RunGame(ref platform, game, script);
}
