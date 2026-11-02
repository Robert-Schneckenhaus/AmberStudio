namespace Amber.Conformance;

using System;
using Amber.Base;
using Amber.Pack;
using Amber.Runtime;
using Amber.Script.Common;
using Amber.Script.Compilation;

const int ScenarioTicksPerHour = 6000;

/// The outcome of a scenario run: the trace lines and the expectations which did not hold.
struct ScenarioResult
{
	List<string> Trace;
	List<string> Failures;

	bool Passed()
	{
		return Failures.Count() == 0;
	}

	string TraceText()
	{
		return JoinList("\n", Trace) + "\n";
	}
}

/// The host of a scenario: the party has gold, items and words; blocking actions wait for an "answer" step. A handle: the
/// session and the interpreter see the same state.
struct ScenarioHost : IGameHost
{
	Dictionary<int, int> _items;
	HashSet<int> _words;
	/// The threads waiting for a blocking action (thread ID to action opcode).
	Dictionary<int, int> _waiting;
	Cell<Interpreter> _interpreter;
	Cell<int> MapId;
	Cell<int> Gold;

	static ScenarioHost Create()
	{
		return ScenarioHost
		{
			_items = Dictionary<int, int>.Create(),
			_words = HashSet<int>.Create(),
			_waiting = Dictionary<int, int>.Create(),
			_interpreter = Cell<Interpreter>.Of(new Interpreter()),
			MapId = Cell<int>.Of(-1),
			Gold = Cell<int>.Of(0)
		};
	}

	void SetInterpreter(Interpreter interpreter)
	{
		_interpreter.Set(interpreter);
	}

	int ItemCount(int item)
	{
		return _items.GetOrDefault(item, 0);
	}

	bool Knows(int word)
	{
		return _words.Contains(word);
	}

	int WaitingCount(int op)
	{
		int count = 0;

		foreach (var entry in _waiting.Entries())
		{
			if (entry.Value == op)
				count += 1;
		}

		return count;
	}

	/// Takes the lowest thread which waits for the action and returns its ID, or -1.
	int TakeWaiting(int op)
	{
		int lowest = -1;

		foreach (var entry in _waiting.Entries())
		{
			if (entry.Value == op && (lowest < 0 || entry.Key < lowest))
				lowest = entry.Key;
		}

		if (lowest >= 0)
			_waiting.Remove(lowest);

		return lowest;
	}

	ActionOutcome Execute(ActionOp op, uint16[] operands, const ref ThreadContext context)
	{
		switch (op)
		{
			case ActionOp.GiveGold:
				Gold.Set(Gold.Get() + (int)Wire.Combine(operands[0], operands[1]));
				return ActionOutcome.Done;
			case ActionOp.TakeGold:
				Gold.Set(Math.Max(0, Gold.Get() - (int)Wire.Combine(operands[0], operands[1])));
				return ActionOutcome.Done;
			case ActionOp.GiveItem:
				_items.Set((int)operands[0], ItemCount((int)operands[0]) + (int)operands[1]);
				return ActionOutcome.Done;
			case ActionOp.TakeItem:
				_items.Set((int)operands[0], Math.Max(0, ItemCount((int)operands[0]) - (int)operands[1]));
				return ActionOutcome.Done;
			case ActionOp.LearnWord:
				_words.Add((int)operands[0]);
				return ActionOutcome.Done;
			default:
				break;
		}

		if (ActionTable.ByOp((int)op) is OpInfo info)
		{
			if (info.Blocking)
			{
				_waiting.Set(context.ThreadId, (int)info.Op);

				return ActionOutcome.Blocked;
			}
		}

		return ActionOutcome.Done;
	}

	bool Evaluate(ConditionOp op, uint16[] operands, const ref ThreadContext context)
	{
		switch (op)
		{
			case ConditionOp.WordKnown:
				return _words.Contains((int)operands[0]);
			case ConditionOp.HasItem:
				return ItemCount((int)operands[0]) >= (int)operands[1];
			case ConditionOp.Gold:
				return Compare((int64)Gold.Get(), operands[0], (int64)(int)Wire.Combine(operands[1], operands[2]));
			case ConditionOp.PartySize:
				return Compare(1, operands[0], (int64)(int16)operands[1]);
			case ConditionOp.InMap:
				return (int)operands[0] == MapId.Get();
			case ConditionOp.HourIn:
			{
				int hour = (int)((9 + _interpreter.Get().Ticks() / ScenarioTicksPerHour) % 24);

				if (operands[0] <= operands[1])
					return hour >= (int)operands[0] && hour < (int)operands[1];

				return hour >= (int)operands[0] || hour < (int)operands[1];
			}
			default:
				return false;
		}
	}
}

