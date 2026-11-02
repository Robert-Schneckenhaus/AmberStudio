// The companions of the hero: up to four, they join by script (add_member), follow the hero from
// map to map and fight on their own; the player never steers them. Their role decides what they do in a fight:
// the healer heals whoever is hurt most (below 60 %) and else shields the hero, the mage casts a spell that also hits the
// monsters next to its target and picks the target with the most monsters around it, the ranger shoots the weakest
// monster in range. They do not block the way of the hero.

namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Content;
using Amber.Player.Graphics;

const int MaxCompanions = 4;
/// A healer heals a figure below this share of its hit points (percent).
const int HealBelowPercent = 60;
/// The healer's shield (a shield spell) lasts this many ticks.
const int ShieldTicks = 600;
/// A companion this far away from the hero (tiles) is put next to it (it lost the way).
const int CatchUpDistance = 10;

/// A companion in the party.
struct Companion
{
	CompanionInfo Info;
	Actor Actor;
	int Hp;
	int Cooldown;
	/// The item it wears as weapon and as armor (0 for none).
	int Weapon;
	int Armor;
	/// The spells it knows (symbol IDs).
	List<int> Spells;

	int Attack(GameContent content)
	{
		return Info.Attack + content.Items.GetOrDefault(Weapon, new ItemInfo()).Attack;
	}

	int Defense(GameContent content)
	{
		return Info.Defense + content.Items.GetOrDefault(Armor, new ItemInfo()).Defense;
	}

	/// The strongest spell of the kind it knows: its power, or -1 if it knows none.
	int BestPower(GameContent content, string kind)
	{
		int best = -1;

		foreach (var id in Spells)
		{
			var spell = content.Spells.GetOrDefault(id, new SpellInfo());

			if (spell.Kind == kind)
				best = Max(best, spell.Power);
		}

		return best;
	}
}

/// The roles that can learn a kind of spell: heal and shield are for healers, bolt and blast for mages.
bool CanLearn(string role, string kind)
{
	return role == "healer" ? kind == "heal" || kind == "shield" : role == "mage" && (kind == "bolt" || kind == "blast");
}

/// The companions of the party. A handle; part of the session.
struct Squad
{
	List<Companion> Members;
	/// Counts every change of the companions (the party screen redraws its labels).
	int64[] _version;

	static Squad Create()
	{
		return Squad { Members = List<Companion>.Create(), _version = new int64[1] };
	}

	int64 Version()
	{
		return _version[0];
	}

	void Changed()
	{
		_version[0] += 1;
	}

	int IndexOf(int id)
	{
		for (var i = 0; i < Members.Count(); i += 1)
		{
			if (Members.Get(i).Info.Id == id)
				return i;
		}

		return -1;
	}

	/// The companion wears the item (a weapon or an armor from the pack); what it wore goes back to the pack. Or it learns the
	/// spell of a scroll (the scroll is used up). Returns what happened, for the screen.
	string Use(GameSession session, int id, int item)
	{
		int index = IndexOf(id);
		var content = session.Content;
		var party = session.Party;

		if (index < 0 || party.Count(item) == 0)
			return "";

		var member = Members.Get(index);
		var info = content.Items.GetOrDefault(item, new ItemInfo());

		if (info.Teaches > 0)
		{
			var spell = content.Spells.GetOrDefault(info.Teaches, new SpellInfo());

			if (!CanLearn(member.Info.Role, spell.Kind))
				return member.Info.Name + " cannot learn " + spell.Name + ".";

			if (member.Spells.Contains(spell.Id))
				return member.Info.Name + " knows " + spell.Name + " already.";

			party.RemoveItem(item, 1);
			member.Spells.Add(spell.Id);
			Members.Set(index, member);
			Changed();

			return member.Info.Name + " learns " + spell.Name + ".";
		}

		if (info.Slot == "")
			return member.Info.Name + " cannot use " + info.Name + ".";

		party.RemoveItem(item, 1);

		int old = info.Slot == "weapon" ? member.Weapon : member.Armor;

		if (old > 0)
			party.AddItem(old, 1);

		if (info.Slot == "weapon")
			member.Weapon = item;
		else
			member.Armor = item;

		Members.Set(index, member);
		Changed();

		return member.Info.Name + " takes " + info.Name + ".";
	}

