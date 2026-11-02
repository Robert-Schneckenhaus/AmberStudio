// The runtime objects of the nodes of a screen (C#: Widget and its subclasses). A widget is a handle with a kind; what it
// shows is a list of draw items which it rebuilds when it has to be drawn again (dirty marking: its own state changed,
// its focus or hover changed, or the data source it shows has a new version).

namespace Amber.Player.Screens;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Screens;
using Amber.Player.Game;
using Amber.Player.Game.Ui;
using Amber.Player.Graphics;
using Amber.Player.Platform;

/// A row of a list or item grid: the value the handler receives, the text (with an item: name, count, price), a longer
/// text (detail line), the icon (sheet cell, -1 none) and the count of an item stack.
struct ListRow
{
	int Value;
	string Label;
	string Detail;
	int Icon;
	int Count;

	static ListRow Of(int value, string label)
	{
		return ListRow { Value = value, Label = label, Detail = "", Icon = -1, Count = 1 };
	}

	bool Same(ListRow other)
	{
		return Value == other.Value && Label == other.Label && Detail == other.Detail && Icon == other.Icon && Count == other.Count;
	}
}

enum WidgetKind : int32
{
	Container,
	Unsupported,
	Window,
	Label,
	Button,
	TextView,
	List,
	Input,
	ItemGrid,
	Bar
}

/// The number of widget redraws so far (widgets which are not dirty are not redrawn); used by the test runs.
int WidgetRedraws = 0;

/// Shows texts at once (scripted test runs).
bool InstantText = false;

const int TextCharsPerTick = 2;
const int CaretBlinkTicks = 30;
const int ItemCellSize = 20;

Color ButtonNormal = Color.Of(40, 34, 64);
Color ButtonHover = Color.Of(76, 58, 110);
Color ButtonActive = Color.Of(120, 84, 36);
Color InputNormal = Color.Of(12, 10, 22);
Color InputFocus = Color.Of(40, 34, 64);
Color ListHighlight = Color.Of(70, 50, 100);
Color ListFocus = Color.Of(110, 76, 150);
Color GridColor = Color.Of(12, 10, 22);
Color BarTrack = Color.Of(12, 10, 22);
Color BarHigh = Color.Of(70, 190, 90);
Color BarMedium = Color.Of(230, 200, 70);
Color BarLow = Color.Of(220, 70, 60);

struct WidgetState
{
	bool Visible;
	bool Enabled;
	bool HasTextId;
	int TextId;
	bool Dirty;
	int64 SeenVersion;
	bool SeenFocused;
	bool SeenHovered;
	/// True between Show and Hide (the C# widget had its pooled UI elements).
	bool Shown;
	int Layer;
	/// What the widget shows now.
	List<DrawItem> Items;
	// button: the text of the last redraw (its width depends on it)
	string ButtonText;
	// text view
	List<string> Lines;
	string LastText;
	int Page;
	int ShownChars;
	bool Finished;
	// list and item grid
	ListRow[] Rows;
	int Selected;
	int64 SelectionVersion;
	bool HasSelectedLabel;
	string SelectedLabel;
	// input
	string Text;
	int Ticks;
	bool Caret;
}

/// What a widget asks of its screen: texts, data sources and the user interface kit. The session and the screen are held in
/// one element arrays and never returned: the compiler lays out a struct when a signature first mentions it, and the
/// session holds the screens (a struct cannot contain a struct by value whose layout is still being computed).
struct ScreenContext
{
	GameSession[] _session;
	ScreenModal[] _modal;

	static ScreenContext Of(ref GameSession session, ref ScreenModal modal)
	{
		var sessionHolder = new GameSession[1];
		var modalHolder = new ScreenModal[1];

		sessionHolder[0] = session;
		modalHolder[0] = modal;

		return ScreenContext { _session = sessionHolder, _modal = modalHolder };
	}

	UiKit Ui()
	{
		return _session[0].Ui;
	}

	string ResolveText(string raw)
	{
		return ScreenHost.Of(_session[0]).ResolveText(raw, _modal[0]);
	}

	string ResolveTextId(int id)
	{
		return ScreenHost.Of(_session[0]).ResolveTextId(id);
	}

