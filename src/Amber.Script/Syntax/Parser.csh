namespace Amber.Script.Syntax;

using System;
using Amber.Base;
using Amber.Script.Common;

/// The result of parsing a file: the program, or the syntax error (E100) that stopped the parser (C#: SyntaxException).
struct ParseResult
{
	Optional<ProgramNode> Program;
	Optional<Diagnostic> SyntaxError;
}

/// Recursive descent parser for the grammar of spec section 7.2. A syntax error (E100) stops the parser (the parse functions
/// return an error and Failure holds the diagnostic); recoverable problems (E008) are added to the diagnostic bag.
struct Parser
{
	List<Token> _tokens;
	DiagnosticBag _diagnostics;
	int _index;
	Diagnostic Failure;

	static ParseResult Parse(string source, string file, DiagnosticBag diagnostics)
	{
		var lexer = Lexer.Create(source, file);
		var tokens = lexer.Tokenize();

		if (tokens is List<Token> list)
		{
			var parser = Parser { _tokens = list, _diagnostics = diagnostics, _index = 0 };
			var program = parser.ParseProgram(file);

			if (program is ProgramNode node)
				return ParseResult { Program = node, SyntaxError = null };

			return ParseResult { Program = null, SyntaxError = parser.Failure };
		}

		return ParseResult { Program = null, SyntaxError = lexer.Failure };
	}

	Token Current()
	{
		return _tokens.Get(_index);
	}

	Token PeekToken(int offset)
	{
		return _tokens.Get(Math.Min(_index + offset, _tokens.Count() - 1));
	}

	Token Next()
	{
		var token = _tokens.Get(_index);

		if (token.Kind != TokenKind.EndOfFile)
			_index += 1;

		return token;
	}

	/// Records the syntax error (E100) and returns its message for error(...).
	string Fail(string message, Token token)
	{
		Failure = Diagnostic { Code = "E100", Severity = Severity.Error, Message = message, Location = token.Location };

		return message;
	}

	bool AcceptSymbol(string text)
	{
		if (!Current().IsSymbol(text))
			return false;

		_index += 1;

		return true;
	}

	bool AcceptKeyword(string text)
	{
		if (!Current().IsKeyword(text))
			return false;

		_index += 1;

		return true;
	}

