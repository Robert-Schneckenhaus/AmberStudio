namespace Amber.Script.Common;

using System;

/// Trigger IDs as defined in spec section 3.
enum TriggerType : uint8
{
	None = 0x00,
	EnterTile = 0x01,
	LeaveTile = 0x02,
	Step = 0x03,
	Examine = 0x04,
	Speak = 0x05,
	Listen = 0x06,
	UseItem = 0x07,
	CastSpell = 0x08,
	MapEnter = 0x09,
	MapExit = 0x0A,
	MapTick = 0x0B,
	Keyword = 0x0C,
	ShowItem = 0x0D,
	GiveItem = 0x0E,
	GiveGold = 0x0F,
	GiveFood = 0x10,
	SeeParty = 0x11,
	EntityDied = 0x12,
	JoinRequest = 0x13,
	Interact = 0x14,
	Hour = 0x20,
	DayChange = 0x21,
	TravelStep = 0x22,
	WeatherChange = 0x23,
	FlagChanged = 0x30,
	VarChanged = 0x31,
	Custom = 0x32,
	ScreenOpen = 0x40,
	ScreenClose = 0x41,
	ScreenResume = 0x42,
	Click = 0x43,
	Hover = 0x44,
	Key = 0x45,
	RegionClick = 0x46,
	BattleEnd = 0x50,
	ItemGained = 0x51,
	MemberJoined = 0x52,
	MemberLeft = 0x53,
	LevelUp = 0x54
}

/// Scope of a binding (spec section 3).
enum TriggerScope : uint8
{
	Global = 0,
	Map = 1,
	Tile = 2,
	Area = 3,
	Entity = 4,
	Screen = 5,
	Node = 6
}

/// Flags of the scopes a trigger can be bound in (1 shifted by the scope value).
enum TriggerScopes : uint16
{
	None = 0,
	Global = 1,
	Map = 2,
	Tile = 4,
	Area = 8,
	Entity = 16,
	Screen = 32,
	Node = 64
}

/// Returns the flag which corresponds to the scope value (1 shifted by the scope value).
TriggerScopes ScopeFlag(TriggerScope scope)
{
	return (TriggerScopes)(1 << (int)scope);
}

/// The four state namespaces (spec section 1.2). The value is stored in the upper two bits of a slot.
enum StateNamespace : uint8
{
	Global = 0,
	Map = 1,
	Screen = 2,
	Thread = 3
}

enum GroupMode : uint8
{
	First = 0,
	All = 1
}

enum Comparison : uint8
{
	Equal = 0,
	NotEqual = 1,
	Less = 2,
	LessOrEqual = 3,
	Greater = 4,
	GreaterOrEqual = 5
}

/// Condition opcodes (spec section 4). Conditions and actions have separate opcode spaces.
enum ConditionOp : uint8
{
	Flag = 0x01,
	Var = 0x02,
	Var32 = 0x03,
	VarVar = 0x04,
	Result = 0x05,
	Arg = 0x06,
	Chance = 0x07,
	WordKnown = 0x08,
	HasItem = 0x09,
	HasMember = 0x0A,
	PartyClass = 0x0B,
	PartyRace = 0x0C,
	PartyLanguage = 0x0D,
	PartySize = 0x0E,
	Gold = 0x0F,
	Attribute = 0x10,
	Probe = 0x11,
	HourIn = 0x12,
	DayIn = 0x13,
	Season = 0x14,
	InMap = 0x15,
	Transport = 0x16,
	World = 0x17,
	SpellActive = 0x18,
	TileIs = 0x19,
	ScreenOpen = 0x1A,
	MemberCondition = 0x1B,
	Near = 0x1C,
	Facing = 0x1D,
	InputMatches = 0x1E
}

/// Action opcodes (spec section 5).
enum ActionOp : uint8
{
	SetFlag = 0x01,
	ClearFlag = 0x02,
	ToggleFlag = 0x03,
	SetVar = 0x04,
	AddVar = 0x05,
	SetVar32 = 0x06,
	AddVar32 = 0x07,
	CopyVar = 0x08,
	LearnWord = 0x09,

	Teleport = 0x10,
	SetTile = 0x11,
	SetTileOn = 0x12,
	Spawn = 0x13,
	Despawn = 0x14,
	MoveEntity = 0x15,
	SetDir = 0x16,
	SetLight = 0x17,
	SetWeather = 0x18,
	SetWorld = 0x19,
	SetRoutine = 0x1A,
	SetModifier = 0x1B,
	ApplyDelta = 0x1C,