/// The run of one scenario: executes the steps and writes the trace.
struct ScenarioSession
{
	Scenario Scenario;
	ScenarioProgram Program;
	Optional<ScenarioMap> Map;
	Interpreter Interpreter;
	ScenarioHost Host;
	List<string> Trace;
	Dictionary<string, LoadedChunk> OpenScreens;
	List<string> Failures;

	int MapIdOf()
	{
		if (Map is ScenarioMap map)
			return map.Id;

		return -1;
	}

	void Write(string line)
	{
		Trace.Add("tick=" + Interpreter.Ticks() + " " + line);
	}

	void Hash()
	{
		Write("hash crc32=0x" + Hex(Interpreter.StateHash(MapIdOf()), 8) + " gold=" + Host.Gold.Get());
	}

	Error<void> Execute(ScenarioStep step)
	{
		switch (step.Command)
		{
			case "fire":
				return Fire(step);
			case "answer":
			{
				string action = step.Argument(0);

				if (action == null)
					return Fail(step, "'answer' needs an action name");

				return Answer(step, action, step.Argument(1));
			}
			case "battle_result":
				return Answer(step, "battle", step.Argument(0));
			case "open":
				return OpenScreen(step);
			case "close":
				return CloseScreen(step);
			case "run":
				return RunScreenGroup(step);
			case "expect":
				return Expect(step);
			case "hash":
				Hash();
				return;
			default:
				return Fail(step, "unknown command '" + step.Command + "'");
		}
	}

	Error<void> Fire(ScenarioStep step)
	{
		string name = step.Argument(0);

		if (name == null)
			return Fail(step, "'fire' needs a trigger name");

		var found = TriggerTable.ByName(name);

		if (found == null)
			return Fail(step, "unknown trigger '" + name + "'");

		var info = new TriggerInfo();

		if (found is TriggerInfo trigger)
			info = trigger;

		var context = TriggerContext.Of(info.Type);
		var rest = List<string>.Create();

		context.MapId = MapIdOf();

		for (var i = 1; i < step.Arguments.Length; i += 1)
		{
			string pair = step.Arguments[i];
			int equals = pair.IndexOf('=');

			rest.Add(pair);

			if (equals <= 0)
				return Fail(step, "'" + pair + "' is not key=value");

			string key = pair.Substring(0, equals);
			string value = pair.Substring(equals + 1);

			switch (key)
			{
				case "x":
					context.X = (uint16)try Value(step, value);
					break;
				case "y":
					context.Y = (uint16)try Value(step, value);
					break;
				case "ox":
					context.OtherX = (uint16)try Value(step, value);
					break;
				case "oy":
					context.OtherY = (uint16)try Value(step, value);
					break;
				case "param":
					context.Param = (uint16)try Value(step, value);
					break;
				case "arg":
					context.Arg = (uint32)try Value(step, value);
					break;
				case "screen":
					context.ScreenId = (int)try Value(step, value);
					break;
				case "node":
					context.NodeId = (int)try Value(step, value);
					break;
				case "entity":
				{
					bool named = false;

					if (Map is ScenarioMap map)
					{
						if (map.Entities.TryGet(value) is int id)
						{
							context.EntityId = id;
							named = true;
						}
					}

					if (!named)
						context.EntityId = (int)try Value(step, value);

					break;
				}
				default:
					return Fail(step, "unknown trigger parameter '" + key + "'");
			}
		}

		Write(TrimEnd("fire " + info.Name + " " + JoinList(" ", rest)));

		int started = Interpreter.Trigger(ref Host, context);

		Write("fired " + info.Name + " threads=" + started);

		return;
	}

	Error<ScenarioScreen> ScreenNamed(ScenarioStep step, string name)
	{
		if (name != null)
		{
			if (Program.FindScreen(name) is ScenarioScreen screen)
				return screen;
		}

		return error(ErrorText(step, "the screen '" + name + "' does not exist"), (int)ErrorKind.Scenario);
	}

	Error<LoadedChunk> OpenScreenNamed(ScenarioStep step, string name)
	{
		if (name != null)
		{
			if (OpenScreens.TryGet(name) is LoadedChunk chunk)
				return chunk;
		}

		return error(ErrorText(step, "the screen '" + name + "' is not open"), (int)ErrorKind.Scenario);
	}

