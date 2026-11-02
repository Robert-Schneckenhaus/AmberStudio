// Small game types: directions, the game clock, counted item stacks, the party and the chests. The mutable ones are
// handles (C#: classes): their state is in a one element array, so every copy sees the same state.

namespace Amber.Player.Game;

using System;
using Amber.Base;
using Amber.Player.Content;

/// The four directions. The values are the wire values of the script language (up, right, down, left).
enum Direction : int32
{
	Up = 0,
	Right = 1,
	Down = 2,
	Left = 3
}

int DeltaX(Direction direction)
{
	return direction == Direction.Right ? 1 : direction == Direction.Left ? -1 : 0;
}

int DeltaY(Direction direction)
{
	return direction == Direction.Up ? -1 : direction == Direction.Down ? 1 : 0;
}

Direction Opposite(Direction direction)
{
	return (Direction)(((int)direction + 2) % 4);
}

/// C#: Math.Clamp.
int Clamp(int value, int min, int max)
{
	return value < min ? min : value > max ? max : value;
}

int Max(int a, int b)
{
	return a > b ? a : b;
}

int Min(int a, int b)
{
	return a < b ? a : b;
}

int Abs(int value)
{
	return value < 0 ? -value : value;
}

/// "mira" -> "Mira" (C#: char.ToUpperInvariant(name[0]) + name[1..]).
string Capitalized(string name)
{
	if (name.Length == 0)
		return name;

	return name.Substring(0, 1).ToUpper() + name.Substring(1);
}

struct ClockState
{
	int Day;
	int MinuteOfDay;
	int TickInMinute;
}

/// Game time. One game minute is 100 ticks (spec: DurationValue.TicksPerGameMinute), so a game day lasts 48 real minutes.
/// The hour events of the C# class are the return values of Tick and AddMinute: the session fires the hour trigger.
struct GameClock
{
	ClockState[] _s;

	static GameClock Create(int hour, int minute)
	{
		var state = new ClockState[1];

		state[0].Day = 1;
		state[0].MinuteOfDay = hour * 60 + minute;

		return GameClock { _s = state };
	}

	int Day()
	{
		return _s[0].Day;
	}

	int MinuteOfDay()
	{
		return _s[0].MinuteOfDay;
	}

	int Hour()
	{
		return _s[0].MinuteOfDay / 60;
	}

	int Minute()
	{
		return _s[0].MinuteOfDay % 60;
	}

	int TickInMinute()
	{
		return _s[0].TickInMinute;
	}

	string Text()
	{
		return ZeroPad(Hour(), 2) + ":" + ZeroPad(Minute(), 2);
	}

	/// Sets the time of a savegame. No hour events are raised: the time is restored, not advanced.
	void Restore(int day, int minuteOfDay, int tick)
	{
		_s[0].Day = day;
		_s[0].MinuteOfDay = Clamp(minuteOfDay, 0, 24 * 60 - 1);
		_s[0].TickInMinute = Clamp(tick, 0, 99);
	}

	/// One tick; true if a minute ended (then AddMinute has to be called).
	bool Tick()
	{
		_s[0].TickInMinute += 1;

		if (_s[0].TickInMinute >= 100)
		{
			_s[0].TickInMinute = 0;

			return true;
		}

		return false;
	}

	/// Advances one minute. Returns the hour which starts with it, or -1.
	int AddMinute()
	{
		_s[0].MinuteOfDay += 1;

		if (_s[0].MinuteOfDay >= 24 * 60)
		{
			_s[0].MinuteOfDay = 0;
			_s[0].Day += 1;
		}

		return _s[0].MinuteOfDay % 60 == 0 ? Hour() : -1;
	}
}

/// Item stacks by item ID, iterated in the order of the IDs (C#: SortedDictionary<int, int>). Copies share the stacks.
struct SortedCounts
{
	List<int> _keys;
	Dictionary<int, int> _counts;

	static SortedCounts Create()
	{
		return SortedCounts { _keys = List<int>.Create(), _counts = Dictionary<int, int>.Create() };
	}

	int Count()
	{
		return _keys.Count();
	}

	/// The IDs in ascending order.
	int[] Keys()
	{
		return ArrayOf(_keys);
	}

	int Get(int key)
	{
		return _counts.GetOrDefault(key, 0);
	}

	void Set(int key, int count)
	{
		if (!_counts.ContainsKey(key))
		{
			int index = 0;

			while (index < _keys.Count() && _keys.Get(index) < key)
				index += 1;

			_keys.Insert(index, key);
		}

		_counts.Set(key, count);
	}

	void Remove(int key)
	{
		if (!_counts.ContainsKey(key))
			return;

		_counts.Remove(key);
		_keys.RemoveAt(_keys.IndexOf(key));
	}

	void Clear()
	{
		_keys.Clear();
		_counts.Clear();
	}
}

