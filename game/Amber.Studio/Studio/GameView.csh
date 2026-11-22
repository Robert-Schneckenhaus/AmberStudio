// The game inside the studio: a third platform next to the window and the headless runner. It cooks the content as the
// game does at its start, puts the party on a map at a cell (the one under the mouse: "play from here"), runs 50 ticks
// per second of the clock of System.Ui and draws the virtual screen scaled into the middle area. The keys and the
// mouse go to the game while it has the area; Escape in the world ends it (the game quits), as F5 starts it again.

namespace Amber.Studio;

using System;
using System.Image;
using System.Ui;
using Amber.Base;
using Amber.Player.Game;

struct GameViewValues
{
	bool Running;
	bool HasGame;
	double Last;
	double Accumulator;
	/// The window reports held keys (UiInput.Held); without them a key counts as held while it repeats.
	bool SawHeld;
	string Status;
	int Ticks;
	bool MouseDown;
	bool RightDown;
	/// Where the picture was drawn in the last frame (pixels of the frame).
	Rect Screen;
	/// The touch controls over the picture (a phone has no keys): the key the finger holds, Unknown for none.
	bool Touch;
	Amber.Player.Platform.Key TouchKey;
}

/// A button of the touch controls: while it is held, its key is down for the game.
struct PadButton
{
	Rect Rect;
	Amber.Player.Platform.Key Key;
	string Label;
}

/// A handle.
struct GameView
{
	GameViewValues[] _s;
	PrototypeGame[] _game;
	Amber.Player.Platform.InputState Input;
	/// The keys of System.Ui that are down for the game, and when each was pressed last (seconds).
	Dictionary<int, bool> Down;
	Dictionary<int, double> PressedAt;
	Image[] _frame;

	static GameView Create()
	{
		var values = new GameViewValues[1];

		values[0].Status = "";
		values[0].Touch = TouchScreen;

		return GameView
		{
			_s = values, _game = new PrototypeGame[1], Input = Amber.Player.Platform.InputState.Create(), Down = Dictionary<int, bool>.Create(),
			PressedAt = Dictionary<int, double>.Create(),
			_frame = new Image[1]
		};
	}

	bool Running()
	{
		return _s[0].Running;
	}

	string Status()
	{
		return _s[0].Status;
	}

	int Ticks()
	{
		return _s[0].Ticks;
	}

	Rect ScreenRect()
	{
		return _s[0].Screen;
	}

	PrototypeGame Game()
	{
		return _game[0];
	}

	bool Touch()
	{
		return _s[0].Touch;
	}

	void SetTouch(bool on)
	{
		_s[0].Touch = on;
	}

	/// The touch controls over the picture: a cross for walking (and turning in 3D) at the bottom left, the buttons for
	/// Space (look, talk, next text), Escape and T (target) at the bottom right.
	List<PadButton> Pad(Rect screen)
	{
		var buttons = List<PadButton>.Create();
		int size = Math.Max(24, screen.Height / 7);
		int gap = size / 8;
		int left = screen.X + gap * 2;
		int bottom = screen.Y + screen.Height - gap * 2;
		int right = screen.X + screen.Width - gap * 2;

		buttons.Add(PadButton { Rect = Rect.Create(left + size + gap, bottom - 3 * size - 2 * gap, size, size), Key = Amber.Player.Platform.Key.Up, Label = "^" });
		buttons.Add(PadButton { Rect = Rect.Create(left, bottom - 2 * size - gap, size, size), Key = Amber.Player.Platform.Key.Left, Label = "<" });
		buttons.Add(PadButton { Rect = Rect.Create(left + 2 * (size + gap), bottom - 2 * size - gap, size, size), Key = Amber.Player.Platform.Key.Right, Label = ">" });
		buttons.Add(PadButton { Rect = Rect.Create(left + size + gap, bottom - size, size, size), Key = Amber.Player.Platform.Key.Down, Label = "v" });
		buttons.Add(PadButton { Rect = Rect.Create(right - size * 3 / 2, bottom - size * 3 / 2, size * 3 / 2, size * 3 / 2), Key = Amber.Player.Platform.Key.Space, Label = "OK" });
		buttons.Add(PadButton { Rect = Rect.Create(right - size * 3 - gap, bottom - size, size, size), Key = Amber.Player.Platform.Key.Escape, Label = "Esc" });
		buttons.Add(PadButton { Rect = Rect.Create(right - size, bottom - size * 5 / 2 - gap, size, size), Key = Amber.Player.Platform.Key.T, Label = "T" });

		return buttons;
	}

