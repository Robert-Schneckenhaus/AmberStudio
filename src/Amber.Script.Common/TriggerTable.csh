// Trigger table (spec section 3).

namespace Amber.Script.Common.TriggerTable;

using System;

const TriggerScopes TileOrEntity = TriggerScopes.Tile | TriggerScopes.Area | TriggerScopes.Entity;

TriggerInfo T(TriggerType type, string name, TriggerScopes scopes, Optional<OperandSpec> p1, Optional<OperandSpec> p2, bool nodeFirst)
{
	return TriggerInfo { Type = type, Name = name, Scopes = scopes, P1 = p1, P2 = p2, NodeFirst = nodeFirst };
}

TriggerInfo[] All = new TriggerInfo[]
{
	T(TriggerType.EnterTile, "enter_tile", TriggerScopes.Tile | TriggerScopes.Area | TriggerScopes.Entity, null, null, false),
	T(TriggerType.LeaveTile, "leave_tile", TriggerScopes.Tile | TriggerScopes.Area | TriggerScopes.Entity, null, null, false),
	T(TriggerType.Step, "step", TriggerScopes.Tile | TriggerScopes.Area, null, null, false),
	T(TriggerType.Examine, "examine", TileOrEntity, null, null, false),
	T(TriggerType.Speak, "speak", TileOrEntity, null, null, false),
	T(TriggerType.Listen, "listen", TileOrEntity, null, null, false),
	T(TriggerType.UseItem, "use_item", TileOrEntity, O.Sym(SymbolKind.Item, "item"), null, false),
	T(TriggerType.CastSpell, "cast_spell", TileOrEntity, O.Sym(SymbolKind.Spell, "spell"), null, false),
	T(TriggerType.MapEnter, "map_enter", TriggerScopes.Map, null, null, false),
	T(TriggerType.MapExit, "map_exit", TriggerScopes.Map, null, null, false),
	T(TriggerType.MapTick, "map_tick", TriggerScopes.Map, O.Word("interval"), null, false),
	T(TriggerType.Keyword, "keyword", TriggerScopes.Entity, null, null, false),
	T(TriggerType.ShowItem, "show_item", TriggerScopes.Entity, null, null, false),
	T(TriggerType.GiveItem, "give_item", TriggerScopes.Entity, null, null, false),
	T(TriggerType.GiveGold, "give_gold", TriggerScopes.Entity, null, null, false),
	T(TriggerType.GiveFood, "give_food", TriggerScopes.Entity, null, null, false),
	T(TriggerType.SeeParty, "see_party", TriggerScopes.Entity, O.Word("range"), null, false),
	T(TriggerType.EntityDied, "entity_died", TriggerScopes.Entity, null, null, false),
	T(TriggerType.JoinRequest, "join_request", TriggerScopes.Entity, null, null, false),
	T(TriggerType.Interact, "interact", TileOrEntity, null, null, false),
	T(TriggerType.Hour, "hour", TriggerScopes.Global | TriggerScopes.Map, O.Word("hour"), null, false),
	T(TriggerType.DayChange, "day_change", TriggerScopes.Global, null, null, false),
	T(TriggerType.TravelStep, "travel_step", TriggerScopes.Global | TriggerScopes.Map, null, null, false),
	T(TriggerType.WeatherChange, "weather_change", TriggerScopes.Global, O.Word("weather"), null, false),
	T(TriggerType.FlagChanged, "flag_changed", TriggerScopes.Global | TriggerScopes.Map, O.Flag(), O.FlagMode(), false),
	T(TriggerType.VarChanged, "var_changed", TriggerScopes.Global | TriggerScopes.Map, O.Var(), null, false),
	T(TriggerType.Custom, "custom", TriggerScopes.Global | TriggerScopes.Map, O.Custom(), null, false),
	T(TriggerType.ScreenOpen, "screen_open", TriggerScopes.Screen, null, null, false),
	T(TriggerType.ScreenClose, "screen_close", TriggerScopes.Screen, null, null, false),
	T(TriggerType.ScreenResume, "screen_resume", TriggerScopes.Screen, null, null, false),
	T(TriggerType.Click, "click", TriggerScopes.Node, O.Word("buttons"), null, true),
	T(TriggerType.Hover, "hover", TriggerScopes.Node, null, null, true),
	T(TriggerType.Key, "key", TriggerScopes.Global | TriggerScopes.Screen, O.Word("key"), null, false),
	T(TriggerType.RegionClick, "region_click", TriggerScopes.Area, O.Word("buttons"), null, false),
	T(TriggerType.BattleEnd, "battle_end", TriggerScopes.Global, O.Sym(SymbolKind.MonsterGroup, "group"), null, false),
	T(TriggerType.ItemGained, "item_gained", TriggerScopes.Global, O.Sym(SymbolKind.Item, "item"), null, false),
	T(TriggerType.MemberJoined, "member_joined", TriggerScopes.Global, O.Sym(SymbolKind.Character, "character"), null, false),
	T(TriggerType.MemberLeft, "member_left", TriggerScopes.Global, O.Sym(SymbolKind.Character, "character"), null, false),
	T(TriggerType.LevelUp, "level_up", TriggerScopes.Global, null, null, false)
};

/// The trigger with this source name, or no value.
Optional<TriggerInfo> ByName(string name)
{
	for (var i = 0; i < All.Length; i += 1)
	{
		if (All[i].Name == name)
			return All[i];
	}

	return null;
}

/// The trigger with this type, or no value.
Optional<TriggerInfo> ByType(TriggerType type)
{
	for (var i = 0; i < All.Length; i += 1)
	{
		if (All[i].Type == type)
			return All[i];
	}

	return null;
}
