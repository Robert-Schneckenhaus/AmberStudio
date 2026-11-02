namespace Amber.Player.Game;

using System;
using Amber.Base;

/// The native functions and data sources the game implements (C#: ScreenHost.natives).
const ReadOnlySlice<string> GameNatives =
[
	// functions of the scripts (native action)
	"pop_arg", "conversation_ask", "conversation_ask_result", "conversation_give", "conversation_show", "lookup_word",
	"chest_take", "chest_put", "chest_take_all", "chest_take_gold", "chest_close", "shop_buy", "shop_sell", "party_give", "party_take_off",
	// data sources of the screens (bind, source)
	"party.gold", "party.words", "party.words.hint", "party.items", "chest.gold", "chest.items", "conversation.title", "input.message",
	"shop.items", "shop.pack", "shop.message", "party.hp", "party.stats", "party.members", "party.message", "member.stats", "member.gear",
	"member.spells"
];

/// True if the game implements the native function or data source (the load check of a pack, spec section 9.4). The
/// sources "screen.<argument>" belong to every screen.
bool ImplementsNative(string native)
{
	return ContainsText(GameNatives, native) || native.StartsWith("screen.");
}