	string ResolveSource(string source)
	{
		return _modal[0].ResolveSource(ref _session[0], source);
	}

	int64 SourceVersion(string source)
	{
		return _modal[0].SourceVersion(ref _session[0], source);
	}

	ListRow[] Rows(string source)
	{
		return ScreenHost.Of(_session[0]).Rows(source, _modal[0]);
	}

	IntPair Bar(string kind, int slot)
	{
		return ScreenHost.Of(_session[0]).Bar(kind, slot);
	}
}

/// The runtime object of a node.
struct Widget
{
	WidgetState[] _s;
	NodeDefinition Node;
	WidgetKind Kind;
	int X;
	int Y;
	int Handle;

	static Widget Create(NodeDefinition node, int x, int y)
	{
		var state = new WidgetState[1];

		state[0].Visible = node.Visible;
		state[0].Enabled = node.Enabled;
		state[0].Dirty = true;
		state[0].SeenVersion = -1;
		state[0].Items = List<DrawItem>.Create();
		state[0].ButtonText = "";
		state[0].Lines = List<string>.Create();
		state[0].LastText = "";
		state[0].Rows = new ListRow[0];
		state[0].Text = "";

		return Widget { _s = state, Node = node, Kind = KindOf(node.Kind), X = x, Y = y, Handle = NewHandleKey() };
	}

	bool Same(Widget other)
	{
		return Handle == other.Handle;
	}

	List<DrawItem> Items()
	{
		return _s[0].Items;
	}

	bool Visible()
	{
		return _s[0].Visible;
	}

	void SetVisible(bool value)
	{
		if (_s[0].Visible != value)
			_s[0].Dirty = true;

		_s[0].Visible = value;
	}

	bool Enabled()
	{
		return _s[0].Enabled;
	}

	void SetEnabled(bool value)
	{
		if (_s[0].Enabled != value)
			_s[0].Dirty = true;

		_s[0].Enabled = value;
	}

	/// Text ID set by set_text; replaces the text of the definition.
	void SetTextId(int id)
	{
		if (!_s[0].HasTextId || _s[0].TextId != id)
			_s[0].Dirty = true;

		_s[0].HasTextId = true;
		_s[0].TextId = id;
	}

	/// Marks the widget as changed: it is drawn again in the next tick.
	void Invalidate()
	{
		_s[0].Dirty = true;
	}

	bool IsFocusKind()
	{
		return Kind == WidgetKind.Button || Kind == WidgetKind.List || Kind == WidgetKind.Input || Kind == WidgetKind.ItemGrid;
	}

	bool Focusable()
	{
		return IsFocusKind() && _s[0].Visible && _s[0].Enabled;
	}

	int Width()
	{
		if (Kind == WidgetKind.Button)
			return Node.Width > 0 ? Node.Width : TextLength(_s[0].ButtonText) * CellWidth + 8;

		if (Kind == WidgetKind.Input)
			return Node.Width > 0 ? Node.Width : 160;

		if (Kind == WidgetKind.ItemGrid)
			return Node.Width > 0 ? Node.Width : GridColumns() * ItemCellSize + 4;

		return Node.Width;
	}

	int Height()
	{
		if (Kind == WidgetKind.Button)
			return Node.Height > 0 ? Node.Height : 14;

		if (Kind == WidgetKind.Input)
			return Node.Height > 0 ? Node.Height : 12;

		if (Kind == WidgetKind.ItemGrid)
			return Node.Height > 0 ? Node.Height : GridRows() * ItemCellSize + 4;

		return Node.Height;
	}

	bool Contains(int mouseX, int mouseY)
	{
		return _s[0].Visible && mouseX >= X && mouseY >= Y && mouseX < X + Width() && mouseY < Y + Height();
	}

	/// True if the widget has to be drawn again (and counts the redraw).
	bool NeedsRedraw(ScreenContext context, string source, bool focused, bool hovered)
	{
		int64 version = source == null ? 0 : context.SourceVersion(source);

		if (!_s[0].Dirty && version == _s[0].SeenVersion && focused == _s[0].SeenFocused && hovered == _s[0].SeenHovered)
			return false;

		_s[0].Dirty = false;
		_s[0].SeenVersion = version;
		_s[0].SeenFocused = focused;
		_s[0].SeenHovered = hovered;
		WidgetRedraws += 1;

		return true;
	}

