// The tile picker of the editor: the tiles of one tileset in a scrollable grid.

namespace Amber.Player.Editor;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Game;
using Amber.Player.Graphics;
using Amber.Player.Tiled;

struct PaletteValues
{
	int TilesetIndex;
	int ScrollRow;
	bool Visible;
	/// Global ID of the selected tile.
	int SelectedGid;
}

/// The palette; a handle (copies share the state).
struct EditorPalette
{
	PaletteValues[] _s;
	List<TiledTilesetReference> Tilesets;
	int X;
	int Y;
	int Width;
	int Height;

	static EditorPalette Create(List<TiledTilesetReference> tilesets, int x, int y, int width, int height)
	{
		var state = new PaletteValues[1];

		state[0].Visible = true;
		state[0].SelectedGid = tilesets.Count() > 0 ? tilesets.Get(0).FirstGid : 0;

		return EditorPalette { _s = state, Tilesets = tilesets, X = x, Y = y, Width = width, Height = height };
	}

	int SelectedGid()
	{
		return _s[0].SelectedGid;
	}

	bool HasTilesets()
	{
		return Tilesets.Count() > 0;
	}

	bool Visible()
	{
		return _s[0].Visible;
	}

	void SetVisible(bool visible)
	{
		_s[0].Visible = visible;
	}

	TiledTilesetReference Current()
	{
		return Tilesets.Get(_s[0].TilesetIndex);
	}

	string TilesetName()
	{
		return HasTilesets() ? Current().Tileset.Name + " (" + Current().Tileset.TileCount + ")" : "(no tilesets)";
	}

	int CellWidth()
	{
		return Current().Tileset.TileWidth + 2;
	}

	int CellHeight()
	{
		return Current().Tileset.TileHeight + 2;
	}

	int Columns()
	{
		return Max(1, Width / CellWidth());
	}

	int VisibleRows()
	{
		return Max(1, Height / CellHeight());
	}

	int TotalRows()
	{
		return (Current().Tileset.TileCount + Columns() - 1) / Columns();
	}

	void SelectTileset(int delta)
	{
		if (!HasTilesets())
			return;

		_s[0].TilesetIndex = (_s[0].TilesetIndex + delta + Tilesets.Count()) % Tilesets.Count();
		_s[0].ScrollRow = 0;
		_s[0].SelectedGid = Current().FirstGid;
	}

	/// Selects a tile by its global ID: switches to its tileset and scrolls to it.
	void Select(int gid)
	{
		for (var i = 0; i < Tilesets.Count(); i += 1)
		{
			if (!Tilesets.Get(i).Contains(gid))
				continue;

			_s[0].TilesetIndex = i;
			_s[0].SelectedGid = gid;

			int row = (gid - Tilesets.Get(i).FirstGid) / Columns();

			if (row < _s[0].ScrollRow || row >= _s[0].ScrollRow + VisibleRows())
				_s[0].ScrollRow = Max(0, row - VisibleRows() / 2);

			return;
		}
	}

	void Scroll(int rows)
	{
		if (HasTilesets())
			_s[0].ScrollRow = Clamp(_s[0].ScrollRow + rows, 0, Max(0, TotalRows() - VisibleRows()));
	}

	bool Contains(int mouseX, int mouseY)
	{
		return mouseX >= X && mouseY >= Y && mouseX < X + Width && mouseY < Y + Height;
	}

	/// Selects the tile under the mouse. Returns true if there was one.
	bool TryPick(int mouseX, int mouseY)
	{
		if (!HasTilesets() || !Contains(mouseX, mouseY))
			return false;

		int column = (mouseX - X) / CellWidth();
		int row = (mouseY - Y) / CellHeight() + _s[0].ScrollRow;
		int index = row * Columns() + column;

		if (column >= Columns() || index >= Current().Tileset.TileCount)
			return false;

		_s[0].SelectedGid = Current().FirstGid + index;

		return true;
	}

	/// Keeps the scroll position in range (once per tick, before drawing).
	void Update()
	{
		if (_s[0].Visible && HasTilesets())
			_s[0].ScrollRow = Clamp(_s[0].ScrollRow, 0, Max(0, TotalRows() - VisibleRows()));
	}

	/// The visible tiles (above the panels) and the frame of the selected tile (behind the tiles).
	void Draw(DrawList list, TileImages images)
	{
		if (!_s[0].Visible || !HasTilesets())
			return;

		var current = Current();
		var tileset = current.Tileset;
		int columns = Columns();
		int scrollRow = _s[0].ScrollRow;

		for (var row = 0; row < VisibleRows(); row += 1)
		{
			for (var column = 0; column < columns; column += 1)
			{
				int index = (scrollRow + row) * columns + column;

				if (index >= tileset.TileCount)
					break;

				var picture = images.Get((uint32)(current.FirstGid + index), 0);

				list.Add(PictureItem(DrawPlane.UiSprites, 0, picture, X + column * CellWidth() + 1, Y + row * CellHeight() + 1, 0, 0));
			}
		}

		int selected = _s[0].SelectedGid - current.FirstGid;
		int selectedRow = selected / columns - scrollRow;

		if (current.Contains(_s[0].SelectedGid) && selectedRow >= 0 && selectedRow < VisibleRows())
			list.Add(RectItem(DrawPlane.Panels, 30, X + selected % columns * CellWidth(), Y + selectedRow * CellHeight(), CellWidth(), CellHeight(), Color.Of(200, 150, 60)));
	}
}
