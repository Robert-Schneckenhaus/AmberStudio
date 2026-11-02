namespace Amber.Pack;

using System;
using Amber.Base;

/// A slot that moved: its old and its new place.
struct MovedSlot
{
	LayoutSlot Old;
	LayoutSlot New;
}

/// The difference between two state layouts (spec section 10.1): which names are new, which are gone and which moved to
/// another slot.
struct LayoutDiff
{
	List<LayoutSlot> Added;
	List<LayoutSlot> Removed;
	/// Names in both layouts whose index changed.
	List<MovedSlot> Moved;

	bool IsEmpty()
	{
		return Added.Count() == 0 && Removed.Count() == 0 && Moved.Count() == 0;
	}

	static LayoutDiff Compare(LayoutTable oldLayout, LayoutTable newLayout)
	{
		var oldSlots = Dictionary<string, LayoutSlot>.Create();
		var newSlots = Dictionary<string, LayoutSlot>.Create();

		foreach (var slot in oldLayout.Slots)
			oldSlots.Set(slot.Key(), slot);

		foreach (var slot in newLayout.Slots)
			newSlots.Set(slot.Key(), slot);

		var diff = LayoutDiff { Added = List<LayoutSlot>.Create(), Removed = List<LayoutSlot>.Create(), Moved = List<MovedSlot>.Create() };

		foreach (var slot in newLayout.Slots)
		{
			if (!oldSlots.ContainsKey(slot.Key()))
				diff.Added.Add(slot);
		}

		foreach (var slot in oldLayout.Slots)
		{
			if (newSlots.TryGet(slot.Key()) is LayoutSlot other)
			{
				if (other.Index != slot.Index)
					diff.Moved.Add(MovedSlot { Old = slot, New = other });
			}
			else
			{
				diff.Removed.Add(slot);
			}
		}

		return diff;
	}

	/// The text of the migration file the cook writes next to a release.
	string ToText()
	{
		var lines = List<string>.Create();

		foreach (var slot in Removed)
			lines.Add("- " + slot.Text());

		foreach (var slot in Added)
			lines.Add("+ " + slot.Text());

		foreach (var pair in Moved)
			lines.Add("> " + pair.Old.Text() + " => index " + pair.New.Index);

		return JoinList("\n", lines);
	}
}

/// The result of a migration: the new savegame and what happened to the names.
struct SaveMigrationResult
{
	SaveData Data;
	List<LayoutSlot> Dropped;
	List<LayoutSlot> Added;
	List<string> DroppedMaps;
}

/// Moves a savegame to a new layout by names (spec section 10.2): values of names in both layouts are kept, deleted names
/// are dropped, new names get the default value 0. Maps are matched by name, too; a map which no longer exists is dropped.
/// 'old' is the savegame of the old release, 'oldLayout' the layout it was written with (its hash has to match),
/// 'newLayout' the layout of the pack the game runs with now, 'newMaps' the maps of the new pack (name to ID).
Error<SaveMigrationResult> MigrateSave(SaveData old, LayoutTable oldLayout, LayoutTable newLayout, Dictionary<string, int> newMaps)
{
	if (oldLayout.Hash() != old.LayoutHash)
		return error("The given old layout is not the layout of the savegame (hash mismatch).", (int)ErrorKind.InvalidSave);

	var diff = LayoutDiff.Compare(oldLayout, newLayout);
	var global = MigrateState(old.Global, oldLayout, newLayout, "Global", "global");
	var maps = List<MapSave>.Create();
	var droppedMaps = List<string>.Create();

	foreach (var map in old.Maps)
	{
		if (newMaps.TryGet(map.Name) is int newId)
		{
			maps.Add(MapSave
			{
				MapId = newId,
				Name = map.Name,
				State = MigrateState(map.State, oldLayout, newLayout, "Map", map.Name),
				TileChanges = map.TileChanges,
				Entities = map.Entities
			});
		}
		else
		{
			droppedMaps.Add(map.Name);
		}
	}

	var data = SaveData.Create(newLayout.Hash(), old.RngState, old.Day, old.Minute, old.Tick, global);

	data.Version = old.Version;
	data.Maps = maps;
	data.Party = old.Party;

	var keptMaps = List<string>.Create();

	foreach (var map in maps)
		keptMaps.Add(map.Name);

	var dropped = List<LayoutSlot>.Create();
	var added = List<LayoutSlot>.Create();

	foreach (var slot in diff.Removed)
	{
		if (slot.ScopeKind != "Map" || ContainsText(keptMaps, slot.ScopeName))
			dropped.Add(slot);
	}

	foreach (var slot in diff.Added)
	{
		if (slot.ScopeKind != "Map" || ContainsText(keptMaps, slot.ScopeName))
			added.Add(slot);
	}

	return SaveMigrationResult { Data = data, Dropped = dropped, Added = added, DroppedMaps = droppedMaps };
}

StateSnapshot MigrateState(StateSnapshot old, LayoutTable oldLayout, LayoutTable newLayout, string scopeKind, string scopeName)
{
	var result = StateSnapshot.Empty(newLayout.Count(scopeKind, scopeName, "Flag"), newLayout.Count(scopeKind, scopeName, "Var"), newLayout.Count(scopeKind, scopeName, "Var32"));

	foreach (var slot in newLayout.Slots)
	{
		if (slot.ScopeKind != scopeKind || slot.ScopeName != scopeName)
			continue;

		if (oldLayout.Find(scopeKind, scopeName, slot.Kind, slot.Name) is LayoutSlot before)
		{
			if (slot.Kind == "Flag" && before.Index < old.FlagCount)
				result.SetFlag(slot.Index, old.GetFlag(before.Index));
			else if (slot.Kind == "Var" && before.Index < old.Vars.Length)
				result.Vars[slot.Index] = old.Vars[before.Index];
			else if (slot.Kind == "Var32" && before.Index < old.Vars32.Length)
				result.Vars32[slot.Index] = old.Vars32[before.Index];
		}
	}

	return result;
}
