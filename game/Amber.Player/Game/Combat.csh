// The fights: in real time on the map, not turn based. The battle action puts
// the monsters of a group on the map near the hero; a click on a monster (or T for the nearest) makes it the target, the
// hero walks up to it and strikes in the rhythm of the weapon's attack speed. The monsters walk up to the hero and strike
// in their own rhythm. H uses a healing item. The fight ends when all monsters are down (result 0), when the hero gets far
// away from them (1, fled) or when the hero falls (2, lost); the thread of the battle action waits until then. The dice are
// the ones of the interpreter (xorshift32), so a run with an input script is always the same.

namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Content;
using Amber.Player.Graphics;

const int BattleWon = 0;
const int BattleFled = 1;
const int BattleLost = 2;

/// Ticks between two blows without a weapon of its own (the item field speed, 50 ticks = 1 second).
const int DefaultAttackTicks = 40;
const int DefaultMonsterAttackTicks = 60;
/// The fight is fled when the hero is this many tiles away from every monster ...
const int FleeDistance = 9;
/// ... for this many ticks.
const int FleeTicks = 100;
/// How long a damage number rises above a figure.
const int PopupTicks = 40;

/// A monster on the map.
struct Foe
{
	Actor Actor;
	MonsterInfo Info;
	int Hp;
	int Cooldown;
}

/// A number or a word that rises above a figure for a moment (damage, healing).
struct Popup
{
	string Text;
	TextColor Color;
	int TileX;
	int TileY;
	int Age;
}

struct CombatValues
{
	bool Active;
	/// The index of the target in Foes, or -1.
	int Target;
	int HeroCooldown;
	int FarTicks;
	/// Counts the monsters ever placed (their actor IDs, below the ones of the map's entities).
	int Spawned;
	/// Ticks left of the healer's shield on the hero and the defense it gives.
	int Shield;
	int ShieldPower;
}

/// The fight on the current map. A handle; part of the session.
struct Combat
{
	CombatValues[] _s;
	List<Foe> Foes;
	List<int> WaitingThreads;
	List<Popup> Popups;

	static Combat Create()
	{
		var state = new CombatValues[1];

		state[0].Target = -1;

		return Combat { _s = state, Foes = List<Foe>.Create(), WaitingThreads = List<int>.Create(), Popups = List<Popup>.Create() };
	}

	bool Active()
	{
		return _s[0].Active;
	}

	/// The battle action: the monsters of the group appear around the hero; the thread waits for the end of the fight. A
	/// second battle while one runs adds its monsters to it.
	void Start(GameSession session, MonsterGroupInfo group, int waitingThread)
	{
		var world = session.World();
		var player = world.Player;

		foreach (var monster in group.Monsters)
		{
			_s[0].Spawned += 1;

			var actor = Actor.Create(monster.Key, -1000 - _s[0].Spawned, DummyActorArt(MonsterColor(monster.Key), Color.Of(30, 30, 30)));
			var place = FreeTileNear(world, player.TileX(), player.TileY() - 3, actor);

			actor.PlaceAt(place.X, place.Y);
			world.Actors.Add(actor);
			Foes.Add(Foe { Actor = actor, Info = monster, Hp = monster.Hp, Cooldown = DefaultMonsterAttackTicks / 2 });
		}

		if (waitingThread >= 0)
			WaitingThreads.Add(waitingThread);

		_s[0].Active = true;
		_s[0].FarTicks = 0;
	}

	/// Makes the monster under the point of the map (in pixels) the target: a click anywhere on its figure. False if there
	/// is none.
	bool TargetAt(int x, int y)
	{
		for (var i = 0; i < Foes.Count(); i += 1)
		{
			var foe = Foes.Get(i);
			var art = foe.Actor.Art();
			int left = foe.Actor.PixelX();
			int top = foe.Actor.PixelY();

			if (foe.Hp > 0 && x >= left && y >= top && x < left + art.Width && y < top + art.Height)
			{
				_s[0].Target = i;

				return true;
			}
		}

		return false;
	}

	/// The nearest monster becomes the target (T).
	void TargetNearest(Actor player)
	{
		int best = -1;
		int bestDistance = 0x7FFFFFFF;

		for (var i = 0; i < Foes.Count(); i += 1)
		{
			var foe = Foes.Get(i);
			int distance = Distance(player, foe.Actor);

			if (foe.Hp > 0 && distance < bestDistance)
			{
				best = i;
				bestDistance = distance;
			}
		}

		_s[0].Target = best;
	}