	string TextOf(ScreenContext context, string raw)
	{
		return _s[0].HasTextId ? context.ResolveTextId(_s[0].TextId) : context.ResolveText(raw);
	}

	void Show(ScreenContext context, int layer)
	{
		_s[0].Shown = true;
		_s[0].Layer = layer;
		_s[0].Items.Clear();

		if (Kind == WidgetKind.Unsupported)
			Console.WriteErrorLine("screen node '" + Node.Kind + "' is not supported by the prototype");
		else if (Kind == WidgetKind.Window)
			RedrawWindow(context);
		else if (Kind == WidgetKind.TextView)
			_s[0].LastText = "";
		else if (Kind == WidgetKind.List || Kind == WidgetKind.ItemGrid)
		{
			_s[0].Rows = context.Rows(TextOr(Node.GetString("source"), ""));
			_s[0].Selected = Clamp(_s[0].Selected, 0, Max(0, _s[0].Rows.Length - 1));
		}
	}

	void Hide()
	{
		_s[0].Shown = false;
		_s[0].Items.Clear();
	}

	/// Redraws the widget (once per tick).
	void Update(ScreenContext context, bool focused, bool hovered)
	{
		if (!_s[0].Shown)
			return;

		if (Kind == WidgetKind.Window)
		{
			if (NeedsRedraw(context, null, false, false))
				RedrawWindow(context);
		}
		else if (Kind == WidgetKind.Label)
			UpdateLabel(context);
		else if (Kind == WidgetKind.Button)
			UpdateButton(context, focused, hovered);
		else if (Kind == WidgetKind.TextView)
			UpdateTextView(context);
		else if (Kind == WidgetKind.List)
			UpdateList(context, focused, hovered);
		else if (Kind == WidgetKind.Input)
			UpdateInput(context, focused, hovered);
		else if (Kind == WidgetKind.ItemGrid)
			UpdateGrid(context, focused, hovered);
		else if (Kind == WidgetKind.Bar)
			UpdateBar(context);
	}

	// ---- window ---------------------------------------------------------------------------------

	void RedrawWindow(ScreenContext context)
	{
		var items = _s[0].Items;

		items.Clear();

		if (!_s[0].Visible)
			return;

		// X/Y/Width/Height are the client area other nodes place themselves in; the border (if the look has one) is drawn
		// around it, not inside it, so it never covers content that sits flush with the window's own edges.
		string look = Node.GetString("look");
		var inset = context.Ui().BorderThickness("window", look);
		bool dark = Node.GetBool("dark", false);

		context.Ui().LookBox(items, _s[0].Layer, "window", look, dark ? "dark" : "normal", X - inset.Left, Y - inset.Top, Width() + inset.Left + inset.Right,
			Height() + inset.Top + inset.Bottom, UiBorder, dark ? Color.Of(12, 10, 22) : UiBackground);
	}

	// ---- label ----------------------------------------------------------------------------------

	void UpdateLabel(ScreenContext context)
	{
		string bind = Node.GetString("bind");

		if (!NeedsRedraw(context, bind, false, false))
			return;

		var items = _s[0].Items;

		items.Clear();

		if (!_s[0].Visible)
			return;

		string text = bind != null ? context.ResolveSource(bind) : TextOf(context, Node.GetString("text"));
		var lines = Width() > 0 ? Wrap(text, Width()) : SplitToList(text, "\n");
		int offset = 0;
		string align = Node.GetString("align");

		if (Width() > 0 && (align == "center" || align == "right"))
		{
			int widest = 0;

			foreach (var line in lines)
				widest = Max(widest, TextLength(line));

			int textWidth = widest * CellWidth;

			offset = align == "center" ? (Width() - textWidth) / 2 : Width() - textWidth;
		}

		items.Add(TextItem(_s[0].Layer + 2, JoinList("\n", lines), X + offset, Y, ColorOf(Node)));
	}

	// ---- button ---------------------------------------------------------------------------------

