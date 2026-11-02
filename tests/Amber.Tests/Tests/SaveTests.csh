namespace Amber.Tests;

using System;
using Amber.Base;
using Amber.Pack;
using Amber.Runtime;
using Amber.Script;
using Amber.Script.Common;
using Amber.Script.Compilation;

// The savegame (spec section 10.2) and its migration to a new layout by names (task 3.6).

void RegisterSaveTests(ref TestList tests)
{
	tests.Fact("Save.ASavegameRoundTrips", ASavegameRoundTrips);
	tests.Fact("Save.DamagedSavegamesAreRejected", DamagedSavegamesAreRejected);
	tests.Fact("Save.MigrationKeepsValuesByNameAndInitializesNewNames", MigrationKeepsValuesByNameAndInitializesNewNames);
	tests.Fact("Save.MigrationToTheSameLayoutChangesNothing", MigrationToTheSameLayoutChangesNothing);
	tests.Fact("Save.MigrationNeedsTheLayoutOfTheSavegame", MigrationNeedsTheLayoutOfTheSavegame);
	tests.Fact("Save.TheLayoutDiffListsAddedRemovedAndMovedNames", TheLayoutDiffListsAddedRemovedAndMovedNames);
	tests.Fact("Save.SnapshotsRestoreIntoStoresWithoutEvents", SnapshotsRestoreIntoStoresWithoutEvents);
	tests.Fact("Save.SavingIsOnlyPossibleWhenNoScriptIsWaiting", SavingIsOnlyPossibleWhenNoScriptIsWaiting);
}

const string OldSaveSource = "flag alpha; flag beta; var counter; var32 total;\n"
	+ "map keller { flag schrein; flag hebel; var besuche; var32 punkte; }\n"
	+ "map turm { flag offen; }";

// beta and alpha swapped, counter and hebel gone, gamma and riegel new, the map turm gone and the map wald new
const string NewSaveSource = "flag beta; flag gamma; flag alpha; var32 total; var32 extra;\n"
	+ "map keller { flag riegel; flag schrein; var besuche; }\n"
	+ "map wald { flag frisch; }";

Error<LayoutTable> LayoutOf(string source)
{
	var result = ScriptCompiler.CompileText(source, "test.ams", CompileOptions { LenientSymbols = true });

	try NoErrors(result);

	return LayoutTable.Parse(result.LayoutText);
}

SaveData OldSave(LayoutTable layout)
{
	var global = StateSnapshot.Empty(2, 1, 1);
	var keller = StateSnapshot.Empty(2, 1, 1);
	var turm = StateSnapshot.Empty(1, 0, 0);

	global.SetFlag(0, true);
	global.Vars[0] = 7;
	global.Vars32[0] = 123456;
	keller.SetFlag(0, true);	// schrein (hebel, index 1, stays clear)
	keller.Vars[0] = -3;
	keller.Vars32[0] = 99;
	turm.SetFlag(0, true);

	var save = SaveData.Create(layout.Hash(), 0xDEADBEEF, 12, 345, 67, global);
	var kellerSave = MapSave.Create(1, "keller", keller);

	kellerSave.TileChanges.Add(TileChange { Layer = 2, X = 14, Y = 15, Tile = 2817 });
	kellerSave.Entities.Add(EntityState { Id = 3, X = 8, Y = 9, Facing = 1, Routine = 2 });
	save.Maps.Add(kellerSave);
	save.Maps.Add(MapSave.Create(2, "turm", turm));
	save.Party = new uint8[] { 1, 2, 3, 4, 5 };

	return save;
}

Error<void> SameTileChange(TileChange expected, TileChange actual)
{
	return Assert.Ints(new int[] { expected.Layer, expected.X, expected.Y, (int)expected.Tile }, new int[] { actual.Layer, actual.X, actual.Y, (int)actual.Tile });
}