	Error<void> ExpectSymbol(string text)
	{
		if (!AcceptSymbol(text))
			return error(Fail("Expected '" + text + "' but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);

		return;
	}

	Error<void> ExpectKeyword(string text)
	{
		if (!AcceptKeyword(text))
			return error(Fail("Expected '" + text + "' but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);

		return;
	}

	Error<string> ExpectIdentifier(string what)
	{
		if (Current().Kind != TokenKind.Identifier)
			return error(Fail("Expected " + what + " but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);

		return Next().Text;
	}

	Error<int64> ExpectInteger()
	{
		bool negative = AcceptSymbol("-");

		if (Current().Kind != TokenKind.Integer)
			return error(Fail("Expected a number but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);

		int64 value = Next().Value;

		return negative ? -value : value;
	}

	Error<ProgramNode> ParseProgram(string file)
	{
		var items = List<SyntaxNode>.Create();

		while (Current().Kind != TokenKind.EndOfFile)
			items.Add(try ParseTop());

		return ProgramNode { File = file, Items = ArrayOf(items) };
	}

	Error<SyntaxNode> ParseTop()
	{
		var token = Current();

		if (token.Kind == TokenKind.Identifier)
		{
			switch (token.Text)
			{
				case "flag":
				case "var":
				case "var32":
					return DeclItem(try ParseDecl());
				case "map":
					return ParseMap();
				case "screen":
					return ParseScreenBlock();
				case "on":
					return BindingItem(try ParseBinding());
				case "group":
					return GroupItem(try ParseGroup());
				case "conversation":
					return ParseConversation();
				case "npc":
				case "entity":
					return ParseEntity();
				case "preset":
					return PresetItem(try ParsePreset());
				case "use":
					return UseItem(try ParseUse());
				default:
					break;
			}
		}

		return error(Fail("Unexpected " + token.Describe() + ".", token), (int)ErrorKind.Syntax);
	}

	Error<DeclNode> ParseDecl()
	{
		var location = Current().Location;
		var kind = DeclKind.Var32;
		string word = Next().Text;

		if (word == "flag")
			kind = DeclKind.Flag;
		else if (word == "var")
			kind = DeclKind.Var;

		string name = try ExpectIdentifier("name");
		Optional<int64> initial = null;

		if (AcceptSymbol("="))
			initial = try ExpectInteger();

		try ExpectSymbol(";");

		return DeclNode { Location = location, Kind = kind, Name = name, Initial = initial };
	}

	Error<SyntaxNode> ParseMap()
	{
		var location = Next().Location;
		string name = try ExpectIdentifier("map name");
		string template = null;
		var items = List<SyntaxNode>.Create();

		try ExpectSymbol("{");

		while (!AcceptSymbol("}"))
		{
			if (Current().IsKeyword("template"))
			{
				Next();
				template = try ExpectIdentifier("template name");
				try ExpectSymbol(";");
			}
			else
			{
				items.Add(try ParseTop());
			}
		}

		return SyntaxNode { Kind = NodeKind.Map, Location = location, Name = name, Template = template, Items = ArrayOf(items) };
	}

	Error<SyntaxNode> ParseScreenBlock()
	{
		var location = Next().Location;
		string name = try ExpectIdentifier("screen name");
		var items = List<SyntaxNode>.Create();

		try ExpectSymbol("{");

		while (!AcceptSymbol("}"))
			items.Add(try ParseTop());

		return SyntaxNode { Kind = NodeKind.ScreenBlock, Location = location, Name = name, Items = ArrayOf(items) };
	}

	Error<BindingNode> ParseBinding()
	{
		var location = Next().Location;
		var trigger = try ParseTriggerHead();
		var place = (try ParsePlace()).ToOptional();

		try ExpectSymbol("->");

		string group = try ExpectIdentifier("group name");

		try ExpectSymbol(";");

		return BindingNode { Location = location, Trigger = trigger, Place = place, Group = group };
	}

	Error<CallNode> ParseTriggerHead()
	{
		var location = Current().Location;
		string name = try ExpectIdentifier("trigger name");
		var args = new ArgNode[0];

		if (AcceptSymbol("("))
		{
			if (!AcceptSymbol(")"))
			{
				args = try ParseArgs();
				try ExpectSymbol(")");
			}
		}

		return CallNode.Create(location, name, args);
	}

	Error<MaybePlace> ParsePlace()
	{
		if (AcceptKeyword("at"))
		{
			try ExpectSymbol("(");

			int64 x = try ExpectInteger();

			try ExpectSymbol(",");

			int64 y = try ExpectInteger();

			try ExpectSymbol(")");

			return MaybePlace { Present = true, Place = BindingPlace { X = x, Y = y, Width = null, Height = null } };
		}

		if (AcceptKeyword("in"))
		{
			try ExpectSymbol("(");

			int64 x = try ExpectInteger();

			try ExpectSymbol(",");

			int64 y = try ExpectInteger();

			try ExpectSymbol(",");

			int64 width = try ExpectInteger();

			try ExpectSymbol(",");

			int64 height = try ExpectInteger();

			try ExpectSymbol(")");

			return MaybePlace { Present = true, Place = BindingPlace { X = x, Y = y, Width = width, Height = height } };
		}

		return MaybePlace { Present = false };
	}

	Error<GroupNode> ParseGroup()
	{
		var location = Next().Location;
		string name = try ExpectIdentifier("group name");
		Optional<GroupMode> mode = null;
		var rules = List<RuleNode>.Create();

		if (AcceptKeyword("first"))
			mode = GroupMode.First;
		else if (AcceptKeyword("all"))
			mode = GroupMode.All;

		try ExpectSymbol("{");

		while (!AcceptSymbol("}"))
			rules.Add(try ParseRule());

		if (rules.Count() == 0)
			return error(Fail("Group '" + name + "' has no rules.", Current()), (int)ErrorKind.Syntax);

		return GroupNode { Location = location, Name = name, Mode = mode, Rules = ArrayOf(rules) };
	}

	Error<RuleNode> ParseRule()
	{
		var location = Current().Location;
		bool once = AcceptKeyword("once");
		Optional<ConditionNode> condition = null;
		bool isElse = false;

		if (AcceptKeyword("when"))
			condition = try ParseCondition();
		else if (AcceptKeyword("else"))
			isElse = true;

		try ExpectKeyword("do");

		var actions = try ParseBlock();
		string then = null;
		var thenLocation = SourceLocation.None();

		if (Current().IsKeyword("then"))
		{
			thenLocation = Next().Location;
			then = try ExpectIdentifier("group name");
			try ExpectSymbol(";");
		}

		return RuleNode { Location = location, Once = once, IsElse = isElse, Condition = condition, Actions = actions, Then = then, ThenLocation = thenLocation };
	}

	Error<CallNode[]> ParseBlock()
	{
		var actions = List<CallNode>.Create();

		try ExpectSymbol("{");

		while (!AcceptSymbol("}"))
		{
			actions.Add(try ParseCall());
			try ExpectSymbol(";");
		}

		return ArrayOf(actions);
	}

	Error<CallNode> ParseCall()
	{
		var location = Current().Location;
		string name = try ExpectIdentifier("action name");
		var args = new ArgNode[0];

		try ExpectSymbol("(");

		if (!AcceptSymbol(")"))
		{
			args = try ParseArgs();
			try ExpectSymbol(")");
		}

		return CallNode.Create(location, name, args);
	}

	Error<ArgNode[]> ParseArgs()
	{
		var args = List<ArgNode>.Create();

		args.Add(try ParseArg());

		while (AcceptSymbol(","))
			args.Add(try ParseArg());

		return ArrayOf(args);
	}

	Error<ArgNode> ParseArg()
	{
		var token = Current();

		switch (token.Kind)
		{
			case TokenKind.Integer:
				Next();

				return ArgNode.Int(token.Location, token.Value, false);
			case TokenKind.Symbol:
			{
				if (token.Text == "+")
				{
					Next();

					if (Current().Kind != TokenKind.Integer)
						return error(Fail("Expected a number after '+' but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);

					return ArgNode.Rel(token.Location, Next().Value);
				}

				if (token.Text == "-")
				{
					Next();

					if (Current().Kind != TokenKind.Integer)
						return error(Fail("Expected a number after '-' but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);

					return ArgNode.Int(token.Location, -Next().Value, true);
				}

				if (token.Text == "(")
				{
					Next();

					int64 x = try ExpectInteger();

					try ExpectSymbol(",");

					int64 y = try ExpectInteger();

					try ExpectSymbol(")");

					return ArgNode.Pos(token.Location, x, y);
				}

				break;
			}
			case TokenKind.Identifier:
				Next();

				if (token.Text == "here")
					return ArgNode.Here(token.Location);

				if (Current().IsSymbol(".") && PeekToken(1).Kind == TokenKind.Identifier)
				{
					Next();

					return ArgNode.Symbol(token.Location, token.Text, Next().Text);
				}

				return ArgNode.Ident(token.Location, token.Text);
			default:
				break;
		}

		return error(Fail("Expected an argument but found " + token.Describe() + ".", token), (int)ErrorKind.Syntax);
	}

	Error<ConditionNode> ParseCondition()
	{
		var location = Current().Location;
		var clauses = List<ClauseNode>.Create();
		bool bareOr = false;

		do
		{
			var clause = try ParseClause();

			clauses.Add(clause.Clause);
			bareOr = bareOr || clause.BareOr;
		}
		while (AcceptKeyword("and"));

		if (clauses.Count() > 1 && bareOr)
			_diagnostics.Error("E008", "'or' must be written in parentheses when combined with 'and'.", location);

		return ConditionNode { Location = location, Clauses = ArrayOf(clauses) };
	}

	Error<ParsedClause> ParseClause()
	{
		var location = Current().Location;
		var literals = List<LiteralNode>.Create();
		bool bareOr = false;

		if (AcceptSymbol("("))
		{
			literals.Add(try ParseLiteral());

			while (AcceptKeyword("or"))
				literals.Add(try ParseLiteral());

			try ExpectSymbol(")");
		}
		else
		{
			literals.Add(try ParseLiteral());

			while (AcceptKeyword("or"))
			{
				bareOr = true;
				literals.Add(try ParseLiteral());
			}
		}

		return ParsedClause { Clause = ClauseNode { Location = location, Literals = ArrayOf(literals) }, BareOr = bareOr };
	}

	Error<LiteralNode> ParseLiteral()
	{
		var location = Current().Location;
		bool not = AcceptKeyword("not");

		return LiteralNode { Location = location, Not = not, Atom = try ParseAtom() };
	}

	Error<AtomNode> ParseAtom()
	{
		var location = Current().Location;

		if (Current().Kind == TokenKind.Identifier && PeekToken(1).IsSymbol("("))
			return AtomNode { Kind = AtomKind.Call, Location = location, Call = try ParseCall() };

		var left = try ParseArg();

		if (Current().Kind != TokenKind.Symbol)
			return error(Fail("Expected a comparison operator but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);

		Comparison comparison;

		switch (Current().Text)
		{
			case "==":
				comparison = Comparison.Equal;
				break;
			case "!=":
				comparison = Comparison.NotEqual;
				break;
			case "<":
				comparison = Comparison.Less;
				break;
			case "<=":
				comparison = Comparison.LessOrEqual;
				break;
			case ">":
				comparison = Comparison.Greater;
				break;
			case ">=":
				comparison = Comparison.GreaterOrEqual;
				break;
			default:
				return error(Fail("Expected a comparison operator but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);
		}

		Next();

		return AtomNode { Kind = AtomKind.Compare, Location = location, Left = left, Comparison = comparison, Right = try ParseArg() };
	}

	Error<SyntaxNode> ParseConversation()
	{
		var location = Next().Location;
		string name = try ExpectIdentifier("entity name");
		var items = List<SyntaxNode>.Create();

		try ExpectSymbol("{");

		while (!AcceptSymbol("}"))
			items.Add(try ParseEntityItem());

		return SyntaxNode { Kind = NodeKind.Conversation, Location = location, Name = name, Items = ArrayOf(items) };
	}

	Error<SyntaxNode> ParseEntity()
	{
		var token = Next();
		var kind = token.Text == "npc" ? EntityKind.Npc : EntityKind.Entity;
		string name = try ExpectIdentifier("entity name");

		try ExpectKeyword("at");
		try ExpectSymbol("(");

		int64 x = try ExpectInteger();

		try ExpectSymbol(",");

		int64 y = try ExpectInteger();

		try ExpectSymbol(")");

		var items = List<SyntaxNode>.Create();

		try ExpectSymbol("{");

		while (!AcceptSymbol("}"))
			items.Add(try ParseEntityItem());

		return SyntaxNode { Kind = NodeKind.Entity, Location = token.Location, EntityKind = kind, Name = name, X = x, Y = y, Items = ArrayOf(items) };
	}

	Error<SyntaxNode> ParseEntityItem()
	{
		var token = Current();

		if (token.Kind != TokenKind.Identifier)
			return error(Fail("Unexpected " + token.Describe() + ".", token), (int)ErrorKind.Syntax);

		switch (token.Text)
		{
			case "on":
				return ParseEntityOn();
			case "bark":
				return BarkItem(try ParseBark());
			case "routine":
				return RoutineItem(try ParseRoutine());
			case "greet":
			{
				Next();

				var text = try ParseArg();

				if (text.Kind != ArgKind.Symbol)
					return error(Fail("Expected a text symbol (T.name) after 'greet'.", token), (int)ErrorKind.Syntax);

				try ExpectSymbol(";");

				return SyntaxNode { Kind = NodeKind.Greet, Location = token.Location, Greet = GreetNode { Location = token.Location, Text = text } };
			}
			case "topic":
			{
				Next();

				if (Current().Kind != TokenKind.String)
					return error(Fail("Expected a keyword string after 'topic' but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);

				string word = Next().Text;
				Optional<ConditionNode> condition = null;

				if (AcceptKeyword("when"))
					condition = try ParseCondition();

				try ExpectKeyword("do");

				var topic = TopicNode { Location = token.Location, Word = word, Condition = condition, Actions = try ParseBlock() };

				return SyntaxNode { Kind = NodeKind.Topic, Location = token.Location, Topic = topic };
			}
			case "use":
				return UseItem(try ParseUse());
			default:
				break;
		}

		return error(Fail("Unexpected " + token.Describe() + ".", token), (int)ErrorKind.Syntax);
	}

	Error<SyntaxNode> ParseEntityOn()
	{
		var location = Next().Location;
		var trigger = try ParseTriggerHead();

		if (Current().IsKeyword("when") || Current().IsKeyword("do"))
		{
			if (trigger.Args.Length != 1)
				return error(Fail("'" + trigger.Name + "' needs exactly one argument.", Current()), (int)ErrorKind.Syntax);

			Optional<ConditionNode> condition = null;

			if (AcceptKeyword("when"))
				condition = try ParseCondition();

			try ExpectKeyword("do");

			var onItem = OnItemNode { Location = location, TriggerName = trigger.Name, Argument = trigger.Args[0], Condition = condition, Actions = try ParseBlock() };

			return SyntaxNode { Kind = NodeKind.OnItem, Location = location, OnItem = onItem };
		}

		var place = (try ParsePlace()).ToOptional();

		try ExpectSymbol("->");

		string group = try ExpectIdentifier("group name");

		try ExpectSymbol(";");

		return BindingItem(BindingNode { Location = location, Trigger = trigger, Place = place, Group = group });
	}

	Error<BarkNode> ParseBark()
	{
		var location = Next().Location;
		var text = try ParseArg();

		if (text.Kind != ArgKind.Symbol)
			return error(Fail("Expected a text symbol (T.name) after 'bark'.", Current()), (int)ErrorKind.Syntax);

		Optional<ConditionNode> condition = null;

		if (AcceptKeyword("when"))
			condition = try ParseCondition();

		try ExpectKeyword("every");

		var every = try ParseDuration();

		try ExpectSymbol(";");

		return BarkNode { Location = location, Text = text, Condition = condition, Every = every };
	}

	Error<DurationValue> ParseDuration()
	{
		if (Current().Kind != TokenKind.Duration)
			return error(Fail("Expected a duration like 30t, 2s, 2min or 6h but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);

		var token = Next();
		var unit = DurationUnit.GameHours;

		if (token.Text == "t")
			unit = DurationUnit.Ticks;
		else if (token.Text == "s")
			unit = DurationUnit.Seconds;
		else if (token.Text == "min")
			unit = DurationUnit.GameMinutes;

		return DurationValue { Amount = token.Value, Unit = unit };
	}

	Error<RoutineNode> ParseRoutine()
	{
		var location = Next().Location;
		string name = try ExpectIdentifier("routine name");
		var entries = List<RoutineEntry>.Create();

		try ExpectSymbol("{");

		while (!AcceptSymbol("}"))
		{
			if (Current().Kind != TokenKind.Time)
				return error(Fail("Expected a time of day like 06:00 but found " + Current().Describe() + ".", Current()), (int)ErrorKind.Syntax);

			var time = Next();
			var steps = List<RoutineStep>.Create();

			do
			{
				steps.Add(try ParseRoutineStep());
				try ExpectSymbol(";");
			}
			while (Current().IsKeyword("walk_to") || Current().IsKeyword("stay") || Current().IsKeyword("sleep"));

			entries.Add(RoutineEntry { Location = time.Location, Minute = time.Value, Steps = ArrayOf(steps) });
		}

		return RoutineNode { Location = location, Name = name, Entries = ArrayOf(entries) };
	}

	Error<RoutineStep> ParseRoutineStep()
	{
		var token = Current();

		if (AcceptKeyword("walk_to"))
			return RoutineStep { Kind = RoutineStepKind.WalkTo, Target = try ExpectIdentifier("target name"), Duration = null };

		if (AcceptKeyword("stay"))
			return RoutineStep { Kind = RoutineStepKind.Stay, Target = null, Duration = try ParseDuration() };

		if (AcceptKeyword("sleep"))
			return RoutineStep { Kind = RoutineStepKind.Sleep, Target = null, Duration = null };

		return error(Fail("Expected 'walk_to', 'stay' or 'sleep' but found " + token.Describe() + ".", token), (int)ErrorKind.Syntax);
	}

	Error<PresetNode> ParsePreset()
	{
		var location = Next().Location;

		if ((Current().IsKeyword("cond") || Current().IsKeyword("action")) && PeekToken(1).Kind == TokenKind.Identifier)
		{
			bool isCondition = Next().Text == "cond";
			string fragmentName = try ExpectIdentifier("preset name");
			var fragmentParams = try ParseParams();

			try ExpectSymbol("=");

			if (isCondition)
			{
				var body = try ParseCondition();

				try ExpectSymbol(";");

				return PresetNode
				{
					Location = location, Kind = PresetKind.Condition, Name = fragmentName, Params = fragmentParams, ConditionBody = body,
					ActionBody = null, Trigger = null, Mode = null, Decls = new DeclNode[0], Rules = new RuleNode[0]
				};
			}

			var actions = List<CallNode>.Create();

			do
			{
				actions.Add(try ParseCall());
				try ExpectSymbol(";");
			}
			while (Current().Kind == TokenKind.Identifier && PeekToken(1).IsSymbol("("));

			return PresetNode
			{
				Location = location, Kind = PresetKind.Action, Name = fragmentName, Params = fragmentParams, ConditionBody = null,
				ActionBody = ArrayOf(actions), Trigger = null, Mode = null, Decls = new DeclNode[0], Rules = new RuleNode[0]
			};
		}

		string name = try ExpectIdentifier("preset name");
		var parameters = try ParseParams();

		try ExpectKeyword("on");

		var trigger = try ParseTriggerHead();
		Optional<GroupMode> mode = null;

		if (AcceptKeyword("first"))
			mode = GroupMode.First;
		else if (AcceptKeyword("all"))
			mode = GroupMode.All;

		var decls = List<DeclNode>.Create();
		var rules = List<RuleNode>.Create();

		try ExpectSymbol("{");

		while (Current().IsKeyword("flag") || Current().IsKeyword("var") || Current().IsKeyword("var32"))
			decls.Add(try ParseDecl());

		while (!AcceptSymbol("}"))
			rules.Add(try ParseRule());

		if (rules.Count() == 0)
			return error(Fail("Preset '" + name + "' has no rules.", Current()), (int)ErrorKind.Syntax);

		return PresetNode
		{
			Location = location, Kind = PresetKind.Pattern, Name = name, Params = parameters, ConditionBody = null, ActionBody = null,
			Trigger = trigger, Mode = mode, Decls = ArrayOf(decls), Rules = ArrayOf(rules)
		};
	}

	Error<PresetParam[]> ParseParams()
	{
		var parameters = List<PresetParam>.Create();

		try ExpectSymbol("(");

		if (AcceptSymbol(")"))
			return ArrayOf(parameters);

		do
		{
			string name = try ExpectIdentifier("parameter name");
			string kind = null;
			Optional<ArgNode> defaultValue = null;

			if (AcceptSymbol(":"))
				kind = try ExpectIdentifier("parameter kind");

			if (AcceptSymbol("="))
				defaultValue = try ParseArg();

			parameters.Add(PresetParam { Name = name, Kind = kind, Default = defaultValue });
		}
		while (AcceptSymbol(","));

		try ExpectSymbol(")");

		return ArrayOf(parameters);
	}

	Error<UseNode> ParseUse()
	{
		var location = Next().Location;
		string name = try ExpectIdentifier("preset name");
		var args = new ArgNode[0];

		try ExpectSymbol("(");

		if (!AcceptSymbol(")"))
		{
			args = try ParseArgs();
			try ExpectSymbol(")");
		}

		var place = (try ParsePlace()).ToOptional();

		try ExpectSymbol(";");

		return UseNode { Location = location, Name = name, Args = args, Place = place };
	}
}

/// The place of a binding or use, if one was written (Error<Optional<T>> is not allowed in CShift).
struct MaybePlace
{
	bool Present;
	BindingPlace Place;

	Optional<BindingPlace> ToOptional()
	{
		if (Present)
			return Place;

		return null;
	}
}

/// A clause and whether it had an 'or' without parentheses (C#: the out parameter of ParseClause).
struct ParsedClause
{
	ClauseNode Clause;
	bool BareOr;
}

SyntaxNode DeclItem(DeclNode decl)
{
	return SyntaxNode { Kind = NodeKind.Decl, Location = decl.Location, Decl = decl };
}

SyntaxNode BindingItem(BindingNode binding)
{
	return SyntaxNode { Kind = NodeKind.Binding, Location = binding.Location, Binding = binding };
}

SyntaxNode GroupItem(GroupNode group)
{
	return SyntaxNode { Kind = NodeKind.Group, Location = group.Location, Group = group };
}

SyntaxNode PresetItem(PresetNode preset)
{
	return SyntaxNode { Kind = NodeKind.Preset, Location = preset.Location, Preset = preset };
}

SyntaxNode UseItem(UseNode use)
{
	return SyntaxNode { Kind = NodeKind.Use, Location = use.Location, Use = use };
}

SyntaxNode BarkItem(BarkNode bark)
{
	return SyntaxNode { Kind = NodeKind.Bark, Location = bark.Location, Bark = bark };
}

SyntaxNode RoutineItem(RoutineNode routine)
{
	return SyntaxNode { Kind = NodeKind.Routine, Location = routine.Location, Routine = routine };
}