	/// The key which activates the button, or Key.Unknown.
	Amber.Player.Platform.Key Hotkey()
	{
		string name = Node.GetString("hotkey");

		if (name == null)
			return Amber.Player.Platform.Key.Unknown;

		string lower = name.ToLower();

		if (lower == "esc" || lower == "escape")
			return Amber.Player.Platform.Key.Escape;

		if (lower == "enter" || lower == "return")
			return Amber.Player.Platform.Key.Enter;

		return ParseKey(name);
	}

	void UpdateButton(ScreenContext context, bool focused, bool hovered)
	{
		if (!NeedsRedraw(context, null, focused, hovered))
			return;

		string raw = Node.GetString("text");

		_s[0].ButtonText = TextOf(context, raw != null ? raw : Node.GetString("icon"));

		var items = _s[0].Items;

		items.Clear();

		if (!_s[0].Visible)
			return;

		bool enabled = _s[0].Enabled;
		string state = focused ? "focused" : hovered && enabled ? "hover" : enabled ? "normal" : "disabled";
		string text = _s[0].ButtonText;

		context.Ui().LookBox(items, _s[0].Layer + 4, "button", Node.GetString("look"), state, X, Y, Width(), Height(), UiBorder,
			focused ? ButtonActive : hovered && enabled ? ButtonHover : ButtonNormal);
		items.Add(TextItem(_s[0].Layer + 6, text, X + (Width() - TextLength(text) * CellWidth) / 2, Y + (Height() - CellHeight) / 2, enabled ? TextColor.White : TextColor.Gray));
	}

	// ---- text view ------------------------------------------------------------------------------

	bool Paged()
	{
		return Node.GetBool("paged", true);
	}

	bool TextFinished()
	{
		return _s[0].Finished;
	}

	int LinesPerPage()
	{
		return Height() > 0 ? Max(1, Height() / LineHeight) : 4;
	}

	List<string> PageLines()
	{
		var result = List<string>.Create();
		int start = _s[0].Page * LinesPerPage();

		for (var i = start; i < start + LinesPerPage() && i < _s[0].Lines.Count(); i += 1)
			result.Add(_s[0].Lines.Get(i));

		return result;
	}

	bool HasMorePages()
	{
		return Paged() && (_s[0].Page + 1) * LinesPerPage() < _s[0].Lines.Count();
	}

	int PageLength()
	{
		int length = 0;

		foreach (var line in PageLines())
			length += TextLength(line) + 1;

		return length;
	}

	/// Completes the page, or turns to the next one, or finishes. Called for Space, Enter and a click.
	void Advance()
	{
		if (_s[0].ShownChars < PageLength())
			_s[0].ShownChars = PageLength();
		else if (HasMorePages())
		{
			_s[0].Page += 1;
			_s[0].ShownChars = InstantText ? PageLength() : 0;
		}
		else
			_s[0].Finished = true;
	}

	void UpdateTextView(ScreenContext context)
	{
		string source = Node.GetString("source");
		string text = source != null ? context.ResolveSource(source) : TextOf(context, Node.GetString("text"));

		if (text != _s[0].LastText)
		{
			_s[0].LastText = text;
			_s[0].Lines = Wrap(text, Width() > 0 ? Width() : 288);
			_s[0].Page = 0;
			_s[0].ShownChars = InstantText ? PageLength() : 0;
		}
		else if (_s[0].ShownChars < PageLength())
			_s[0].ShownChars += TextCharsPerTick;

		int remaining = _s[0].ShownChars;
		var visible = List<string>.Create();

		foreach (var line in PageLines())
		{
			if (remaining <= 0)
				break;

			visible.Add(TextLength(line) <= remaining ? line : TextPrefix(line, remaining));
			remaining -= TextLength(line) + 1;
		}

		var items = _s[0].Items;

		items.Clear();
		items.Add(TextItem(_s[0].Layer + 2, JoinList("\n", visible), X, Y, TextColor.White));

		if (Paged() && _s[0].ShownChars >= PageLength())
		{
			string mark = HasMorePages() ? "Space >>" : "Space";

			items.Add(TextItem(_s[0].Layer + 2, mark, X + Max(Width(), 96) - TextLength(mark) * CellWidth, Y + Max(Height(), 40) - 1, TextColor.Gray));
		}
	}

	// ---- list -----------------------------------------------------------------------------------

	int RowsPerColumn()
	{
		return Max(1, Node.GetInt("rows", 3));
	}

