// An open screen (spec section 8): the widgets of a ScreenDefinition with focus, keyboard and mouse input. It is a modal
// of the game: the topmost screen gets the input, the game world waits. The modal stack holds the open screens.

namespace Amber.Player.Screens;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Screens;
using Amber.Player.Game;
using Amber.Player.Graphics;
using Amber.Player.Platform;

struct ModalValues
{
	bool Finished;
	bool Active;
	int Result;
	int Focus;
	int TextView;
	int EnterCount;
	string Message;
	int64 MessageVersion;
	int DragGrid;
	bool HasDragRow;
	ListRow DragRow;
	int DragStartX;
	int DragStartY;
	bool DragMoved;
	int GhostX;
	int GhostY;
	string GhostText;
	/// The script thread which waits for the result (pop_screen), or -1.
	int WaitingThread;
	int OwnerMap;
}

/// An open screen. A handle: the modal stack, the screen host and the widgets' context share it.
struct ScreenModal
{
	ModalValues[] _s;
	ScreenDefinition Definition;
	/// The arguments of push_screen (screen variables 0..n-1).
	int[] Args;
	int LayerBase;
	Widget[] Widgets;
	/// The indices of the widgets which can have the focus (buttons, lists, inputs, item grids).
	int[] FocusableIndices;
	int Handle;

	static ScreenModal Create(ScreenDefinition definition, int[] args, int layerBase, int waitingThread, int ownerMap)
	{
		var widgets = List<Widget>.Create();

		BuildWidgets(widgets, definition.Nodes, definition.RegionX, definition.RegionY);

		var focusable = List<int>.Create();
		int textView = -1;

		for (var i = 0; i < widgets.Count(); i += 1)
		{
			var widget = widgets.Get(i);

			if (widget.IsFocusKind())
				focusable.Add(i);

			if (widget.Kind == WidgetKind.TextView && widget.Node.GetBool("paged", true) && textView < 0)
				textView = i;
		}

		var state = new ModalValues[1];

		state[0].Message = "";
		state[0].TextView = textView;
		state[0].DragGrid = -1;
		state[0].GhostText = "";
		state[0].WaitingThread = waitingThread;
		state[0].OwnerMap = ownerMap;

		var modal = ScreenModal { _s = state, Definition = definition, Args = args, LayerBase = layerBase, Widgets = ArrayOf(widgets), FocusableIndices = ArrayOf(focusable), Handle = NewHandleKey() };

		// the first input field gets the focus, else the first list, item grid or button
		modal._s[0].Focus = modal.FirstOf(WidgetKind.Input);

		if (modal._s[0].Focus < 0)
			modal._s[0].Focus = modal.FirstOf(WidgetKind.List);

		if (modal._s[0].Focus < 0)
			modal._s[0].Focus = modal.FirstOf(WidgetKind.ItemGrid);

		if (modal._s[0].Focus < 0 && focusable.Count() > 0)
			modal._s[0].Focus = focusable.Get(0);

		return modal;
	}

	bool Same(ScreenModal other)
	{
		return Handle == other.Handle;
	}

	int FirstOf(WidgetKind kind)
	{
		foreach (var index in FocusableIndices)
		{
			if (Widgets[index].Kind == kind)
				return index;
		}

		return -1;
	}

	bool Finished()
	{
		return _s[0].Finished;
	}

	bool Active()
	{
		return _s[0].Active;
	}

	int Result()
	{
		return _s[0].Result;
	}

	int WaitingThread()
	{
		return _s[0].WaitingThread;
	}

	int OwnerMap()
	{
		return _s[0].OwnerMap;
	}

	/// The modal below stays visible while this one is open.
	bool Transparent()
	{
		return Definition.Transparent;
	}

	/// A text the game shows in the screen (data source "input.message"), for example why an input was rejected.
	string Message()
	{
		return _s[0].Message;
	}

	void SetMessage(string value)
	{
		if (_s[0].Message == value)
			return;

		_s[0].Message = value;
		_s[0].MessageVersion += 1;
	}

	int64 MessageVersion()
	{
		return _s[0].MessageVersion;
	}

	/// The text in the first input field of the screen.
	string InputText()
	{
		foreach (var widget in Widgets)
		{
			if (widget.Kind == WidgetKind.Input)
				return widget.InputText();
		}

		return "";
	}