	/// The hero uses the first item that heals (H). False if there is none.
	bool UseHealingItem(GameSession session)
	{
		var party = session.Party;

		foreach (var item in session.Content.Items.Values())
		{
			if (item.Heal > 0 && party.Count(item.Id) > 0)
			{
				int before = party.Hp();

				party.RemoveItem(item.Id, 1);
				party.SetHp(party.Hp() + item.Heal);
				AddPopup("+" + (party.Hp() - before), TextColor.Green, session.World().Player);

				return true;
			}
		}

		return false;
	}

	/// One tick of the fight (the world ticks after the input: a step the player started with the keys comes first).
	void Tick(GameSession session)
	{
		AgePopups();

		if (!_s[0].Active)
			return;

		var world = session.World();
		var player = world.Player;
		var party = session.Party;

		// the hero: walk up to the target, then strike in the rhythm of the weapon
		_s[0].HeroCooldown = Max(0, _s[0].HeroCooldown - 1);

		if (_s[0].Target >= 0 && Foes.Get(_s[0].Target).Hp <= 0)
			_s[0].Target = -1;

		if (_s[0].Target >= 0)
		{
			var target = Foes.Get(_s[0].Target);

			if (Distance(player, target.Actor) <= 1 && !player.IsMoving() && !target.Actor.IsMoving())
			{
				player.SetFacing(DirectionTo(player, target.Actor));

				if (_s[0].HeroCooldown == 0)
				{
					int damage = Max(1, party.AttackWith(session.Content) - target.Info.Defense + Roll(session, 3));

					target.Hp -= damage;
					Foes.Set(_s[0].Target, target);
					AddPopup("" + damage, TextColor.White, target.Actor);
					_s[0].HeroCooldown = HeroAttackTicks(session);

					// a fallen target: the hero goes on with the nearest monster
					if (target.Hp <= 0)
					{
						Fall(world, _s[0].Target);
						TargetNearest(player);
					}
				}
			}
			else if (!player.IsMoving())
				StepTowards(world, player, target.Actor);
		}

		_s[0].Shield = Max(0, _s[0].Shield - 1);

		// the companions act by their role
		var squad = session.Squad;

		for (var i = 0; i < squad.Members.Count(); i += 1)
			ActCompanion(session, squad, i);

		// the monsters: walk up to the nearest of the party and strike in their own rhythm
		for (var i = 0; i < Foes.Count(); i += 1)
		{
			var foe = Foes.Get(i);

			if (foe.Hp <= 0)
				continue;

			foe.Cooldown = Max(0, foe.Cooldown - 1);

			int victim = NearestOfParty(squad, player, foe.Actor);
			var victimActor = victim < 0 ? player : squad.Members.Get(victim).Actor;

			if (Distance(foe.Actor, victimActor) <= 1 && !foe.Actor.IsMoving())
			{
				foe.Actor.SetFacing(DirectionTo(foe.Actor, victimActor));

				if (foe.Cooldown == 0 && party.Hp() > 0)
				{
					if (victim < 0)
					{
						int defense = party.DefenseWith(session.Content) + (_s[0].Shield > 0 ? _s[0].ShieldPower : 0);
						int damage = Max(1, foe.Info.Attack - defense + Roll(session, 2));

						party.SetHp(party.Hp() - damage);
						AddPopup("-" + damage, TextColor.Red, player);
					}
					else
					{
						var member = squad.Members.Get(victim);
						int damage = Max(1, foe.Info.Attack - member.Defense(session.Content) + Roll(session, 2));

						member.Hp = Max(0, member.Hp - damage);
						AddPopup("-" + damage, TextColor.Red, member.Actor);

						// a fallen companion is out of the fight until it ends
						if (member.Hp == 0)
							member.Actor.SetVisible(false);

						squad.Members.Set(victim, member);
					}

					foe.Cooldown = DefaultMonsterAttackTicks;
				}
			}
			else if (!foe.Actor.IsMoving() && Distance(foe.Actor, victimActor) < FleeDistance)
				StepTowards(world, foe.Actor, victimActor);

			Foes.Set(i, foe);
		}

		// the end
		if (party.Hp() <= 0)
		{
			End(session, BattleLost);

			return;
		}

		if (Living() == 0)
		{
			End(session, BattleWon);

			return;
		}

		_s[0].FarTicks = NearestDistance(player) >= FleeDistance ? _s[0].FarTicks + 1 : 0;

		if (_s[0].FarTicks >= FleeTicks)
			End(session, BattleFled);
	}