	int ListColumns()
	{
		return Max(1, Node.GetInt("columns", 1));
	}

	int ListSlots()
	{
		return RowsPerColumn() * ListColumns();
	}

	int ListCellWidth()
	{
		return Width() / ListColumns();
	}

	int PageStart()
	{
		return _s[0].Selected / ListSlots() * ListSlots();
	}

	/// The selected row of a list or item grid.
	Optional<ListRow> Selected()
	{
		if (_s[0].Selected >= 0 && _s[0].Selected < _s[0].Rows.Length)
			return _s[0].Rows[_s[0].Selected];

		return null;
	}

	/// Changes whenever the selected row changes ("nodeid.detail" labels depend on it).
	int64 SelectionVersion()
	{
		return _s[0].SelectionVersion;
	}

	string SelectHandler()
	{
		return Node.GetString("on_select");
	}

	string DropHandler()
	{
		return Node.GetString("on_drop");
	}

	string SubmitHandler()
	{
		return Node.GetString("on_submit");
	}

	void Select(int index)
	{
		if (index == _s[0].Selected)
			return;

		_s[0].Selected = index;
		_s[0].SelectionVersion += 1;
		_s[0].Dirty = true;
	}

	/// Moves the selection by whole rows (up/down = 1) or columns (left/right = rows per column).
	void MoveList(int delta)
	{
		int count = _s[0].Rows.Length;

		if (count == 0)
			return;

		Select(Clamp(delta == 1 || delta == -1 ? (_s[0].Selected + delta + count) % count : _s[0].Selected + delta, 0, count - 1));
	}

	/// Selects the row under the mouse. Returns true if there was one.
	bool TrySelectListAt(int mouseX, int mouseY)
	{
		if (!Contains(mouseX, mouseY))
			return false;

		int column = (mouseX - X) / Max(1, ListCellWidth());
		int row = (mouseY - Y) / LineHeight;
		int index = PageStart() + column * RowsPerColumn() + row;

		if (row >= RowsPerColumn() || column >= ListColumns() || index >= _s[0].Rows.Length)
			return false;

		Select(index);

		return true;
	}

	void UpdateList(ScreenContext context, bool focused, bool hovered)
	{
		string source = Node.GetString("source");

		if (!NeedsRedraw(context, source, focused, hovered))
			return;

		_s[0].Rows = context.Rows(TextOr(source, ""));
		_s[0].Selected = Clamp(_s[0].Selected, 0, Max(0, _s[0].Rows.Length - 1));
		_s[0].SelectionVersion += 1;

		var items = _s[0].Items;
		var rows = _s[0].Rows;

		items.Clear();

		if (!_s[0].Visible)
			return;

		int visibleCount = Max(0, Min(ListSlots(), rows.Length - PageStart()));

		for (var i = 0; i < visibleCount; i += 1)
		{
			int index = PageStart() + i;
			int column = i / RowsPerColumn();
			int row = i % RowsPerColumn();
			string text = rows[index].Label;
			int maxChars = Max(1, ListCellWidth() / CellWidth - 1);

			items.Add(TextItem(_s[0].Layer + 4, TextLength(text) > maxChars ? TextPrefix(text, maxChars) : text, X + column * ListCellWidth() + 4, Y + row * LineHeight,
				index == _s[0].Selected ? TextColor.Yellow : TextColor.White));
		}

		if (rows.Length > 0)
		{
			int local = _s[0].Selected - PageStart();

			items.Add(RectItem(DrawPlane.Panels, _s[0].Layer + 3, X + local / RowsPerColumn() * ListCellWidth(), Y + local % RowsPerColumn() * LineHeight - 1,
				Max(1, ListCellWidth() - 2), LineHeight, focused ? ListFocus : ListHighlight));
		}
	}

	// ---- input ----------------------------------------------------------------------------------

	string InputText()
	{
		return _s[0].Text;
	}

	int MaxLength()
	{
		return Node.GetInt("max_length", 24);
	}

	/// Appends the printable characters until max_length is reached.
	void Type(string characters)
	{
		for (var i = 0; i < characters.Length; i += 1)
		{
			char character = characters[i];

			if (character >= ' ' && character <= '~' && TextLength(_s[0].Text) < MaxLength())
			{
				_s[0].Text = _s[0].Text + characters.Substring(i, 1);
				_s[0].Dirty = true;
			}
		}
	}