	/// The touch controls: the button under a held finger (or a tap of this frame) holds its key; returns true if the
	/// finger is on a button, so that the tap does not also go to the game as a click.
	bool FeedTouch(UiInput input, Rect screen)
	{
		var key = Amber.Player.Platform.Key.Unknown;
		bool onPad = false;

		if (input.MouseDown || input.MousePressed)
		{
			foreach (var button in Pad(screen))
			{
				if (button.Rect.Contains(input.MouseX, input.MouseY))
				{
					key = button.Key;
					onPad = true;
				}
			}
		}

		if (key != _s[0].TouchKey)
		{
			if (_s[0].TouchKey != Amber.Player.Platform.Key.Unknown)
				Input.KeyUp(_s[0].TouchKey);

			if (key != Amber.Player.Platform.Key.Unknown)
				Input.KeyDown(key);

			_s[0].TouchKey = key;
		}

		return onPad;
	}

	void DrawPad(Ui ui, Rect screen)
	{
		double scale = ui.Scale() > 0.0 ? ui.Scale() : 1.0;

		foreach (var button in Pad(screen))
		{
			bool held = button.Key == _s[0].TouchKey;
			var r = button.Rect;

			ui.FillRect(r, held ? Color.FromArgb(150, 255, 230, 140) : Color.FromArgb(90, 255, 255, 255));
			ui.FillRect(Rect.Create(r.X, r.Y, r.Width, 2), Color.FromArgb(160, 255, 255, 255));
			ui.FillRect(Rect.Create(r.X, r.Y + r.Height - 2, r.Width, 2), Color.FromArgb(160, 40, 40, 40));
			if (button.Label.Length == 1 && "^<>v".Contains(button.Label))
				DrawArrow(ui, r, button.Label);
			else
				ui.DrawText(r.X + r.Width / 2 - (int)((double)(button.Label.Length * 4) * scale), r.Y + r.Height / 2 - (int)(8.0 * scale),
					button.Label, Color.FromRgb(20, 20, 30));
		}
	}

	/// A filled triangle in the middle of a button, pointing the way of ^, <, > or v.
	void DrawArrow(Ui ui, Rect r, string way)
	{
		var color = Color.FromArgb(200, 30, 30, 40);
		int half = r.Width / 4;
		int centerX = r.X + r.Width / 2;
		int centerY = r.Y + r.Height / 2;

		for (var i = 0; i <= half; i += 1)
		{
			// i runs from the tip to the base; the line across grows with it
			if (way == "^")
				ui.FillRect(Rect.Create(centerX - i, centerY - half / 2 + i, 2 * i + 1, 1), color);
			else if (way == "v")
				ui.FillRect(Rect.Create(centerX - i, centerY + half / 2 - i, 2 * i + 1, 1), color);
			else if (way == "<")
				ui.FillRect(Rect.Create(centerX - half / 2 + i, centerY - i, 1, 2 * i + 1), color);
			else
				ui.FillRect(Rect.Create(centerX + half / 2 - i, centerY - i, 1, 2 * i + 1), color);
		}
	}