	/// Weapon and armor of the companion go back to the pack.
	string TakeOff(GameSession session, int id)
	{
		int index = IndexOf(id);

		if (index < 0)
			return "";

		var member = Members.Get(index);

		if (member.Weapon > 0)
			session.Party.AddItem(member.Weapon, 1);

		if (member.Armor > 0)
			session.Party.AddItem(member.Armor, 1);

		member.Weapon = 0;
		member.Armor = 0;
		Members.Set(index, member);
		Changed();

		return member.Info.Name + " gives you the gear back.";
	}

	/// The gear and spells of a savegame (without spells, version 3, the companion keeps the ones it starts with).
	void Restore(int id, int weapon, int armor, bool hasSpells, List<int> spells)
	{
		int index = IndexOf(id);

		if (index < 0)
			return;

		var member = Members.Get(index);

		member.Weapon = weapon;
		member.Armor = armor;

		if (hasSpells)
		{
			member.Spells.Clear();
			member.Spells.AddRange(spells.ToArray());
		}

		Members.Set(index, member);
		Changed();
	}

	/// teach_spell.
	void Teach(GameSession session, int id, int spell)
	{
		int index = IndexOf(id);

		if (index < 0)
			return;

		var member = Members.Get(index);

		if (!member.Spells.Contains(spell))
		{
			member.Spells.Add(spell);
			Members.Set(index, member);
			Changed();
		}
	}

	bool Has(int id)
	{
		foreach (var member in Members)
		{
			if (member.Info.Id == id)
				return true;
		}

		return false;
	}

	/// add_member: the companion joins next to the hero (no effect if it is there or the party is full).
	Error<void> Join(GameSession session, int id, int hp)
	{
		if (Has(id) || Members.Count() >= MaxCompanions)
			return;

		if (session.Content.Companions.TryGet(id) is not CompanionInfo info)
			return error("add_member: the companion " + id + " does not exist", (int)ErrorKind.InvalidData);

		var art = try CreateArt(session.Content, info.Look, DummyBody(info.Key), DummyHair(info.Key));
		var actor = Actor.Create(info.Key, -2000 - id, art);
		var world = session.World();
		var place = FreeTileNearFigures(world, session.Player.TileX(), session.Player.TileY() + 1, actor);

		actor.SetBlocking(false);
		actor.PlaceAt(place.X, place.Y);
		world.Actors.Add(actor);
		var spells = List<int>.Create();

		spells.AddRange(info.Spells);
		Members.Add(Companion { Info = info, Actor = actor, Hp = hp > 0 ? Min(hp, info.Hp) : info.Hp, Cooldown = 0, Weapon = 0, Armor = 0, Spells = spells });
		Changed();

		return;
	}

	/// remove_member.
	void Leave(GameSession session, int id)
	{
		for (var i = Members.Count() - 1; i >= 0; i -= 1)
		{
			if (Members.Get(i).Info.Id == id)
			{
				session.World().Remove(Members.Get(i).Actor);
				Members.RemoveAt(i);
				Changed();
			}
		}
	}

	/// The party changes the map: the companions come along and stand next to the hero.
	void MoveTo(GameWorld from, GameWorld to, Actor player)
	{
		foreach (var member in Members)
		{
			from.Remove(member.Actor);

			if (!to.Contains(member.Actor))
				to.Actors.Add(member.Actor);

			var place = FreeTileNearFigures(to, player.TileX(), player.TileY() + 1, member.Actor);

			member.Actor.PlaceAt(place.X, place.Y);
		}
	}