Error<void> ASavegameRoundTrips()
{
	var save = OldSave(try LayoutOf(OldSaveSource));
	var read = try SaveData.Read(save.Write());

	try Assert.Equal(save.LayoutHash, read.LayoutHash);
	try Assert.Equal(0xDEADBEEF, read.RngState);
	try Assert.Ints(new int[] { 12, 345, 67 }, new int[] { read.Day, read.Minute, read.Tick });
	try Assert.Bytes(save.Party, read.Party);
	try Assert.True(read.Global.GetFlag(0));
	try Assert.False(read.Global.GetFlag(1));
	try Assert.Equal(7, read.Global.Vars[0]);
	try Assert.Equal(123456, read.Global.Vars32[0]);
	try Assert.Equal(2, read.Maps.Count());
	try Assert.Equal("keller", read.Maps.Get(0).Name);
	try Assert.Equal("turm", read.Maps.Get(1).Name);
	try Assert.Equal(-3, read.Maps.Get(0).State.Vars[0]);
	try SameTileChange(TileChange { Layer = 2, X = 14, Y = 15, Tile = 2817 }, try Assert.Single(read.Maps.Get(0).TileChanges));

	var entity = try Assert.Single(read.Maps.Get(0).Entities);

	try Assert.Ints(new int[] { 3, 8, 9, 1, 2 }, new int[] { entity.Id, entity.X, entity.Y, entity.Facing, entity.Routine });

	return;
}

Error<void> DamagedSavegamesAreRejected()
{
	var good = OldSave(try LayoutOf(OldSaveSource)).Write();

	try Assert.Fails(SaveData.Read(Slice(good, 0, 10)), ErrorKind.InvalidSave);
	try Assert.Fails(SaveData.Read(Slice(good, 0, good.Length - 5)), ErrorKind.InvalidSave);

	var flipped = CopyOf(good);

	flipped[30] = (uint8)((int)flipped[30] ^ 1);
	try Assert.Fails(SaveData.Read(flipped), ErrorKind.InvalidSave);

	var wrongMagic = CopyOf(good);

	wrongMagic[0] = (uint8)'X';
	try Assert.Fails(SaveData.Read(wrongMagic), ErrorKind.InvalidSave);

	return;
}

bool HasSlotNamed(List<LayoutSlot> slots, string name)
{
	foreach (var slot in slots)
	{
		if (slot.Name == name)
			return true;
	}

	return false;
}

Error<void> MigrationKeepsValuesByNameAndInitializesNewNames()
{
	var oldLayout = try LayoutOf(OldSaveSource);
	var newLayout = try LayoutOf(NewSaveSource);
	var maps = Dictionary<string, int>.Create();

	maps.Set("keller", 5);
	maps.Set("wald", 6);

	var result = try MigrateSave(OldSave(oldLayout), oldLayout, newLayout, maps);
	var data = result.Data;

	// global: alpha was set (index 0, now 2), beta was clear (index 1, now 0), gamma is new
	try Assert.Equal(newLayout.Hash(), data.LayoutHash);
	try Assert.Equal(3, data.Global.FlagCount);
	try Assert.True(data.Global.GetFlag(2));
	try Assert.False(data.Global.GetFlag(0));
	try Assert.False(data.Global.GetFlag(1));
	try Assert.Empty(data.Global.Vars);
	try Assert.Ints(new int[] { 123456, 0 }, data.Global.Vars32);

	// the map keller: schrein was set, hebel is gone, riegel is new; counter/besuche and punkte
	var keller = try Assert.Single(data.Maps);

	try Assert.Equal("keller", keller.Name);
	try Assert.Equal(5, keller.MapId);
	try Assert.Equal(2, keller.State.FlagCount);
	try Assert.False(keller.State.GetFlag(0));
	try Assert.True(keller.State.GetFlag(1));
	try Assert.Equal(1, keller.State.Vars.Length);
	try Assert.Equal(-3, keller.State.Vars[0]);
	try Assert.Empty(keller.State.Vars32);
	try SameTileChange(TileChange { Layer = 2, X = 14, Y = 15, Tile = 2817 }, try Assert.Single(keller.TileChanges));

	// what does not belong to the game any more is reported, nothing else changes
	try Assert.Strings(new string[] { "turm" }, result.DroppedMaps);
	try Assert.Equal(0xDEADBEEF, data.RngState);
	try Assert.Bytes(new uint8[] { 1, 2, 3, 4, 5 }, data.Party);
	try Assert.True(HasSlotNamed(result.Dropped, "counter"), "counter is dropped");
	try Assert.True(HasSlotNamed(result.Dropped, "hebel"), "hebel is dropped");
	try Assert.False(HasSlotNamed(result.Dropped, "offen"), "offen is not dropped");
	try Assert.True(HasSlotNamed(result.Added, "gamma"), "gamma is added");
	try Assert.True(HasSlotNamed(result.Added, "riegel"), "riegel is added");

	// the migrated savegame is a valid file for the new layout
	try Assert.Equal(newLayout.Hash(), (try SaveData.Read(data.Write())).LayoutHash);

	return;
}