	/// The widget of the node with the index of ScreenDefinition.NodeIds (set_node, show_node ...). The widgets are in the
	/// same depth first order as the node list.
	Optional<Widget> FindNode(int index)
	{
		if (index >= 0 && index < Widgets.Length)
			return Widgets[index];

		return null;
	}

	void Close(int result)
	{
		_s[0].Result = result;
		_s[0].Finished = true;
	}

	/// The value of a screen argument by name (0 if unknown).
	int Arg(string name)
	{
		int index = IndexOfText(ListOf(Definition.Args), name);

		return index >= 0 && index < Args.Length ? Args[index] : 0;
	}

	/// Shows the widgets; the second and later entries run the on_resume handler (C#: Modal.Enter with OnEnter and Resumed).
	void Enter(ref GameSession session)
	{
		if (_s[0].Active)
			return;

		_s[0].Active = true;

		var context = ScreenContext.Of(ref session, ref this);

		foreach (var widget in Widgets)
		{
			widget.Invalidate();
			widget.Show(context, LayerBase + Min(widget.Node.Layer, 8));
		}

		_s[0].GhostText = "";
		Redraw(ref session, -1, -1);

		_s[0].EnterCount += 1;

		if (_s[0].EnterCount > 1)
			ScreenHost.Of(session).RunGroup(this, Definition.OnResume, 0);
	}

	void Leave()
	{
		if (!_s[0].Active)
			return;

		_s[0].Active = false;

		foreach (var widget in Widgets)
			widget.Hide();

		_s[0].GhostText = "";
		_s[0].DragGrid = -1;
		_s[0].HasDragRow = false;
	}

	void Update(ref GameSession session, InputState input)
	{
		Handle(ref session, input, input.MouseX(), input.MouseY());
		Redraw(ref session, input.MouseX(), input.MouseY());
	}