	/// The party leaves the map: the fight counts as fled.
	void Abort(GameSession session)
	{
		if (_s[0].Active)
			End(session, BattleFled);
	}

	void End(GameSession session, int outcome)
	{
		var world = session.World();

		foreach (var foe in Foes)
			world.Remove(foe.Actor);

		Foes.Clear();
		_s[0].Active = false;
		_s[0].Target = -1;
		_s[0].Shield = 0;
		session.Squad.Recover();

		var threads = WaitingThreads.ToArray();

		WaitingThreads.Clear();

		foreach (var thread in threads)
			session.Resume(thread, outcome);
	}

	/// The health bars of the monsters, the target mark and the rising numbers (world plane, above the figures).
	void Draw(DrawList list, int cameraX, int cameraY)
	{
		for (var i = 0; i < Foes.Count(); i += 1)
		{
			var foe = Foes.Get(i);

			if (foe.Hp <= 0)
				continue;

			int x = foe.Actor.PixelX() - cameraX;
			int y = foe.Actor.PixelY() - cameraY - 4;
			int width = 14;
			int filled = Max(1, foe.Hp * width / Max(1, foe.Info.Hp));

			list.Add(RectItem(DrawPlane.Panels, 0, x, y, width + 2, 3, Color.Of(20, 20, 20)));
			list.Add(RectItem(DrawPlane.Panels, 1, x + 1, y + 1, filled, 1, i == _s[0].Target ? Color.Of(250, 210, 60) : Color.Of(200, 50, 40)));
		}

		foreach (var popup in Popups)
		{
			int x = popup.TileX * TileSize - cameraX + 2;
			int y = popup.TileY * TileSize - cameraY - 12 - popup.Age / 3;

			list.Add(TextItem(5, popup.Text, x, y, popup.Color));
		}
	}

	/// One tick of a companion: heal, shield, shoot or cast by its role, or walk to where it can.
	void ActCompanion(GameSession session, Squad squad, int index)
	{
		var member = squad.Members.Get(index);

		if (member.Hp <= 0)
			return;

		var world = session.World();
		var player = world.Player;
		var party = session.Party;

		member.Cooldown = Max(0, member.Cooldown - 1);

		if (member.Info.Role == "healer")
		{
			// who is hurt most (in percent) below the limit: the hero (-1) or a companion
			int patient = -2;
			int lowest = HealBelowPercent;

			if (party.Hp() * 100 / Max(1, party.MaxHp) < lowest)
			{
				patient = -1;
				lowest = party.Hp() * 100 / Max(1, party.MaxHp);
			}

			for (var i = 0; i < squad.Members.Count(); i += 1)
			{
				var other = squad.Members.Get(i);
				int percent = other.Hp * 100 / Max(1, other.Info.Hp);

				if (other.Hp > 0 && percent < lowest)
				{
					patient = i;
					lowest = percent;
				}
			}

			var patientActor = patient == -1 ? player : patient >= 0 ? squad.Members.Get(patient).Actor : player;

			if (patient != -2 && Distance(member.Actor, patientActor) > member.Info.Range)
			{
				if (!member.Actor.IsMoving())
					StepTowardsFree(world, member.Actor, patientActor);
			}
			else if (member.Cooldown == 0 && patient == -1)
			{
				int before = party.Hp();

				party.SetHp(party.Hp() + HealOf(session, member));
				AddPopup("+" + (party.Hp() - before), TextColor.Green, player);
				member.Cooldown = member.Info.Speed;
			}
			else if (member.Cooldown == 0 && patient >= 0)
			{
				var other = squad.Members.Get(patient);
				int before = other.Hp;

				other.Hp = Min(other.Info.Hp, other.Hp + HealOf(session, member));
				AddPopup("+" + (other.Hp - before), TextColor.Green, other.Actor);
				member.Cooldown = member.Info.Speed;

				if (patient == index)
					member.Hp = other.Hp;
				else
					squad.Members.Set(patient, other);
			}
			else if (member.Cooldown == 0 && _s[0].Shield == 0 && member.BestPower(session.Content, "shield") > 0 && Distance(member.Actor, player) <= member.Info.Range)
			{
				_s[0].Shield = ShieldTicks;
				_s[0].ShieldPower = member.BestPower(session.Content, "shield");
				AddPopup("shield", TextColor.Cyan, player);
				member.Cooldown = member.Info.Speed;
			}
			else if (!member.Actor.IsMoving() && Distance(member.Actor, player) > 2)
				StepTowardsFree(world, member.Actor, player);

			squad.Members.Set(index, member);

			return;
		}

		// ranger and mage: a target in range, else walk up to the nearest monster
		int target = member.Info.Role == "mage" ? CrowdedFoe(member.Actor, member.Info.Range) : WeakestFoe(member.Actor, member.Info.Range);

		if (target < 0)
		{
			int nearest = NearestFoe(member.Actor);

			if (nearest >= 0 && !member.Actor.IsMoving())
				StepTowardsFree(world, member.Actor, Foes.Get(nearest).Actor);

			squad.Members.Set(index, member);

			return;
		}

		if (member.Cooldown == 0 && !member.Actor.IsMoving())
		{
			member.Actor.SetFacing(DirectionTo(member.Actor, Foes.Get(target).Actor));
			var content = session.Content;
			int attack = member.Attack(content) + Max(0, member.BestPower(content, "bolt"));
			int blast = member.BestPower(content, "blast");
			var centre = Foes.Get(target).Actor;

			Hit(session, target, attack, TextColor.Yellow);

			// a blast spell also hits the monsters next to the target, with half the force
			if (member.Info.Role == "mage" && blast >= 0)
			{
				for (var i = 0; i < Foes.Count(); i += 1)
				{
					if (i != target && Foes.Get(i).Hp > 0 && Distance(Foes.Get(i).Actor, centre) <= 1)
						Hit(session, i, Max(1, (attack + blast) / 2), TextColor.Yellow);
				}
			}

			member.Cooldown = member.Info.Speed;
		}

		squad.Members.Set(index, member);
	}