	/// Starts the game of the project on the map at the cell, at the time of day ("" the start of the game).
	Error<void> Start(StudioProject project, string map, int x, int y, string time)
	{
		Stop();
		Amber.Player.Platform.RepositoryRoot = project.Root;
		Amber.Player.Platform.VirtualScreenWidth = 320;
		Amber.Player.Platform.VirtualScreenHeight = 200;

		var options = Amber.Player.Platform.LaunchOptions { Scale = 1, Content = project.Content };
		var game = try PrototypeGame.Load(options);

		if (map.Length > 0)
			try game.Debug("map " + map + " " + x + " " + y);

		if (time.Length > 0)
			try game.Debug("time " + time);

		_game[0] = game;
		Input = Amber.Player.Platform.InputState.Create();
		Down.Clear();
		PressedAt.Clear();
		_s[0].HasGame = true;
		_s[0].Running = true;
		_s[0].Last = -1.0;
		_s[0].Accumulator = 0.0;
		_s[0].Ticks = 0;
		_s[0].MouseDown = false;
		_s[0].RightDown = false;
		_s[0].TouchKey = Amber.Player.Platform.Key.Unknown;
		_s[0].Status = map.Length > 0 ? "Spiel läuft auf " + map + " bei " + x + ", " + y : "Spiel läuft";

		return;
	}

	void Stop()
	{
		if (_s[0].Running)
			_s[0].Status = "Spiel beendet nach " + _s[0].Ticks + " Ticks";

		_s[0].Running = false;
	}

	/// Runs one tick (the input as it is): the tests step the game without a clock.
	Error<void> Tick()
	{
		if (!_s[0].Running)
			return;

		Input.BeginTick();
		try _game[0].Update(Input);
		_s[0].Ticks += 1;

		if (_game[0].QuitRequested())
			Stop();

		return;
	}

	/// The keys and the mouse of the frame go to the game (the mouse in pixels of the virtual screen).
	void Feed(UiInput input, Rect screen, bool takeKeys)
	{
		if (takeKeys)
		{
			if (input.Held.IsCreated() && input.Held.Count() > 0)
				_s[0].SawHeld = true;

			// the keys that are held now: those the window reports, or (without them) those that repeat - the first
			// repeat comes after about half a second, so a key just pressed counts as held a little longer
			foreach (var key in input.Keys)
				PressedAt.Set((int)key, input.Time);

			var wanted = Dictionary<int, bool>.Create();

			if (_s[0].SawHeld)
			{
				foreach (var key in input.Held)
					wanted.Set((int)key, true);
			}
			else
			{
				foreach (var code in PressedAt.Keys())
				{
					if (input.Time - PressedAt.GetOrDefault(code, 0.0) < 0.55)
						wanted.Set(code, true);
				}
			}

			// every press of the frame counts once, also one that is over already
			foreach (var key in input.Keys)
			{
				var engine = EngineKey(key);

				if (engine != Amber.Player.Platform.Key.Unknown)
				{
					Input.KeyUp(engine);
					Input.KeyDown(engine);
					Down.Set((int)key, true);
				}
			}

			var codes = List<int>.Create();

			foreach (var code in Down.Keys())
				codes.Add(code);

			foreach (var code in codes)
			{
				if (!wanted.GetOrDefault(code, false))
				{
					Input.KeyUp(EngineKey((System.Ui.Key)code));
					Down.Remove(code);
				}
			}

			foreach (var code in wanted.Keys())
			{
				var engine = EngineKey((System.Ui.Key)code);

				if (engine != Amber.Player.Platform.Key.Unknown && !Down.ContainsKey(code))
				{
					Input.KeyDown(engine);
					Down.Set(code, true);
				}
			}

			UpdateModifier(input.Shift, Amber.Player.Platform.Key.ShiftLeft);
			UpdateModifier(input.Ctrl, Amber.Player.Platform.Key.ControlLeft);

			if (input.Text.Length > 0)
				Input.CharTyped(input.Text);
		}

		if (screen.Width > 0 && screen.Height > 0)
		{
			int x = (input.MouseX - screen.X) * Amber.Player.Platform.VirtualScreenWidth / screen.Width;
			int y = (input.MouseY - screen.Y) * Amber.Player.Platform.VirtualScreenHeight / screen.Height;

			Input.MouseMoved(x, y);
		}

		bool onPad = _s[0].Touch && FeedTouch(input, screen);
		bool inside = screen.Contains(input.MouseX, input.MouseY) && !onPad;

		if (input.MousePressed && inside)
		{
			Input.MouseButtonDown(Amber.Player.Platform.MouseButton.Left);
			_s[0].MouseDown = true;
		}

		if (_s[0].MouseDown && (input.MouseReleased || !input.MouseDown))
		{
			Input.MouseButtonUp(Amber.Player.Platform.MouseButton.Left);
			_s[0].MouseDown = false;
		}

		if (input.RightPressed && inside)
		{
			Input.MouseButtonDown(Amber.Player.Platform.MouseButton.Right);
			_s[0].RightDown = true;
		}

		if (_s[0].RightDown && (input.RightReleased || !input.RightDown))
		{
			Input.MouseButtonUp(Amber.Player.Platform.MouseButton.Right);
			_s[0].RightDown = false;
		}

		if (input.Wheel != 0 && inside)
			Input.MouseWheel((float)input.Wheel);
	}