	/// open NAME [values]: loads the screen with its state, the values become the screen variables 0.. (the arguments of
	/// push_screen), then screen_open is triggered.
	Error<void> OpenScreen(ScenarioStep step)
	{
		string name = step.Argument(0);
		var screen = try ScreenNamed(step, name);

		if (OpenScreens.ContainsKey(screen.Name))
			return Fail(step, "the screen '" + screen.Name + "' is already open");

		var chunk = Interpreter.LoadScreen(screen.Id, screen.Script, screen.Sizes);
		var values = StringBuilder.Create();

		for (var i = 1; i < step.Arguments.Length; i += 1)
		{
			if (chunk.State.IsValidVar(i - 1))
				chunk.State.SetVar(i - 1, (int16)try Value(step, step.Arguments[i]));

			values.Append(" " + step.Arguments[i]);
		}

		OpenScreens.Set(screen.Name, chunk);
		Write("open screen " + screen.Name + values.ToString());

		var context = TriggerContext.Of(TriggerType.ScreenOpen);

		context.MapId = MapIdOf();
		context.ScreenId = screen.Id;

		int started = Interpreter.Trigger(ref Host, context);

		Write("opened screen " + screen.Name + " threads=" + started);

		return;
	}

	Error<void> CloseScreen(ScenarioStep step)
	{
		string name = step.Argument(0);
		var screen = try ScreenNamed(step, name);
		var chunk = try OpenScreenNamed(step, name);

		Write("close screen " + screen.Name);

		var context = TriggerContext.Of(TriggerType.ScreenClose);

		context.MapId = MapIdOf();
		context.ScreenId = screen.Id;

		int started = Interpreter.Trigger(ref Host, context);

		Interpreter.UnloadScreen(chunk);
		OpenScreens.Remove(screen.Name);
		Write("closed screen " + screen.Name + " threads=" + started);

		return;
	}

	/// run NAME INDEX [value]: runs a local group of an open screen directly (the handlers of a screen definition, RunGroup)
	/// with the value as trigger argument.
	Error<void> RunScreenGroup(ScenarioStep step)
	{
		string name = step.Argument(0);

		try ScreenNamed(step, name);

		var chunk = try OpenScreenNamed(step, name);
		string indexText = step.Argument(1);

		if (indexText == null)
			return Fail(step, "'run' needs a group index");

		int index = (int)try Value(step, indexText);
		int64 arg = 0;

		if (step.Arguments.Length > 2)
			arg = try Value(step, step.Arguments[2]);

		Write("run screen " + name + " group " + index + " arg=" + arg);

		bool started = Interpreter.RunGroup(ref Host, chunk, Wire.LocalGroup(index), (uint32)arg, MapIdOf());

		Write("ran screen " + name + " started=" + (started ? 1 : 0));

		return;
	}

	Error<void> Answer(ScenarioStep step, string action, string value)
	{
		var found = ActionTable.ByName(action);

		if (found == null)
			return Fail(step, "unknown action '" + action + "'");

		int op = 0;

		if (found is OpInfo info)
			op = (int)info.Op;

		int16 result = 0;

		if (value != null)
			result = (int16)try Value(step, value);

		int threadId = Host.TakeWaiting(op);

		Write("answer " + action + " " + result + " thread=" + threadId);

		if (threadId < 0)
			Failures.Add(Scenario.Name + "(" + step.Line + "): nobody is waiting for '" + action + "'");
		else
			Interpreter.Resume(ref Host, threadId, result);

		return;
	}