	/// A blow of a companion against a monster.
	void Hit(GameSession session, int index, int attack, TextColor color)
	{
		var foe = Foes.Get(index);
		int damage = Max(1, attack - foe.Info.Defense + Roll(session, 2));

		foe.Hp -= damage;
		Foes.Set(index, foe);
		AddPopup("" + damage, color, foe.Actor);

		if (foe.Hp <= 0)
		{
			bool wasTarget = _s[0].Target == index;

			Fall(session.World(), index);

			if (wasTarget)
				TargetNearest(session.World().Player);
		}
	}

	/// The living monster with the fewest hit points within the range, or -1 (the ranger finishes the weak).
	int WeakestFoe(Actor from, int range)
	{
		int best = -1;

		for (var i = 0; i < Foes.Count(); i += 1)
		{
			var foe = Foes.Get(i);

			if (foe.Hp > 0 && Distance(from, foe.Actor) <= range && (best < 0 || foe.Hp < Foes.Get(best).Hp))
				best = i;
		}

		return best;
	}

	/// The living monster within the range with the most monsters next to it (the mage's spell hits them too), or -1.
	int CrowdedFoe(Actor from, int range)
	{
		int best = -1;
		int bestNeighbours = -1;

		for (var i = 0; i < Foes.Count(); i += 1)
		{
			var foe = Foes.Get(i);

			if (foe.Hp <= 0 || Distance(from, foe.Actor) > range)
				continue;

			int neighbours = 0;

			foreach (var other in Foes)
			{
				if (other.Hp > 0 && !other.Actor.Same(foe.Actor) && Distance(other.Actor, foe.Actor) <= 1)
					neighbours += 1;
			}

			if (neighbours > bestNeighbours)
			{
				best = i;
				bestNeighbours = neighbours;
			}
		}

		return best;
	}

	int NearestFoe(Actor from)
	{
		int best = -1;

		for (var i = 0; i < Foes.Count(); i += 1)
		{
			if (Foes.Get(i).Hp > 0 && (best < 0 || Distance(from, Foes.Get(i).Actor) < Distance(from, Foes.Get(best).Actor)))
				best = i;
		}

		return best;
	}

	/// The member of the party a monster goes for: the nearest one; -1 for the hero, else the index of the companion.
	int NearestOfParty(Squad squad, Actor player, Actor from)
	{
		int best = -1;
		int bestDistance = Distance(from, player);

		for (var i = 0; i < squad.Members.Count(); i += 1)
		{
			var member = squad.Members.Get(i);

			if (member.Hp > 0 && Distance(from, member.Actor) < bestDistance)
			{
				best = i;
				bestDistance = Distance(from, member.Actor);
			}
		}

		return best;
	}