	void Backspace()
	{
		if (_s[0].Text.Length == 0)
			return;

		_s[0].Text = TextPrefix(_s[0].Text, TextLength(_s[0].Text) - 1);
		_s[0].Dirty = true;
	}

	void UpdateInput(ScreenContext context, bool focused, bool hovered)
	{
		bool phase = focused && _s[0].Ticks / CaretBlinkTicks % 2 == 0;

		if (focused)
			_s[0].Ticks += 1;
		else
			_s[0].Ticks = 0;

		if (phase != _s[0].Caret)
		{
			_s[0].Caret = phase;
			_s[0].Dirty = true;
		}

		if (!NeedsRedraw(context, null, focused, hovered))
			return;

		var items = _s[0].Items;

		items.Clear();

		if (!_s[0].Visible)
			return;

		context.Ui().Frame(items, _s[0].Layer + 2, X, Y, Width(), Height(), UiBorder, focused ? InputFocus : InputNormal);

		int maxChars = Max(1, (Width() - 8) / CellWidth);
		string text = _s[0].Text;
		string shown = TextLength(text) >= maxChars ? TextSuffix(text, TextLength(text) - maxChars + 1) : text;

		items.Add(TextItem(_s[0].Layer + 4, shown + (_s[0].Caret ? "_" : ""), X + 4, Y + (Height() - CellHeight) / 2, TextColor.White));
	}

	// ---- item grid ------------------------------------------------------------------------------

	int GridColumns()
	{
		return Max(1, Node.GetInt("cols", 1));
	}

	int GridRows()
	{
		return Max(1, Node.GetInt("rows", 1));
	}

	int GridSlots()
	{
		return GridColumns() * GridRows();
	}

	/// The item in the cell under the mouse, or no value (empty cell, outside).
	Optional<ListRow> RowAt(int mouseX, int mouseY)
	{
		if (!Contains(mouseX, mouseY))
			return null;

		int localX = mouseX - X - 2;
		int localY = mouseY - Y - 2;

		if (localX < 0 || localY < 0)
			return null;

		int column = localX / ItemCellSize;
		int row = localY / ItemCellSize;
		int index = row * GridColumns() + column;

		if (column < GridColumns() && row < GridRows() && index < Min(_s[0].Rows.Length, GridSlots()))
			return _s[0].Rows[index];

		return null;
	}

	/// Selects the item under the mouse. Returns true if there was one.
	bool TrySelectGridAt(int mouseX, int mouseY)
	{
		if (RowAt(mouseX, mouseY) is ListRow row)
		{
			for (var i = 0; i < _s[0].Rows.Length; i += 1)
			{
				if (_s[0].Rows[i].Same(row))
				{
					Select(i);

					break;
				}
			}

			return true;
		}

		return false;
	}

	/// Moves the selection by cells (up/down = one row, left/right = one cell); stays in the grid.
	void MoveGrid(int columns, int rowsDown)
	{
		int count = Min(_s[0].Rows.Length, GridSlots());

		if (count == 0)
			return;

		int column = _s[0].Selected % GridColumns();
		int row = _s[0].Selected / GridColumns();
		int target = Clamp(row + rowsDown, 0, (count - 1) / GridColumns()) * GridColumns() + Clamp(column + columns, 0, GridColumns() - 1);

		Select(Min(target, count - 1));
	}

