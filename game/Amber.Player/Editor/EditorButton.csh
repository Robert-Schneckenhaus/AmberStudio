// A push button of the editor: a frame with a text, highlighted while the mouse is over it or while it is active (the
// selected layer or tool). CShift has no closures, so a button names its action (ButtonAction and an argument) and the
// editor carries it out.

namespace Amber.Player.Editor;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Game.Ui;
using Amber.Player.Graphics;

enum ButtonAction : int32
{
	/// Selects the layer Argument.
	Layer,
	Grid,
	Collision,
	/// Selects the tool Argument (an EditorTool).
	Tool,
	Undo,
	Redo,
	Save,
	/// Switches the palette by Argument tilesets.
	Tileset,
	/// Selects the terrain color Argument.
	TerrainColor,
	/// Selects the brush size Argument.
	Brush
}

/// Which buttons are shown together: the palette's buttons with the palette, the terrain buttons with the terrain brush.
enum ButtonGroup : int32
{
	Always,
	Tiles,
	Terrain
}

Color ButtonNormal = Color.Of(40, 34, 64);
Color ButtonHover = Color.Of(76, 58, 110);
Color ButtonActive = Color.Of(120, 84, 36);

struct EditorButton
{
	int X;
	int Y;
	int Width;
	int Height;
	string Text;
	ButtonAction Action;
	int Argument;
	ButtonGroup Group;
	/// Hidden buttons are not drawn and cannot be clicked.
	bool Visible;
	// the look of the last update
	bool Hover;
	bool Active;
	bool Enabled;

	/// A button; width 0 fits the text.
	static EditorButton Create(string text, int x, int y, ButtonAction action, int argument, ButtonGroup group, int width)
	{
		return EditorButton
		{
			X = x, Y = y, Width = width > 0 ? width : TextLength(text) * CellWidth + 8, Height = 14, Text = text, Action = action, Argument = argument, Group = group,
			Visible = true, Hover = false, Active = false, Enabled = true
		};
	}

	bool Contains(int mouseX, int mouseY)
	{
		return Visible && mouseX >= X && mouseY >= Y && mouseX < X + Width && mouseY < Y + Height;
	}

	void Draw(DrawList list)
	{
		if (!Visible)
			return;

		var fill = Active ? ButtonActive : Hover && Enabled ? ButtonHover : ButtonNormal;

		list.Add(RectItem(DrawPlane.Panels, 40, X, Y, Width, Height, UiBorder));
		list.Add(RectItem(DrawPlane.Panels, 41, X + 2, Y + 2, Width - 4, Height - 4, fill));
		list.Add(TextItem(44, Text, X + (Width - TextLength(Text) * CellWidth) / 2, Y + 3, Enabled ? TextColor.White : TextColor.Gray));
	}
}