struct PartyValues
{
	int Gold;
	int Hp;
	int64 Version;
}

/// What the player carries (gold, items, the words they know) and the values of the hero in battle.
struct Party
{
	PartyValues[] _s;
	SortedCounts _items;
	Dictionary<int, bool> _words;
	List<int> _wordOrder;
	int MaxHp;
	int Attack;
	int Defense;

	static Party Create(HeroInfo hero)
	{
		var state = new PartyValues[1];

		state[0].Hp = hero.Hp;

		return Party
		{
			_s = state, _items = SortedCounts.Create(), _words = Dictionary<int, bool>.Create(), _wordOrder = List<int>.Create(), MaxHp = hero.Hp,
			Attack = hero.Attack, Defense = hero.Defense
		};
	}

	/// Attack and defense of the hero with the items of the pack: every item type adds its bonus once (there is no equip
	/// screen; carrying the sword or the shield is enough).
	int AttackWith(GameContent content)
	{
		int total = Attack;

		foreach (var id in _items.Keys())
			total += content.Items.GetOrDefault(id, new ItemInfo()).Attack;

		return total;
	}

	int DefenseWith(GameContent content)
	{
		int total = Defense;

		foreach (var id in _items.Keys())
			total += content.Items.GetOrDefault(id, new ItemInfo()).Defense;

		return total;
	}

	int Hp()
	{
		return _s[0].Hp;
	}

	void SetHp(int value)
	{
		_s[0].Hp = Clamp(value, 0, MaxHp);
		_s[0].Version += 1;
	}

	int Gold()
	{
		return _s[0].Gold;
	}

	void SetGold(int value)
	{
		_s[0].Gold = value;
		_s[0].Version += 1;
	}

	/// Counts every change of gold, items and words (dirty marking of the widgets which show them).
	int64 Version()
	{
		return _s[0].Version;
	}

	/// The carried items (ID to count) in the order of the IDs.
	SortedCounts Items()
	{
		return _items;
	}

	List<int> KnownWords()
	{
		return _wordOrder;
	}

	int Count(int item)
	{
		return _items.Get(item);
	}

	void AddItem(int item, int count)
	{
		_items.Set(item, Count(item) + count);
		_s[0].Version += 1;
	}

	void RemoveItem(int item, int count)
	{
		int left = Count(item) - count;

		if (left > 0)
			_items.Set(item, left);
		else
			_items.Remove(item);

		_s[0].Version += 1;
	}

	/// Replaces gold, items and words (loading a savegame).
	void Restore(int gold, int hp, List<IntPair2> carried, List<int> knownWords)
	{
		_s[0].Gold = gold;
		_s[0].Hp = Clamp(hp, 0, MaxHp);
		_items.Clear();
		_words.Clear();
		_wordOrder.Clear();

		foreach (var pair in carried)
			_items.Set(pair.Key, pair.Value);

		foreach (var word in knownWords)
			Learn(word);

		_s[0].Version += 1;
	}

	bool Knows(int word)
	{
		return _words.ContainsKey(word);
	}

	/// Returns true if the word was new.
	bool Learn(int word)
	{
		if (_words.ContainsKey(word))
			return false;

		_words.Set(word, true);
		_wordOrder.Add(word);
		_s[0].Version += 1;

		return true;
	}
}

/// A key with a value (C#: KeyValuePair<int, int>).
struct IntPair2
{
	int Key;
	int Value;
}

struct ChestValues
{
	int Gold;
	int64 Version;
}

/// The content of a chest: items and gold. The chest screen moves them to the party and back.
struct Chest
{
	ChestValues[] _s;
	SortedCounts _items;

	static Chest Create(int gold, List<IntPair2> content)
	{
		var state = new ChestValues[1];
		var items = SortedCounts.Create();

		state[0].Gold = gold;

		foreach (var pair in content)
			items.Set(pair.Key, pair.Value);

		return Chest { _s = state, _items = items };
	}

	int Gold()
	{
		return _s[0].Gold;
	}

	void SetGold(int value)
	{
		_s[0].Gold = value;
		_s[0].Version += 1;
	}

	/// Counts every change (dirty marking of the widgets which show the chest).
	int64 Version()
	{
		return _s[0].Version;
	}

	SortedCounts Items()
	{
		return _items;
	}

	bool IsEmpty()
	{
		return _items.Count() == 0 && _s[0].Gold == 0;
	}

	int Count(int item)
	{
		return _items.Get(item);
	}

	void Add(int item, int count)
	{
		_items.Set(item, Count(item) + count);
		_s[0].Version += 1;
	}

	void Remove(int item, int count)
	{
		int left = Count(item) - count;

		if (left > 0)
			_items.Set(item, left);
		else
			_items.Remove(item);

		_s[0].Version += 1;
	}
}