	void UpdateGrid(ScreenContext context, bool focused, bool hovered)
	{
		string source = Node.GetString("source");

		if (!NeedsRedraw(context, source, focused, hovered))
			return;

		_s[0].Rows = context.Rows(TextOr(source, ""));
		_s[0].Selected = Clamp(_s[0].Selected, 0, Max(0, _s[0].Rows.Length - 1));

		var selected = Selected();
		bool hasLabel = selected is ListRow;
		string label = selected is ListRow row ? row.Label : null;

		if (hasLabel != _s[0].HasSelectedLabel || label != _s[0].SelectedLabel)
		{
			_s[0].HasSelectedLabel = hasLabel;
			_s[0].SelectedLabel = label;
			_s[0].SelectionVersion += 1;
		}

		var items = _s[0].Items;
		var rows = _s[0].Rows;
		var icons = context.Ui().Icons;

		items.Clear();

		if (!_s[0].Visible)
			return;

		context.Ui().LookBox(items, _s[0].Layer + 2, "itemgrid", Node.GetString("look"), "normal", X, Y, Width(), Height(), UiBorder, GridColor);

		int visibleCount = Min(rows.Length, GridSlots());

		for (var i = 0; i < visibleCount; i += 1)
		{
			var cell = rows[i];
			int cellX = X + 2 + i % GridColumns() * ItemCellSize;
			int cellY = Y + 2 + i / GridColumns() * ItemCellSize;

			if (cell.Icon >= 0 && icons.Icons.TryGet(cell.Icon) is Image icon)
				items.Add(PictureItem(DrawPlane.Icons, _s[0].Layer + 5, icon, cellX + 2, cellY + 2, 0, 0));
			else
			{
				string name = cell.Label.Split(" ")[0].ToString();

				items.Add(TextItem(_s[0].Layer + 5, TextLength(name) > 3 ? TextPrefix(name, 3) : name, cellX + 1, cellY + 5, i == _s[0].Selected ? TextColor.Yellow : TextColor.White));
			}

			if (cell.Count > 1)
			{
				string count = "" + cell.Count;

				items.Add(TextItem(_s[0].Layer + 6, count, cellX + ItemCellSize - TextLength(count) * CellWidth - 1, cellY + ItemCellSize - CellHeight - 1, TextColor.Yellow));
			}
		}

		if (visibleCount > 0)
			items.Add(RectItem(DrawPlane.Panels, _s[0].Layer + 4, X + 2 + _s[0].Selected % GridColumns() * ItemCellSize, Y + 2 + _s[0].Selected / GridColumns() * ItemCellSize,
				ItemCellSize, ItemCellSize, focused ? ListFocus : ListHighlight));
	}

	// ---- bar ------------------------------------------------------------------------------------

	void UpdateBar(ScreenContext context)
	{
		string kind = TextOr(Node.GetString("kind"), "hp");

		if (!NeedsRedraw(context, "party." + kind, false, false))
			return;

		var bar = context.Bar(kind, Node.GetInt("slot", 1));
		int value = bar.First;
		int max = bar.Second;
		int inner = Max(0, Width() - 4);
		int filled = max > 0 ? inner * Clamp(value, 0, max) / max : 0;
		var items = _s[0].Items;

		items.Clear();

		if (!_s[0].Visible)
			return;

		context.Ui().LookBox(items, _s[0].Layer, "bar", Node.GetString("look"), "normal", X, Y, Width(), Height(), UiBorder, BarTrack);

		if (filled > 0)
			items.Add(RectItem(DrawPlane.Panels, _s[0].Layer + 2, X + 2, Y + 2, filled, Max(1, Height() - 4),
				max <= 0 || value * 2 > max ? BarHigh : value * 4 > max ? BarMedium : BarLow));
	}
}

WidgetKind KindOf(string kind)
{
	if (kind == "window")
		return WidgetKind.Window;

	if (kind == "label")
		return WidgetKind.Label;

	if (kind == "button")
		return WidgetKind.Button;

	if (kind == "textview")
		return WidgetKind.TextView;

	if (kind == "list")
		return WidgetKind.List;

	if (kind == "input")
		return WidgetKind.Input;

	if (kind == "itemgrid")
		return WidgetKind.ItemGrid;

	if (kind == "bar")
		return WidgetKind.Bar;

	if (kind == "container")
		return WidgetKind.Container;

	return WidgetKind.Unsupported;
}

TextColor ColorOf(NodeDefinition node)
{
	int color = node.GetInt("color", 0);

	if (color == 1)
		return TextColor.Yellow;

	if (color == 2)
		return TextColor.Gray;

	if (color == 3)
		return TextColor.Cyan;

	if (color == 4)
		return TextColor.Green;

	if (color == 5)
		return TextColor.Red;

	if (color == 6)
		return TextColor.Orange;

	if (color == 7)
		return TextColor.Black;

	return TextColor.White;
}

string TextOr(string text, string fallback)
{
	return text != null ? text : fallback;
}
