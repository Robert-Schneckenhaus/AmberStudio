// Keyword constants of the source language (spec section 7.3).

namespace Amber.Script.Common.KeywordConstants;

using System;

/// The value of a keyword for an operand kind (target "leader", direction "up" ...), or no value.
Optional<uint16> Get(OperandKind kind, string name)
{
	switch (kind)
	{
		case OperandKind.Target:
			switch (name)
			{
				case "active": return 0;
				case "any": return 1;
				case "all": return 2;
				case "leader": return 3;
				default:
					if (name.Length == 5 && name.StartsWith("slot") && name[4] >= '1' && name[4] <= '6')
						return (uint16)(4 + (name[4] - '1'));

					break;
			}

			break;
		case OperandKind.Direction:
			switch (name)
			{
				case "up": return 0;
				case "right": return 1;
				case "down": return 2;
				case "left": return 3;
				case "keep": return 0xFF;
				case "random": return 0xFF;
				default: break;
			}

			break;
		case OperandKind.Entity:
			if (name == "party")
				return Wire.None;

			break;
		case OperandKind.Modifier:
			switch (name)
			{
				case "antimagic": return 0;
				case "no_rest": return 1;
				case "no_map_spell": return 2;
				default: break;
			}

			break;
		case OperandKind.MoveSource:
			switch (name)
			{
				case "chest_all": return 1;
				case "chest_gold": return 2;
				case "chest_items": return 3;
				case "chest_food": return 4;
				default: break;
			}

			break;
		case OperandKind.FlagMode:
			switch (name)
			{
				case "any": return 0;
				case "set": return 1;
				case "cleared": return 2;
				default: break;
			}

			break;
		default:
			break;
	}

	return null;
}