	/// Handles the input of one tick. Returns true if something was handled.
	bool Handle(ref GameSession session, InputState input, int mouseX, int mouseY)
	{
		var host = ScreenHost.Of(session);
		bool click = input.MousePressed(MouseButton.Left);
		int focus = _s[0].Focus;
		bool typing = focus >= 0 && Widgets[focus].Kind == WidgetKind.Input;
		bool accept = (input.Pressed(Key.Space) && !typing) || input.Pressed(Key.Enter);

		// a paged text takes the confirming keys and a click
		if (_s[0].TextView >= 0 && (accept || click))
		{
			var view = Widgets[_s[0].TextView];

			view.Advance();

			if (view.TextFinished())
				Close(0);

			return true;
		}

		if (HandleDrag(ref session, input, mouseX, mouseY))
			return true;

		// a text input takes the typed characters and Enter
		if (typing)
		{
			var field = Widgets[focus];

			if (input.Typed().Length > 0)
				field.Type(input.Typed());

			if (input.Pressed(Key.Backspace))
				field.Backspace();

			if (input.Pressed(Key.Enter))
			{
				host.RunGroup(this, field.SubmitHandler(), 0);

				return true;
			}
		}

		// hotkeys of buttons (letters are text while typing)
		foreach (var index in FocusableIndices)
		{
			var button = Widgets[index];

			if (button.Kind != WidgetKind.Button || !button.Visible() || !button.Enabled())
				continue;

			var key = button.Hotkey();

			if (key != Key.Unknown && input.Pressed(key) && (!typing || key == Key.Escape))
			{
				Activate(ref session, index);

				return true;
			}
		}

		// mouse
		if (click)
		{
			foreach (var index in FocusableIndices)
			{
				var widget = Widgets[index];

				if (!widget.Visible() || !widget.Enabled())
					continue;

				if (widget.Kind == WidgetKind.List && widget.TrySelectListAt(mouseX, mouseY))
				{
					_s[0].Focus = index;
					Activate(ref session, index);

					return true;
				}

				if (widget.Kind == WidgetKind.Button && widget.Contains(mouseX, mouseY))
				{
					_s[0].Focus = index;
					Activate(ref session, index);

					return true;
				}

				if (widget.Kind == WidgetKind.Input && widget.Contains(mouseX, mouseY))
				{
					_s[0].Focus = index;

					return true;
				}
			}
		}

		// focus and selection
		focus = _s[0].Focus;

		if (focus >= 0 && Widgets[focus].Kind == WidgetKind.List)
		{
			var list = Widgets[focus];

			if (input.Pressed(Key.Down) || input.Pressed(Key.S))
				list.MoveList(1);
			else if (input.Pressed(Key.Up) || input.Pressed(Key.W))
				list.MoveList(-1);
			else if (input.Pressed(Key.Right) || input.Pressed(Key.D))
				list.MoveList(list.RowsPerColumn());
			else if (input.Pressed(Key.Left) || input.Pressed(Key.A))
				list.MoveList(-list.RowsPerColumn());
		}
		else if (focus >= 0 && Widgets[focus].Kind == WidgetKind.ItemGrid)
		{
			var grid = Widgets[focus];

			if (input.Pressed(Key.Down) || input.Pressed(Key.S))
				grid.MoveGrid(0, 1);
			else if (input.Pressed(Key.Up) || input.Pressed(Key.W))
				grid.MoveGrid(0, -1);
			else if (input.Pressed(Key.Right) || input.Pressed(Key.D))
				MoveInGridOrFocus(focus, 1);
			else if (input.Pressed(Key.Left) || input.Pressed(Key.A))
				MoveInGridOrFocus(focus, -1);
		}
		else if (focus >= 0 && Widgets[focus].Kind == WidgetKind.Button)
		{
			if (input.Pressed(Key.Left) || input.Pressed(Key.Up) || input.Pressed(Key.A) || input.Pressed(Key.W))
				MoveFocus(-1);
			else if (input.Pressed(Key.Right) || input.Pressed(Key.Down) || input.Pressed(Key.D) || input.Pressed(Key.S))
				MoveFocus(1);
		}

		if (input.Pressed(Key.Tab))
			MoveFocus(input.IsDown(Key.ShiftLeft) || input.IsDown(Key.ShiftRight) ? -1 : 1);

		if (accept && _s[0].Focus >= 0 && !typing)
		{
			Activate(ref session, _s[0].Focus);

			return true;
		}

		// closing
		if ((input.Pressed(Key.Escape) && ContainsText(Definition.CloseOn, "escape"))
			|| (input.MousePressed(MouseButton.Right) && ContainsText(Definition.CloseOn, "right_click"))
			|| (input.Pressed(Key.Space) && !typing && ContainsText(Definition.CloseOn, "space")))
		{
			Close(0);

			return true;
		}

		return false;
	}

	/// Mouse press on an item starts a drag; releasing it on another grid runs the on_drop group of that grid, releasing it
	/// without having moved is a click (on_select).
	bool HandleDrag(ref GameSession session, InputState input, int mouseX, int mouseY)
	{
		if (input.MousePressed(MouseButton.Left) && _s[0].DragGrid < 0)
		{
			foreach (var index in FocusableIndices)
			{
				var grid = Widgets[index];

				if (grid.Kind != WidgetKind.ItemGrid || !grid.Visible() || !grid.Enabled())
					continue;

				if (grid.RowAt(mouseX, mouseY) is ListRow row)
				{
					grid.TrySelectGridAt(mouseX, mouseY);
					_s[0].Focus = index;
					_s[0].DragGrid = index;
					_s[0].HasDragRow = true;
					_s[0].DragRow = row;
					_s[0].DragStartX = mouseX;
					_s[0].DragStartY = mouseY;
					_s[0].DragMoved = false;

					break;
				}
			}
		}

		if (_s[0].DragGrid < 0 || !_s[0].HasDragRow)
			return false;

		if (Abs(mouseX - _s[0].DragStartX) + Abs(mouseY - _s[0].DragStartY) > 3)
			_s[0].DragMoved = true;

		if (!input.MouseReleased(MouseButton.Left))
			return true;

		var source = Widgets[_s[0].DragGrid];
		var item = _s[0].DragRow;
		int target = -1;

		foreach (var index in FocusableIndices)
		{
			var grid = Widgets[index];

			if (target < 0 && grid.Kind == WidgetKind.ItemGrid && grid.Visible() && grid.Enabled() && grid.Contains(mouseX, mouseY))
				target = index;
		}

		_s[0].DragGrid = -1;
		_s[0].HasDragRow = false;

		var host = ScreenHost.Of(session);

		if (!_s[0].DragMoved)
			host.RunGroup(this, source.SelectHandler(), item.Value);
		else if (target >= 0 && !Widgets[target].Same(source))
			host.RunGroup(this, Widgets[target].DropHandler(), item.Value);

		return true;
	}