	int Living()
	{
		int count = 0;

		foreach (var foe in Foes)
		{
			if (foe.Hp > 0)
				count += 1;
		}

		return count;
	}

	int NearestDistance(Actor player)
	{
		int nearest = 0x7FFFFFFF;

		foreach (var foe in Foes)
		{
			if (foe.Hp > 0)
				nearest = Min(nearest, Distance(player, foe.Actor));
		}

		return nearest;
	}

	void Fall(GameWorld world, int index)
	{
		world.Remove(Foes.Get(index).Actor);

		if (_s[0].Target == index)
			_s[0].Target = -1;
	}

	void AddPopup(string text, TextColor color, Actor actor)
	{
		Popups.Add(Popup { Text = text, Color = color, TileX = actor.TileX(), TileY = actor.TileY(), Age = 0 });
	}

	void AgePopups()
	{
		for (var i = Popups.Count() - 1; i >= 0; i -= 1)
		{
			var popup = Popups.Get(i);

			popup.Age += 1;

			if (popup.Age >= PopupTicks)
				Popups.RemoveAt(i);
			else
				Popups.Set(i, popup);
		}
	}
}

/// Ticks between two blows of the hero: the fastest weapon carried (item field speed), else DefaultAttackTicks.
int HeroAttackTicks(GameSession session)
{
	int ticks = DefaultAttackTicks;

	foreach (var item in session.Content.Items.Values())
	{
		if (item.Speed > 0 && session.Party.Count(item.Id) > 0)
			ticks = Min(ticks, item.Speed);
	}

	return ticks;
}

int Roll(GameSession session, int sides)
{
	return (int)session.Interpreter().NextRandom16() % sides;
}

/// Tiles between two figures (diagonal neighbours count as 1).
int Distance(Actor a, Actor b)
{
	return Max(Abs(a.TileX() - b.TileX()), Abs(a.TileY() - b.TileY()));
}

Direction DirectionTo(Actor from, Actor to)
{
	int dx = to.TileX() - from.TileX();
	int dy = to.TileY() - from.TileY();

	if (Abs(dx) >= Abs(dy))
		return dx < 0 ? Direction.Left : Direction.Right;

	return dy < 0 ? Direction.Up : Direction.Down;
}

/// One step towards the other figure: along the longer axis, else the shorter one.
void StepTowards(GameWorld world, Actor mover, Actor target)
{
	int dx = target.TileX() - mover.TileX();
	int dy = target.TileY() - mover.TileY();
	var horizontal = dx < 0 ? Direction.Left : Direction.Right;
	var vertical = dy < 0 ? Direction.Up : Direction.Down;
	bool horizontalFirst = Abs(dx) >= Abs(dy);
	var first = horizontalFirst ? horizontal : vertical;
	var second = horizontalFirst ? vertical : horizontal;
	int secondDelta = horizontalFirst ? dy : dx;

	if (world.TryStep(mover, first))
		return;

	if (secondDelta != 0)
		world.TryStep(mover, second);
}

/// A tile of the map.
struct TilePosition
{
	int X;
	int Y;
}

/// A free tile near the position (the position itself if it is free), searched in rings around it.
TilePosition FreeTileNear(GameWorld world, int x, int y, Actor mover)
{
	for (var radius = 0; radius < 8; radius += 1)
	{
		for (var dy = -radius; dy <= radius; dy += 1)
		{
			for (var dx = -radius; dx <= radius; dx += 1)
			{
				if (Max(Abs(dx), Abs(dy)) != radius)
					continue;

				if (world.CanEnter(mover, x + dx, y + dy))
					return TilePosition { X = x + dx, Y = y + dy };
			}
		}
	}

	return TilePosition { X = x, Y = y };
}

/// The color of a monster's placeholder figure (from its name, so every kind looks the same).
Color MonsterColor(string key)
{
	int hash = 0;

	for (var i = 0; i < key.Length; i += 1)
		hash = (hash * 31 + (int)key[i]) & 0xFFFF;

	return Color.Of(120 + hash % 120, 40 + (hash / 7) % 60, 40 + (hash / 13) % 60);
}

/// The hit points a healer gives: its own plus the strongest heal spell it knows.
int HealOf(GameSession session, Companion healer)
{
	return healer.Info.Heal + Max(0, healer.BestPower(session.Content, "heal"));
}
