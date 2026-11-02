namespace Amber.Conformance;

using System;
using Amber.Base;

/// One line "at <tick> <command> <arguments>" of a scenario.
struct ScenarioStep
{
	int Tick;
	string Command;
	string[] Arguments;
	int Line;

	/// C#: ToString().
	string Text()
	{
		return TrimEnd(Command + " " + string.Join(" ", Arguments));
	}

	/// The argument at the index, or null (C#: ElementAtOrDefault).
	string Argument(int index)
	{
		return index < Arguments.Length ? Arguments[index] : null;
	}
}

/// A golden trace scenario (spec section 12.3): the scripts, the initial state and the events at logical ticks.
///
///     seed 12345                     # start value of the random generator
///     script keller.ams              # script file or directory (relative to the scenario), may be repeated
///     pack game.pack                 # or: a cooked pack instead of scripts (needs the SYMBOLS chunk for symbol names)
///     load map spannenberg_keller    # the map the party is on
///     at 0   fire enter_tile x=3 y=4 # trigger with parameters (x y ox oy entity param arg screen node)
///     at 10  answer say              # host answer: resume the thread waiting for this action (default result 0)
///     at 30  battle_result 1         # short for "answer battle 1"
///     at 40  expect flag schrein_benutzt 1
///     at 40  hash                    # write the state hash into the trace
///     at 41  open info 5             # load a screen (the values are its variables 0..) and trigger screen_open
///     at 42  run info 3 7            # run local group 3 of an open screen with the value 7 as trigger argument
///     at 43  close info              # trigger screen_close and unload the screen
///     at 44  expect flag info.gesehen  # a slot of an open screen: screen.name
///     end 50                         # last tick (default: the tick of the last step)
///
/// Comments start with #. Errors in the file are Scenario errors.
struct Scenario
{
	uint32 Seed;
	string[] Scripts;
	/// The map the party is on, or null.
	string MapName;
	/// A cooked pack to run instead of the scripts (directive "pack"), or null.
	string PackPath;
	int EndTick;
	ScenarioStep[] Steps;
	string Name;

	static Error<Scenario> Load(string path)
	{
		string text = try ReadScenarioText(path);
		string directory = Path.GetDirectory(path);

		if (directory.Length == 0)
			directory = ".";

		return Parse(text, directory, Path.GetFileName(path));
	}

	static Error<Scenario> Parse(string text, string baseDirectory, string name)
	{
		uint32 seed = 1;
		string map = null;
		string pack = null;
		bool hasEnd = false;
		int end = 0;
		var scripts = List<string>.Create();
		var steps = List<ScenarioStep>.Create();
		var lines = text.Split('\n');

		for (var i = 0; i < lines.Length; i += 1)
		{
			string line = lines[i].ToString();
			int comment = line.IndexOf('#');

			if (comment >= 0)
				line = line.Substring(0, comment);

			var parts = SplitWhitespace(line);

			if (parts.Length == 0)
				continue;

			int number = i + 1;

			switch (parts[0])
			{
				case "seed":
					seed = (uint32)try Number(parts, 1, name, number);
					break;
				case "script":
					scripts.Add(Path.Normalize(Path.Combine(baseDirectory, try Argument(parts, 1, name, number))));
					break;
				case "pack":
					pack = Path.Normalize(Path.Combine(baseDirectory, try Argument(parts, 1, name, number)));
					break;
				case "end":
					end = (int)try Number(parts, 1, name, number);
					hasEnd = true;
					break;
				case "at":
				{
					int tick = (int)try Number(parts, 1, name, number);
					string command = try Argument(parts, 2, name, number);
					var arguments = new string[parts.Length - 3];

					for (var a = 3; a < parts.Length; a += 1)
						arguments[a - 3] = parts[a];

					steps.Add(ScenarioStep { Tick = tick, Command = command, Arguments = arguments, Line = number });
					break;
				}
				default:
				{
					if (parts[0] == "load" && parts.Length == 3 && parts[1] == "map")
					{
						map = parts[2];
						break;
					}

					return error(name + "(" + number + "): unknown line '" + line.Trim() + "'.", (int)ErrorKind.Scenario);
				}
			}
		}

		for (var i = 1; i < steps.Count(); i += 1)
		{
			if (steps.Get(i).Tick < steps.Get(i - 1).Tick)
				return error(name + "(" + steps.Get(i).Line + "): the ticks must not go backwards.", (int)ErrorKind.Scenario);
		}

		if (!hasEnd)
			end = steps.Count() > 0 ? steps.Get(steps.Count() - 1).Tick : 0;

		return Scenario { Name = name, Seed = seed, Scripts = ArrayOf(scripts), MapName = map, PackPath = pack, EndTick = end, Steps = ArrayOf(steps) };
	}

	static Error<string> Argument(string[] parts, int index, string name, int line)
	{
		if (index < parts.Length)
			return parts[index];

		return error(name + "(" + line + "): '" + parts[0] + "' needs more arguments.", (int)ErrorKind.Scenario);
	}

	static Error<int64> Number(string[] parts, int index, string name, int line)
	{
		string text = try Argument(parts, index, name, line);

		if (TryParseLong(text) is int64 value)
		{
			if (value >= 0)
				return value;
		}

		return error(name + "(" + line + "): '" + text + "' is not a number.", (int)ErrorKind.Scenario);
	}
}

Error<string> ReadScenarioText(string path)
{
	var text = File.ReadAllText(path);

	if (text is string content)
		return content;

	return error("cannot read '" + path + "': " + text.Message, (int)ErrorKind.Io);
}