	void MoveInGridOrFocus(int index, int direction)
	{
		var grid = Widgets[index];
		var before = grid.Selected();

		// left or right moves through the cells; at the edge the focus goes to the next widget (the other grid)
		if (grid.GridColumns() > 1)
			grid.MoveGrid(direction, 0);

		var after = grid.Selected();
		bool unchanged = (before is ListRow first && after is ListRow second && first.Same(second)) || (!(before is ListRow) && !(after is ListRow));

		if (grid.GridColumns() == 1 || unchanged)
			MoveFocus(direction);
	}

	void MoveFocus(int delta)
	{
		var candidates = List<int>.Create();

		foreach (var index in FocusableIndices)
		{
			if (Widgets[index].Visible() && Widgets[index].Enabled())
				candidates.Add(index);
		}

		if (candidates.Count() == 0)
			return;

		int current = _s[0].Focus < 0 ? -1 : candidates.IndexOf(_s[0].Focus);

		_s[0].Focus = candidates.Get((current + delta + candidates.Count()) % candidates.Count());
	}

	void Activate(ref GameSession session, int index)
	{
		var widget = Widgets[index];
		var host = ScreenHost.Of(session);

		if (widget.Kind == WidgetKind.Button)
			host.RunGroup(this, widget.Node.OnClick, 0);
		else if (widget.Kind == WidgetKind.List)
		{
			if (widget.Selected() is ListRow row)
				host.RunGroup(this, widget.SelectHandler(), row.Value);
		}
		else if (widget.Kind == WidgetKind.ItemGrid)
		{
			if (widget.Selected() is ListRow item)
				host.RunGroup(this, widget.SelectHandler(), item.Value);
		}
		else if (widget.Kind == WidgetKind.Input)
			host.RunGroup(this, widget.SubmitHandler(), 0);
	}

	void Redraw(ref GameSession session, int mouseX, int mouseY)
	{
		var context = ScreenContext.Of(ref session, ref this);

		for (var i = 0; i < Widgets.Length; i += 1)
		{
			var widget = Widgets[i];

			widget.Update(context, i == _s[0].Focus, widget.Focusable() && widget.Contains(mouseX, mouseY));
		}

		if (!_s[0].Active)
			return;

		if (_s[0].DragGrid >= 0 && _s[0].HasDragRow && _s[0].DragMoved)
		{
			_s[0].GhostText = _s[0].DragRow.Label;
			_s[0].GhostX = mouseX + 4;
			_s[0].GhostY = mouseY + 4;
		}
		else
			_s[0].GhostText = "";
	}

	/// What the screen shows now (the widgets and the dragged item).
	void Draw(DrawList list)
	{
		foreach (var widget in Widgets)
			list.AddAll(widget.Items());

		if (_s[0].GhostText.Length > 0)
			list.Add(TextItem(Min(255, LayerBase + 22), _s[0].GhostText, _s[0].GhostX, _s[0].GhostY, TextColor.Yellow));
	}

	/// The value of a data source; "nodeid.detail" and "nodeid.name" are the description and the text of the selected row
	/// of a list or item grid of this screen.
	string ResolveSource(ref GameSession session, string source)
	{
		int widget = SelectionWidget(source);

		if (widget >= 0)
		{
			if (Widgets[widget].Selected() is ListRow row)
				return source.EndsWith(".detail") ? row.Detail : row.Label;

			return "";
		}

		return ScreenHost.Of(session).ResolveSource(source, this);
	}

	int64 SourceVersion(ref GameSession session, string source)
	{
		int widget = SelectionWidget(source);

		if (widget >= 0)
			return Widgets[widget].SelectionVersion();

		return ScreenHost.Of(session).SourceVersion(source, this);
	}