	GiveItem = 0x20,
	TakeItem = 0x21,
	GiveGold = 0x22,
	TakeGold = 0x23,
	GiveFood = 0x24,
	TakeFood = 0x25,
	GiveXp = 0x26,
	AddMember = 0x27,
	RemoveMember = 0x28,
	Heal = 0x29,
	Damage = 0x2A,
	AddCondition = 0x2B,
	RemoveCondition = 0x2C,
	ChangeAttribute = 0x2D,
	TeachSpell = 0x2E,
	MoveAll = 0x2F,

	Battle = 0x30,
	Trap = 0x31,
	CastEffect = 0x32,

	Say = 0x40,
	SayPicture = 0x41,
	AskWord = 0x42,
	AskChoice = 0x43,
	Confirm = 0x44,
	Bark = 0x45,

	PushScreen = 0x50,
	PopScreen = 0x51,
	ReplaceScreen = 0x52,
	SetNode = 0x53,
	ShowNode = 0x54,
	HideNode = 0x55,
	EnableNode = 0x56,
	DisableNode = 0x57,
	SetText = 0x58,

	Music = 0x60,
	Sfx = 0x61,
	Fade = 0x62,
	Shake = 0x63,
	Flash = 0x64,
	PlayOutro = 0x65,
	SetPalette = 0x66,
	FadePalette = 0x67,

	AdvanceTime = 0x70,
	Wait = 0x71,

	Raise = 0x78,
	Autosave = 0x79,
	Native = 0x7F
}

/// Kinds of script scopes (and of the chunks compiled from them).
enum ScopeKind : int32
{
	Global,
	Map,
	Screen
}

// ---------------------------------------------------------------------------------------------------------------------
// Names of the enum members (C#: Enum.ToString(), Enum.GetValues()). CShift enums have no names at run time, so every enum
// whose names are printed has a table here, in declaration order.
// ---------------------------------------------------------------------------------------------------------------------

struct EnumEntry
{
	string Name;
	int Value;
}

EnumEntry En(string name, int value)
{
	return EnumEntry { Name = name, Value = value };
}

/// The name of the value, or the number if the table has no member with that value (like Enum.ToString()).
string EnumName(EnumEntry[] table, int value)
{
	for (var i = 0; i < table.Length; i += 1)
	{
		if (table[i].Value == value)
			return table[i].Name;
	}

	return value.ToString();
}

bool EnumDefined(EnumEntry[] table, int value)
{
	for (var i = 0; i < table.Length; i += 1)
	{
		if (table[i].Value == value)
			return true;
	}

	return false;
}

EnumEntry[] TriggerTypeNames = new EnumEntry[]
{
	En("None", 0x00), En("EnterTile", 0x01), En("LeaveTile", 0x02), En("Step", 0x03), En("Examine", 0x04), En("Speak", 0x05),
	En("Listen", 0x06), En("UseItem", 0x07), En("CastSpell", 0x08), En("MapEnter", 0x09), En("MapExit", 0x0A),
	En("MapTick", 0x0B), En("Keyword", 0x0C), En("ShowItem", 0x0D), En("GiveItem", 0x0E), En("GiveGold", 0x0F),
	En("GiveFood", 0x10), En("SeeParty", 0x11), En("EntityDied", 0x12), En("JoinRequest", 0x13), En("Interact", 0x14),
	En("Hour", 0x20), En("DayChange", 0x21), En("TravelStep", 0x22), En("WeatherChange", 0x23), En("FlagChanged", 0x30),
	En("VarChanged", 0x31), En("Custom", 0x32), En("ScreenOpen", 0x40), En("ScreenClose", 0x41), En("ScreenResume", 0x42),
	En("Click", 0x43), En("Hover", 0x44), En("Key", 0x45), En("RegionClick", 0x46), En("BattleEnd", 0x50),
	En("ItemGained", 0x51), En("MemberJoined", 0x52), En("MemberLeft", 0x53), En("LevelUp", 0x54)
};

EnumEntry[] TriggerScopeNames = new EnumEntry[]
{
	En("Global", 0), En("Map", 1), En("Tile", 2), En("Area", 3), En("Entity", 4), En("Screen", 5), En("Node", 6)
};

EnumEntry[] StateNamespaceNames = new EnumEntry[] { En("Global", 0), En("Map", 1), En("Screen", 2), En("Thread", 3) };

EnumEntry[] GroupModeNames = new EnumEntry[] { En("First", 0), En("All", 1) };

