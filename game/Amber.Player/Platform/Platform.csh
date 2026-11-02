// The platform layer: what differs between the systems the game runs on. A platform shows the
// frames, collects the input and has a clock; the game itself (logic, scripts, the draw list) is the same everywhere.
// Files, the console and the time of day need no layer of their own: the standard library of CShift has them on every
// target, the Amiga included. Implementations: GlfwPlatform (a window on Windows and Linux, Window.csh) and
// HeadlessPlatform (no window: input scripts and screenshots in memory, GameRunner.csh). An Amiga platform would draw
// the draw list with the blitter into bitplanes and set the palette in the copper list.
//
// CShift has interfaces only as constraints of generic parameters (no interface values): RunGame is compiled for each
// platform, the calls are direct.

namespace Amber.Player.Platform;

using System;
using Amber.Base;
using Amber.Player.Graphics;

/// The ticks per second of the game (the PAL frame rate of the Amiga).
const int TicksPerSecond = 50;

/// The size of the virtual screen the game draws (the map editor uses 640x400).
int VirtualScreenWidth = 320;
int VirtualScreenHeight = 200;

interface IPlatform
{
	/// The input of the platform: the game reads it every tick (a handle the platform fills while it polls).
	InputState Input();

	/// False when the user closed the window.
	bool IsOpen();

	/// Collects the events of the system (keys, mouse) into the input.
	void Poll();

	/// The clock in seconds (only differences count); it drives the fixed ticks when no input script runs.
	double Seconds();

	/// True if every frame is shown; false if frames are only rendered for screenshots (no window).
	bool ShowsFrames();

	/// Shows the frame described by the draw list (the platform renders it its own way).
	void Present(DrawList list);

	/// Saves the frame that was just presented as a PNG.
	Error<void> Screenshot(string path);

	/// The frame is complete (swap buffers, wait for the vertical blank).
	void EndFrame();
}

/// The game loop of every platform. With an input script exactly one tick runs per frame (deterministic: the playthrough
/// tests), otherwise 50 fixed ticks per second of the platform's clock. Returns the exit code.
Error<int> RunGame<TPlatform>(ref TPlatform platform, AnyGame game, Optional<InputScript> script)
	where TPlatform : IPlatform
{
	var input = platform.Input();
	double tickLength = 1.0 / (double)TicksPerSecond;
	double accumulator = 0.0;
	double last = platform.Seconds();

	while (platform.IsOpen())
	{
		platform.Poll();

		string screenshot = null;

		if (script is InputScript runner)
		{
			string command = runner.Step(input);

			if (command == "quit")
				return 0;

			if (command != null)
			{
				if (command.StartsWith("debug:"))
					try game.Debug(command.Substring(6));
				else
					screenshot = command;
			}

			input.BeginTick();
			try game.Update(input);
		}
		else
		{
			double now = platform.Seconds();
			double delta = now - last;

			last = now;
			accumulator += delta < 0.25 ? delta : 0.25;

			while (accumulator >= tickLength)
			{
				accumulator -= tickLength;
				input.BeginTick();
				try game.Update(input);

				if (game.QuitRequested())
					return 0;
			}
		}

		if (game.QuitRequested())
			return 0;

		if (platform.ShowsFrames() || screenshot != null)
		{
			var list = DrawList.Create();

			game.Draw(list);
			platform.Present(list);

			if (screenshot != null)
				try platform.Screenshot(screenshot);
		}

		platform.EndFrame();
	}

	return 0;
}