Error<void> MigrationToTheSameLayoutChangesNothing()
{
	var layout = try LayoutOf(OldSaveSource);
	var save = OldSave(layout);
	var maps = Dictionary<string, int>.Create();

	maps.Set("keller", 1);
	maps.Set("turm", 2);

	var result = try MigrateSave(save, layout, layout, maps);

	try Assert.Bytes(save.Write(), result.Data.Write());
	try Assert.Empty(result.Dropped);
	try Assert.Empty(result.Added);
	try Assert.Empty(result.DroppedMaps);

	return;
}

Error<void> MigrationNeedsTheLayoutOfTheSavegame()
{
	var oldLayout = try LayoutOf(OldSaveSource);
	var newLayout = try LayoutOf(NewSaveSource);

	try Assert.Fails(MigrateSave(OldSave(oldLayout), newLayout, newLayout, Dictionary<string, int>.Create()), ErrorKind.InvalidSave);

	return;
}

Error<void> TheLayoutDiffListsAddedRemovedAndMovedNames()
{
	var diff = LayoutDiff.Compare(try LayoutOf(OldSaveSource), try LayoutOf(NewSaveSource));
	bool alphaMoved = false;

	foreach (var pair in diff.Moved)
		alphaMoved = alphaMoved || (pair.Old.Name == "alpha" && pair.Old.Index == 0 && pair.New.Index == 2);

	try Assert.True(HasSlotNamed(diff.Removed, "counter"), "counter is removed");
	try Assert.True(HasSlotNamed(diff.Added, "extra"), "extra is added");
	try Assert.True(alphaMoved, "alpha moved from 0 to 2");
	try Assert.False(diff.IsEmpty());
	try Assert.Contains("- Global global Global.Var[0] counter", diff.ToText());
	try Assert.True(LayoutDiff.Compare(try LayoutOf(OldSaveSource), try LayoutOf(OldSaveSource)).IsEmpty(), "the same layout has no difference");

	return;
}

Error<void> SnapshotsRestoreIntoStoresWithoutEvents()
{
	var sizes = StateSizes.Of(10, 2, 1);
	var store = StateStore.Create(sizes);

	store.SetFlag(9, true);
	store.SetVar(1, -5);
	store.SetVar32(0, 70000);

	var copy = StateSnapshot.From(store).ToStore();

	try Assert.True(copy.GetFlag(9));
	try Assert.Equal(-5, copy.GetVar(1));
	try Assert.Equal(70000, copy.GetVar32(0));
	try Assert.True(store.Sizes.Same(copy.Sizes), "the sizes are the same");
	try Assert.FailsVoid(StateSnapshot.Empty(1, 1, 1).RestoreTo(store), ErrorKind.InvalidSave);

	return;
}

/// Blocks at every say, does every other action (C#: SaveTests.BlockingHost).
struct SayBlockingHost : IGameHost
{
	ActionOutcome Execute(ActionOp op, uint16[] operands, const ref ThreadContext context)
	{
		return op == ActionOp.Say ? ActionOutcome.Blocked : ActionOutcome.Done;
	}

	bool Evaluate(ConditionOp op, uint16[] operands, const ref ThreadContext context)
	{
		return false;
	}
}

Error<void> SavingIsOnlyPossibleWhenNoScriptIsWaiting()
{
	var result = ScriptCompiler.CompileText("group g { do { say(T.a); } }\non hour(1) -> g;", "test.ams", CompileOptions { LenientSymbols = true });
	var host = new SayBlockingHost();
	var interpreter = Interpreter.Create(result.Global.ToChunk(), StateSizes.Of(0, 0, 0), RuntimeLimits.Default());

	try Assert.True(SaveData.CanSave(interpreter));

	interpreter.Trigger(ref host, WithParam(TriggerType.Hour, 1));

	try Assert.False(SaveData.CanSave(interpreter));

	interpreter.Resume(ref host, 0, 0);
	interpreter.Tick(ref host);

	try Assert.True(SaveData.CanSave(interpreter));

	return;
}