EnumEntry[] ComparisonNames = new EnumEntry[]
{
	En("Equal", 0), En("NotEqual", 1), En("Less", 2), En("LessOrEqual", 3), En("Greater", 4), En("GreaterOrEqual", 5)
};

EnumEntry[] ConditionOpNames = new EnumEntry[]
{
	En("Flag", 0x01), En("Var", 0x02), En("Var32", 0x03), En("VarVar", 0x04), En("Result", 0x05), En("Arg", 0x06),
	En("Chance", 0x07), En("WordKnown", 0x08), En("HasItem", 0x09), En("HasMember", 0x0A), En("PartyClass", 0x0B),
	En("PartyRace", 0x0C), En("PartyLanguage", 0x0D), En("PartySize", 0x0E), En("Gold", 0x0F), En("Attribute", 0x10),
	En("Probe", 0x11), En("HourIn", 0x12), En("DayIn", 0x13), En("Season", 0x14), En("InMap", 0x15), En("Transport", 0x16),
	En("World", 0x17), En("SpellActive", 0x18), En("TileIs", 0x19), En("ScreenOpen", 0x1A), En("MemberCondition", 0x1B),
	En("Near", 0x1C), En("Facing", 0x1D), En("InputMatches", 0x1E)
};

EnumEntry[] ActionOpNames = new EnumEntry[]
{
	En("SetFlag", 0x01), En("ClearFlag", 0x02), En("ToggleFlag", 0x03), En("SetVar", 0x04), En("AddVar", 0x05),
	En("SetVar32", 0x06), En("AddVar32", 0x07), En("CopyVar", 0x08), En("LearnWord", 0x09),
	En("Teleport", 0x10), En("SetTile", 0x11), En("SetTileOn", 0x12), En("Spawn", 0x13), En("Despawn", 0x14),
	En("MoveEntity", 0x15), En("SetDir", 0x16), En("SetLight", 0x17), En("SetWeather", 0x18), En("SetWorld", 0x19),
	En("SetRoutine", 0x1A), En("SetModifier", 0x1B), En("ApplyDelta", 0x1C),
	En("GiveItem", 0x20), En("TakeItem", 0x21), En("GiveGold", 0x22), En("TakeGold", 0x23), En("GiveFood", 0x24),
	En("TakeFood", 0x25), En("GiveXp", 0x26), En("AddMember", 0x27), En("RemoveMember", 0x28), En("Heal", 0x29),
	En("Damage", 0x2A), En("AddCondition", 0x2B), En("RemoveCondition", 0x2C), En("ChangeAttribute", 0x2D),
	En("TeachSpell", 0x2E), En("MoveAll", 0x2F),
	En("Battle", 0x30), En("Trap", 0x31), En("CastEffect", 0x32),
	En("Say", 0x40), En("SayPicture", 0x41), En("AskWord", 0x42), En("AskChoice", 0x43), En("Confirm", 0x44),
	En("Bark", 0x45),
	En("PushScreen", 0x50), En("PopScreen", 0x51), En("ReplaceScreen", 0x52), En("SetNode", 0x53), En("ShowNode", 0x54),
	En("HideNode", 0x55), En("EnableNode", 0x56), En("DisableNode", 0x57), En("SetText", 0x58),
	En("Music", 0x60), En("Sfx", 0x61), En("Fade", 0x62), En("Shake", 0x63), En("Flash", 0x64), En("PlayOutro", 0x65), En("SetPalette", 0x66), En("FadePalette", 0x67),
	En("AdvanceTime", 0x70), En("Wait", 0x71),
	En("Raise", 0x78), En("Autosave", 0x79), En("Native", 0x7F)
};

EnumEntry[] ScopeKindNames = new EnumEntry[] { En("Global", 0), En("Map", 1), En("Screen", 2) };

string TriggerTypeName(TriggerType value)
{
	return EnumName(TriggerTypeNames, (int)value);
}

string TriggerScopeName(TriggerScope value)
{
	return EnumName(TriggerScopeNames, (int)value);
}

string StateNamespaceName(StateNamespace value)
{
	return EnumName(StateNamespaceNames, (int)value);
}

string GroupModeName(GroupMode value)
{
	return EnumName(GroupModeNames, (int)value);
}

string ActionOpName(ActionOp value)
{
	return EnumName(ActionOpNames, (int)value);
}

string ConditionOpName(ConditionOp value)
{
	return EnumName(ConditionOpNames, (int)value);
}

string ScopeKindName(ScopeKind value)
{
	return EnumName(ScopeKindNames, (int)value);
}