	/// The selected row of the list or item grid with the node id, or no value.
	Optional<ListRow> SelectedOf(string nodeId)
	{
		for (var i = 0; i < Widgets.Length; i += 1)
		{
			if (Widgets[i].Node.Id == nodeId && (Widgets[i].Kind == WidgetKind.List || Widgets[i].Kind == WidgetKind.ItemGrid))
				return Widgets[i].Selected();
		}

		return null;
	}

	/// Changes whenever the selection of that list or grid changes (0 if there is none).
	int64 SelectionVersionOf(string nodeId)
	{
		for (var i = 0; i < Widgets.Length; i += 1)
		{
			if (Widgets[i].Node.Id == nodeId && (Widgets[i].Kind == WidgetKind.List || Widgets[i].Kind == WidgetKind.ItemGrid))
				return Widgets[i].SelectionVersion();
		}

		return 0;
	}

	/// The list or item grid a "nodeid.detail" or "nodeid.name" source refers to, or -1.
	int SelectionWidget(string source)
	{
		int dot = source.LastIndexOf('.');

		if (dot <= 0)
			return -1;

		string field = source.Substring(dot + 1);

		if (field != "detail" && field != "name")
			return -1;

		string id = source.Substring(0, dot);

		for (var i = 0; i < Widgets.Length; i += 1)
		{
			if (Widgets[i].Node.Id == id && (Widgets[i].Kind == WidgetKind.List || Widgets[i].Kind == WidgetKind.ItemGrid))
				return i;
		}

		return -1;
	}
}

void BuildWidgets(List<Widget> widgets, NodeDefinition[] nodes, int offsetX, int offsetY)
{
	foreach (var node in nodes)
	{
		int x = offsetX + node.X;
		int y = offsetY + node.Y;

		widgets.Add(Widget.Create(node, x, y));
		BuildWidgets(widgets, node.Children, x, y);
	}
}

/// The open modal windows. The top one receives the input; the ones below are hidden until it closes, unless the top one
/// is transparent. A handle.
struct ModalStack
{
	List<ScreenModal> _modals;

	static ModalStack Create()
	{
		return ModalStack { _modals = List<ScreenModal>.Create() };
	}

	bool Any()
	{
		return _modals.Count() > 0;
	}

	int Count()
	{
		return _modals.Count();
	}

	List<ScreenModal> Items()
	{
		return _modals;
	}

	void Push(ref GameSession session, ScreenModal modal)
	{
		if (!modal.Transparent() && _modals.Count() > 0)
			_modals.Get(_modals.Count() - 1).Leave();

		_modals.Add(modal);
		modal.Enter(ref session);
	}

	/// Closes the topmost screen with the value (pop_screen). Returns false if no screen is open.
	bool PopScreen(int result)
	{
		if (_modals.Count() == 0)
			return false;

		_modals.Get(_modals.Count() - 1).Close(result);

		return true;
	}

	void Update(ref GameSession session, InputState input)
	{
		if (_modals.Count() == 0)
			return;

		var receiver = InputReceiver(input);

		receiver.Update(ref session, input);

		if (!receiver.Finished())
			return;

		for (var i = 0; i < _modals.Count(); i += 1)
		{
			if (_modals.Get(i).Same(receiver))
			{
				_modals.RemoveAt(i);

				break;
			}
		}

		receiver.Leave();

		// the completion may push new modals (the next action of the script)
		ScreenHost.Of(session).Closed(receiver);

		if (_modals.Count() > 0)
			_modals.Get(_modals.Count() - 1).Enter(ref session);
	}

	/// The topmost modal, except for a click in a passthrough region of a transparent screen: that click belongs to the modal
	/// below (spec 8.1).
	ScreenModal InputReceiver(InputState input)
	{
		var top = _modals.Get(_modals.Count() - 1);
		bool click = input.MousePressed(MouseButton.Left) || input.MousePressed(MouseButton.Right);

		if (click && _modals.Count() > 1 && top.Transparent() && top.Definition.PassesThrough(input.MouseX(), input.MouseY()))
			return _modals.Get(_modals.Count() - 2);

		return top;
	}

	/// The screens that are shown (the entered ones).
	void Draw(DrawList list)
	{
		foreach (var modal in _modals)
		{
			if (modal.Active())
				modal.Draw(list);
		}
	}
}
