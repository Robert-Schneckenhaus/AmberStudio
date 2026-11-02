// Action opcode table (spec section 5).

namespace Amber.Script.Common.ActionTable;

using System;

OpInfo[] All = new OpInfo[]
{
	O.Op((uint8)ActionOp.SetFlag, "set_flag", O.Ops(O.Flag()), false, -1),
	O.Op((uint8)ActionOp.ClearFlag, "clear_flag", O.Ops(O.Flag()), false, -1),
	O.Op((uint8)ActionOp.ToggleFlag, "toggle_flag", O.Ops(O.Flag()), false, -1),
	O.Op((uint8)ActionOp.SetVar, "set_var", O.Ops(O.Var(), O.Int16("value")), false, -1),
	O.Op((uint8)ActionOp.AddVar, "add_var", O.Ops(O.Var(), O.Int16("delta")), false, -1),
	O.Op((uint8)ActionOp.SetVar32, "set_var32", O.Ops(O.Var32(), O.Int32("value")), false, -1),
	O.Op((uint8)ActionOp.AddVar32, "add_var32", O.Ops(O.Var32(), O.Int32("delta")), false, -1),
	O.Op((uint8)ActionOp.CopyVar, "copy_var", O.Ops(O.Var("dst"), O.Var("src")), false, -1),
	O.Op((uint8)ActionOp.LearnWord, "learn_word", O.Ops(O.Sym(SymbolKind.Keyword, "word")), false, -1),

	O.Op((uint8)ActionOp.Teleport, "teleport", O.Ops(O.Sym(SymbolKind.Map, "map"), O.Word("x"), O.Word("y"), O.Dir(), O.Word("fade")), true, -1),
	O.Op((uint8)ActionOp.SetTile, "set_tile", O.Ops(O.Word("layer"), O.Pos(true), O.Tile()), false, -1),
	O.Op((uint8)ActionOp.SetTileOn, "set_tile_on", O.Ops(O.Sym(SymbolKind.Map, "map"), O.Word("layer"), O.Word("x"), O.Word("y"), O.Sym(SymbolKind.Tile, "tile")), false, -1),
	O.Op((uint8)ActionOp.Spawn, "spawn", O.Ops(O.Entity(), O.Pos(true)), false, -1),
	O.Op((uint8)ActionOp.Despawn, "despawn", O.Ops(O.Entity()), false, -1),
	O.Op((uint8)ActionOp.MoveEntity, "move_entity", O.Ops(O.Entity(), O.Pos(true), O.Word("speed")), false, -1),
	O.Op((uint8)ActionOp.SetDir, "set_dir", O.Ops(O.Entity(), O.Dir()), false, -1),
	O.Op((uint8)ActionOp.SetLight, "set_light", O.Ops(O.Word("mode"), O.Word("radius")), false, -1),
	O.Op((uint8)ActionOp.SetWeather, "set_weather", O.Ops(O.Word("weather")), false, -1),
	O.Op((uint8)ActionOp.SetWorld, "set_world", O.Ops(O.Word("world")), false, -1),
	O.Op((uint8)ActionOp.SetRoutine, "set_routine", O.Ops(O.Entity(), O.Sym(SymbolKind.Routine, "routine")), false, -1),
	O.Op((uint8)ActionOp.SetModifier, "set_modifier", O.Ops(O.Modifier(), O.Word("value")), false, -1),
	O.Op((uint8)ActionOp.ApplyDelta, "apply_delta", O.Ops(O.Sym(SymbolKind.Delta, "delta")), false, -1),

	O.Op((uint8)ActionOp.GiveItem, "give_item", O.Ops(O.Sym(SymbolKind.Item, "item"), O.Word("count")), false, -1),
	O.Op((uint8)ActionOp.TakeItem, "take_item", O.Ops(O.Sym(SymbolKind.Item, "item"), O.Word("count")), false, -1),
	O.Op((uint8)ActionOp.GiveGold, "give_gold", O.Ops(O.Int32("amount")), false, -1),
	O.Op((uint8)ActionOp.TakeGold, "take_gold", O.Ops(O.Int32("amount")), false, -1),
	O.Op((uint8)ActionOp.GiveFood, "give_food", O.Ops(O.Word("amount")), false, -1),
	O.Op((uint8)ActionOp.TakeFood, "take_food", O.Ops(O.Word("amount")), false, -1),
	O.Op((uint8)ActionOp.GiveXp, "give_xp", O.Ops(O.Target(), O.Int32("amount")), false, -1),
	O.Op((uint8)ActionOp.AddMember, "add_member", O.Ops(O.Sym(SymbolKind.Character, "character")), false, -1),
	O.Op((uint8)ActionOp.RemoveMember, "remove_member", O.Ops(O.Sym(SymbolKind.Character, "character")), false, -1),
	O.Op((uint8)ActionOp.Heal, "heal", O.Ops(O.Target(), O.Int16("hp"), O.Int16("sp")), false, -1),
	O.Op((uint8)ActionOp.Damage, "damage", O.Ops(O.Target(), O.Int16("amount"), O.Word("kind")), false, -1),
	O.Op((uint8)ActionOp.AddCondition, "add_condition", O.Ops(O.Target(), O.Word("condition")), false, -1),
	O.Op((uint8)ActionOp.RemoveCondition, "remove_condition", O.Ops(O.Target(), O.Word("condition")), false, -1),
	O.Op((uint8)ActionOp.ChangeAttribute, "change_attr", O.Ops(O.Target(), O.Sym(SymbolKind.Attribute, "attribute"), O.Int16("delta")), false, -1),
	O.Op((uint8)ActionOp.TeachSpell, "teach_spell", O.Ops(O.Target(), O.Sym(SymbolKind.Spell, "spell")), false, -1),
	O.Op((uint8)ActionOp.MoveAll, "move_all", O.Ops(O.MoveSource(), O.Target()), false, -1),

	O.Op((uint8)ActionOp.Battle, "battle", O.Ops(O.Sym(SymbolKind.MonsterGroup, "group"), O.Word("flags")), true, -1),
	O.Op((uint8)ActionOp.Trap, "trap", O.Ops(O.Sym(SymbolKind.Trap, "trap"), O.Int16("damage")), true, -1),
	O.Op((uint8)ActionOp.CastEffect, "cast_effect", O.Ops(O.Sym(SymbolKind.Effect, "effect"), O.Target()), false, -1),

	O.Op((uint8)ActionOp.Say, "say", O.Ops(O.Sym(SymbolKind.Text, "text")), true, -1),
	O.Op((uint8)ActionOp.SayPicture, "say_picture", O.Ops(O.Sym(SymbolKind.Picture, "picture"), O.Sym(SymbolKind.Text, "text")), true, -1),
	O.Op((uint8)ActionOp.AskWord, "ask_word", O.Ops(O.Sym(SymbolKind.WordList, "words")), true, -1),
	O.Op((uint8)ActionOp.AskChoice, "ask_choice", O.Ops(O.Sym(SymbolKind.Text, "text"), O.Sym(SymbolKind.WordList, "choices")), true, -1),
	O.Op((uint8)ActionOp.Confirm, "confirm", O.Ops(O.Sym(SymbolKind.Text, "text")), true, -1),
	O.Op((uint8)ActionOp.Bark, "bark", O.Ops(O.Entity(), O.Sym(SymbolKind.Text, "text")), false, -1),

	O.Op((uint8)ActionOp.PushScreen, "push_screen", O.Ops(O.Sym(SymbolKind.Screen, "screen"), O.Word("flags"), O.Word("argc")), true, 2),
	O.Op((uint8)ActionOp.PopScreen, "pop_screen", O.Ops(O.Int16("result")), false, -1),
	O.Op((uint8)ActionOp.ReplaceScreen, "replace_screen", O.Ops(O.Sym(SymbolKind.Screen, "screen"), O.Word("flags"), O.Word("argc")), false, 2),
	O.Op((uint8)ActionOp.SetNode, "set_node", O.Ops(O.Node(), O.Word("property"), O.Int16("value")), false, -1),
	O.Op((uint8)ActionOp.ShowNode, "show_node", O.Ops(O.Node()), false, -1),
	O.Op((uint8)ActionOp.HideNode, "hide_node", O.Ops(O.Node()), false, -1),
	O.Op((uint8)ActionOp.EnableNode, "enable_node", O.Ops(O.Node()), false, -1),
	O.Op((uint8)ActionOp.DisableNode, "disable_node", O.Ops(O.Node()), false, -1),
	O.Op((uint8)ActionOp.SetText, "set_text", O.Ops(O.Node(), O.Sym(SymbolKind.Text, "text")), false, -1),

	O.Op((uint8)ActionOp.Music, "music", O.Ops(O.Sym(SymbolKind.Music, "music")), false, -1),
	O.Op((uint8)ActionOp.Sfx, "sfx", O.Ops(O.Sym(SymbolKind.Sound, "sound")), false, -1),
	O.Op((uint8)ActionOp.Fade, "fade", O.Ops(O.Word("direction"), O.Word("ticks")), true, -1),
	O.Op((uint8)ActionOp.Shake, "shake", O.Ops(O.Word("ticks")), false, -1),
	O.Op((uint8)ActionOp.Flash, "flash", O.Ops(O.Word("color"), O.Word("ticks")), false, -1),
	O.Op((uint8)ActionOp.PlayOutro, "play_outro", O.NoOps(), true, -1),
	O.Op((uint8)ActionOp.SetPalette, "set_palette", O.Ops(O.Sym(SymbolKind.Palette, "palette")), false, -1),
	O.Op((uint8)ActionOp.FadePalette, "fade_palette", O.Ops(O.Sym(SymbolKind.Palette, "palette"), O.Word("ticks"), O.Word("flags")), true, -1),

	O.Op((uint8)ActionOp.AdvanceTime, "advance_time", O.Ops(O.Word("minutes")), false, -1),
	O.Op((uint8)ActionOp.Wait, "wait", O.Ops(O.Word("ticks")), true, -1),

	O.Op((uint8)ActionOp.Raise, "raise", O.Ops(O.Custom(), O.Int16("value")), false, -1),
	O.Op((uint8)ActionOp.Autosave, "autosave", O.NoOps(), false, -1),
	O.Op((uint8)ActionOp.Native, "native", O.Ops(O.Sym(SymbolKind.Native, "native"), O.Word("argc")), false, 1)
};

Dictionary<string, int> ByNameIndex = BuildNameIndex();

Dictionary<string, int> BuildNameIndex()
{
	var index = Dictionary<string, int>.Create();

	for (var i = 0; i < All.Length; i += 1)
		index.Set(All[i].Name, i);

	return index;
}

/// The opcode with this source name, or no value.
Optional<OpInfo> ByName(string name)
{
	if (ByNameIndex.TryGet(name) is int index)
		return All[index];

	return null;
}

/// The opcode with this number, or no value.
Optional<OpInfo> ByOp(int op)
{
	for (var i = 0; i < All.Length; i += 1)
	{
		if ((int)All[i].Op == op)
			return All[i];
	}

	return null;
}