	/// Outside of fights: every companion keeps close to the hero (the first one right behind, the others a bit further).
	void Follow(GameWorld world, Actor player)
	{
		for (var i = 0; i < Members.Count(); i += 1)
		{
			var actor = Members.Get(i).Actor;

			if (actor.IsMoving())
				continue;

			int distance = Distance(actor, player);

			if (distance >= CatchUpDistance)
			{
				var place = FreeTileNearFigures(world, player.TileX(), player.TileY() + 1, actor);

				actor.PlaceAt(place.X, place.Y);
			}
			else if (distance > 1 + i / 2)
				StepTowardsFree(world, actor, player);
		}
	}

	/// The fight is over: who fell gets up again with a few hit points.
	void Recover()
	{
		for (var i = 0; i < Members.Count(); i += 1)
		{
			var member = Members.Get(i);

			if (member.Hp <= 0)
			{
				member.Hp = Max(1, member.Info.Hp / 4);
				member.Actor.SetVisible(true);
				Members.Set(i, member);
			}
		}
	}

	/// Health bars above the companions (green).
	void Draw(DrawList list, int cameraX, int cameraY)
	{
		foreach (var member in Members)
		{
			if (member.Hp <= 0 || member.Hp >= member.Info.Hp)
				continue;

			int x = member.Actor.PixelX() - cameraX;
			int y = member.Actor.PixelY() - cameraY - 4;
			int width = 14;

			list.Add(RectItem(DrawPlane.Panels, 0, x, y, width + 2, 3, Color.Of(20, 20, 20)));
			list.Add(RectItem(DrawPlane.Panels, 1, x + 1, y + 1, Max(1, member.Hp * width / Max(1, member.Info.Hp)), 1, Color.Of(80, 200, 90)));
		}
	}
}

/// True if a visible figure other than the mover stands on the tile or is stepping onto it (companions do not block the
/// hero, but they do not stand on top of each other or of anyone else).
bool FigureAt(GameWorld world, int x, int y, Actor mover)
{
	foreach (var actor in world.Actors)
	{
		if (!actor.Same(mover) && actor.Visible() && actor.TileX() == x && actor.TileY() == y)
			return true;
	}

	return false;
}

/// A step towards the target that does not end on another figure (else no step).
void StepTowardsFree(GameWorld world, Actor mover, Actor target)
{
	int dx = target.TileX() - mover.TileX();
	int dy = target.TileY() - mover.TileY();
	var horizontal = dx < 0 ? Direction.Left : Direction.Right;
	var vertical = dy < 0 ? Direction.Up : Direction.Down;
	bool horizontalFirst = Abs(dx) >= Abs(dy);
	var first = horizontalFirst ? horizontal : vertical;
	var second = horizontalFirst ? vertical : horizontal;
	int secondDelta = horizontalFirst ? dy : dx;

	if (!FigureAt(world, mover.TileX() + DeltaX(first), mover.TileY() + DeltaY(first), mover) && world.TryStep(mover, first))
		return;

	if (secondDelta != 0 && !FigureAt(world, mover.TileX() + DeltaX(second), mover.TileY() + DeltaY(second), mover))
		world.TryStep(mover, second);
}

/// A free tile near the position on which no figure stands.
TilePosition FreeTileNearFigures(GameWorld world, int x, int y, Actor mover)
{
	for (var radius = 0; radius < 8; radius += 1)
	{
		for (var dy = -radius; dy <= radius; dy += 1)
		{
			for (var dx = -radius; dx <= radius; dx += 1)
			{
				if (Max(Abs(dx), Abs(dy)) == radius && world.CanEnter(mover, x + dx, y + dy) && !FigureAt(world, x + dx, y + dy, mover))
					return TilePosition { X = x + dx, Y = y + dy };
			}
		}
	}

	return TilePosition { X = x, Y = y };
}