	Error<void> Expect(ScenarioStep step)
	{
		string what = step.Argument(0);

		if (what == null)
			return Fail(step, "'expect' needs a kind");

		string subject = step.Argument(1);

		if (subject == null)
			subject = "";

		string given = step.Argument(2);
		int expected;
		int actual;

		switch (what)
		{
			case "flag":
				expected = given == null ? 1 : (int)try Value(step, given);
				actual = try SlotState(step, SlotKind.Flag, subject) ? 1 : 0;
				break;
			case "var":
				if (given == null)
					return Fail(step, "'expect var' needs a value");

				expected = (int)try Value(step, given);
				actual = (int)try SlotValue(step, SlotKind.Var, subject);
				break;
			case "var32":
				if (given == null)
					return Fail(step, "'expect var32' needs a value");

				expected = (int)try Value(step, given);
				actual = (int)try SlotValue(step, SlotKind.Var32, subject);
				break;
			case "gold":
				expected = (int)try Value(step, subject);
				actual = Host.Gold.Get();
				given = null;
				break;
			case "item":
				if (given == null)
					return Fail(step, "'expect item' needs a count");

				expected = (int)try Value(step, given);
				actual = Host.ItemCount((int)try Value(step, subject));
				break;
			case "word":
				expected = given == null ? 1 : (int)try Value(step, given);
				actual = Host.Knows((int)try Value(step, subject)) ? 1 : 0;
				break;
			case "threads":
				expected = (int)try Value(step, subject);
				actual = Interpreter.ActiveThreadCount();
				given = null;
				break;
			case "waiting":
			{
				expected = given == null ? 1 : (int)try Value(step, given);

				var action = ActionTable.ByName(subject);

				if (action == null)
					return Fail(step, "unknown action '" + subject + "'");

				int op = 0;

				if (action is OpInfo info)
					op = (int)info.Op;

				actual = Host.WaitingCount(op);
				break;
			}
			default:
				return Fail(step, "unknown expectation '" + what + "'");
		}

		string text = TrimEnd(("expect " + what + " " + subject + (given == null ? "" : " " + given)).Replace("  ", " "));

		if (actual == expected)
		{
			Write(text + " ok");
		}
		else
		{
			Write(text + " FAILED (expected " + expected + ", actual " + actual + ")");
			Failures.Add(Scenario.Name + "(" + step.Line + "): " + text + ": expected " + expected + ", actual " + actual);
		}

		return;
	}

	Error<bool> SlotState(ScenarioStep step, SlotKind kind, string name)
	{
		var slot = try Slot(step, kind, name);

		return slot.Store.GetFlag(slot.Index);
	}

	Error<int64> SlotValue(ScenarioStep step, SlotKind kind, string name)
	{
		var slot = try Slot(step, kind, name);

		return kind == SlotKind.Var ? (int64)slot.Store.GetVar(slot.Index) : (int64)slot.Store.GetVar32(slot.Index);
	}

	Error<StoreSlot> Slot(ScenarioStep step, SlotKind kind, string name)
	{
		// "screen.name": a slot of an open screen
		int dot = name.IndexOf('.');
		string kindName = SlotKindName(kind);

		if (dot > 0)
		{
			string screenName = name.Substring(0, dot);
			var chunk = try OpenScreenNamed(step, screenName);

			if (Program.Layout.Find("Screen", screenName, kindName, name.Substring(dot + 1)) is LayoutSlot screenSlot)
				return StoreSlot { Store = chunk.State, Index = screenSlot.Index };

			return error(ErrorText(step, "unknown " + kindName.ToLower() + " '" + name + "'"), (int)ErrorKind.Scenario);
		}

		if (Map is ScenarioMap map)
		{
			if (Program.Layout.Find("Map", map.Name, kindName, name) is LayoutSlot local)
			{
				if (Interpreter.GetMap(map.Id) is LoadedChunk loaded)
					return StoreSlot { Store = loaded.State, Index = local.Index };
			}
		}

		if (Program.Layout.Find("Global", "global", kindName, name) is LayoutSlot global)
			return StoreSlot { Store = Interpreter.Global(), Index = global.Index };

		return error(ErrorText(step, "unknown " + kindName.ToLower() + " '" + name + "'"), (int)ErrorKind.Scenario);
	}

	/// A number or a table symbol like I.key (the ID of the program under test).
	Error<int64> Value(ScenarioStep step, string text)
	{
		if (TryParseLong(text) is int64 number)
			return number;

		int dot = text.IndexOf('.');

		if (dot > 0)
		{
			if (SymbolKinds.FromPrefix(text.Substring(0, dot)) is SymbolKind kind)
			{
				if (Program.Symbol(kind, text.Substring(dot + 1)) is int id)
					return (int64)id;
			}
		}

		return error(ErrorText(step, "'" + text + "' is not a number or a symbol"), (int)ErrorKind.Scenario);
	}

	string ErrorText(ScenarioStep step, string message)
	{
		return Scenario.Name + "(" + step.Line + "): " + message + ".";
	}

	Error<void> Fail(ScenarioStep step, string message)
	{
		return error(ErrorText(step, message), (int)ErrorKind.Scenario);
	}
}

/// A state store and an index in it (C#: the tuple (StateStore Store, int Index)).
struct StoreSlot
{
	StateStore Store;
	int Index;
}