	void UpdateModifier(bool held, Amber.Player.Platform.Key key)
	{
		if (held)
			Input.KeyDown(key);
		else
			Input.KeyUp(key);
	}

	/// The game in the area: the ticks since the last frame (at most a quarter of a second), then the picture, as large
	/// as fits by a whole factor (or smaller, kept in its proportions). `height`: pixels at scale 1.
	Error<void> Draw(Ui ui, int height, bool takeKeys)
	{
		var r = ui.Area("game", 0, height);
		var theme = ui.GetTheme();

		ui.FillRect(r, Color.FromRgb(0, 0, 0));

		if (!_s[0].Running && _frame[0].Width == 0)
		{
			ui.DrawText(r.X + 16, r.Y + 16, "F5 startet das Spiel: auf der offenen Karte an der Stelle unter der Maus.", theme.TextMuted);

			return;
		}

		int w = Amber.Player.Platform.VirtualScreenWidth;
		int h = Amber.Player.Platform.VirtualScreenHeight;
		int scale = Math.Max(1, Math.Min(r.Width / w, r.Height / h));
		int shownW = w * scale;
		int shownH = h * scale;

		if (r.Width < w || r.Height < h)
		{
			// smaller than the virtual screen: in its proportions
			shownW = Math.Min(r.Width, r.Height * w / h);
			shownH = shownW * h / w;
		}

		var screen = Rect.Create(r.X + (r.Width - shownW) / 2, r.Y + (r.Height - shownH) / 2, shownW, shownH);

		_s[0].Screen = screen;

		if (_s[0].Running)
		{
			Feed(ui.Input(), screen, takeKeys);

			double now = ui.Input().Time;

			if (_s[0].Last < 0.0)
				_s[0].Last = now;

			double delta = now - _s[0].Last;

			_s[0].Last = now;
			_s[0].Accumulator += delta < 0.25 ? (delta > 0.0 ? delta : 0.0) : 0.25;

			var ran = RunTicks();

			if (ran is error e)
			{
				_s[0].Running = false;
				_s[0].Status = "Fehler im Spiel: " + e.Message;
			}

			if (_s[0].Running)
			{
				_frame[0] = RenderGame(_game[0]);
				ui.RequestFrame(20);
			}
		}

		if (_frame[0].Width > 0)
			ui.DrawImage(_frame[0], Rect.Create(0, 0, _frame[0].Width, _frame[0].Height), screen);

		if (_s[0].Touch && _s[0].Running)
			DrawPad(ui, screen);

		if (!_s[0].Running)
			ui.DrawText(r.X + 16, r.Y + 16, "Angehalten - F5 startet neu", Color.FromRgb(255, 220, 120));

		return;
	}

	Error<void> RunTicks()
	{
		double tick = 1.0 / 50.0;

		while (_s[0].Accumulator >= tick && _s[0].Running)
		{
			_s[0].Accumulator -= tick;
			try Tick();
		}

		return;
	}

	/// The picture of the game as it is now (tests: screenshots, without the clock).
	void Render()
	{
		if (_s[0].HasGame)
			_frame[0] = RenderGame(_game[0]);
	}
}
