// Pass A declares slots, groups, entities and presets and expands the syntactic sugar (conversations, barks, preset
// patterns) into pending groups and bindings. Pass B (Rules.csh, Operands.csh) compiles the rules, Analysis.csh checks the
// whole program.
//
// C#: the partial class Compilation. CShift structs cannot be split across files, so the state is a handle (Compiler: all
// mutable state lives in lists, dictionaries and cells, copies see the same state) and the methods are free functions
// that take it as the first parameter.

namespace Amber.Script.Compilation;

using System;
using Amber.Base;
using Amber.Script.Binary;
using Amber.Script.Common;
using Amber.Script.Syntax;

const int MaxPresetDepth = 4;

struct DeclaredPreset
{
	ScopeContext Scope;
	PresetNode Preset;
}

struct DeclaredFlag
{
	ScopeContext Scope;
	string Name;
	uint16 Slot;
	SourceLocation Location;
}

/// A preset and the scope that declares it.
struct FoundPreset
{
	PresetNode Preset;
	ScopeContext Owner;
}

struct Compiler
{
	DiagnosticBag Diagnostics;
	SymbolTable Symbols;
	CompileOptions Options;
	CompilationResult Result;
	Dictionary<string, uint16> CustomEvents;
	HashSet<string> UsedPresets;
	List<DeclaredPreset> DeclaredPresets;
	List<DeclaredFlag> DeclaredFlags;
	ScopeContext Global;
	/// All scopes in the order they were created; the position is the ID of the scope (CompiledScope.Id).
	List<ScopeContext> AllScopes;
	Cell<int> PresetInstances;

	static Compiler Create(DiagnosticBag diagnostics, SymbolTable symbols, CompileOptions options, CompilationResult result)
	{
		var global = ScopeContext.Create(ScopeKind.Global, "global", result.Global);
		var compiler = Compiler
		{
			Diagnostics = diagnostics,
			Symbols = symbols,
			Options = options,
			Result = result,
			CustomEvents = Dictionary<string, uint16>.Create(),
			UsedPresets = HashSet<string>.Create(),
			DeclaredPresets = List<DeclaredPreset>.Create(),
			DeclaredFlags = List<DeclaredFlag>.Create(),
			Global = global,
			AllScopes = List<ScopeContext>.Create(),
			PresetInstances = Cell<int>.Of(0)
		};

		compiler.AllScopes.Add(global);

		return compiler;
	}

	/// The scope with the ID (CompiledScope.Id).
	ScopeContext ScopeById(int id)
	{
		return AllScopes.Get(id);
	}

	/// Runs both passes, the analysis, the deduplication and the encoding. Returns the result with the layout and the
	/// chunks.
	CompilationResult Run(ProgramNode[] programs)
	{
		var result = Result;
		var global = Global;

		// declare global presets first so that maps can use them regardless of file order
		foreach (var program in programs)
		{
			foreach (var item in program.Items)
			{
				if (item.Kind == NodeKind.Preset)
					AddPreset(this, global, item.Preset);
			}
		}

		foreach (var program in programs)
		{
			foreach (var item in program.Items)
			{
				switch (item.Kind)
				{
					case NodeKind.Map:
					{
						var output = CompiledScope.Create(AllScopes.Count(), ScopeKind.Map, item.Name);

						if (result.FindMap(item.Name) is CompiledScope existing)
							Diagnostics.Error("E002", "Map '" + item.Name + "' is declared twice.", item.Location);

						result.Maps.Add(output);

						var scope = ScopeContext.Create(ScopeKind.Map, item.Name, output);

						AllScopes.Add(scope);

						foreach (var mapItem in item.Items)
						{
							if (mapItem.Kind == NodeKind.Preset)
								AddPreset(this, scope, mapItem.Preset);
						}

						ProcessItems(this, scope, item.Items);
						break;
					}
					case NodeKind.ScreenBlock:
					{
						var output = CompiledScope.Create(AllScopes.Count(), ScopeKind.Screen, item.Name);

						result.Screens.Add(output);

						var scope = ScopeContext.Create(ScopeKind.Screen, item.Name, output);

						AllScopes.Add(scope);
						DeclareScreen(this, scope);
						ProcessItems(this, scope, item.Items);
						break;
					}
					case NodeKind.Preset:
						break;
					default:
						ProcessItems(this, global, new SyntaxNode[] { item });
						break;
				}
			}
		}

		foreach (var scope in AllScopes)
			FinishConversations(this, scope);

		foreach (var scope in AllScopes)
			CompileScope(this, scope);

		Analyze(this);

		foreach (var declared in DeclaredPresets)
		{
			if (!UsedPresets.Contains(PresetKey(declared.Scope, declared.Preset.Name)))
				Diagnostics.Warning("W008", "Preset '" + declared.Preset.Name + "' is never used.", declared.Preset.Location);
		}

		if (Diagnostics.HasErrors())
			return result;

		if (!Options.NoDeduplicate)
		{
			result.DuplicateGroupsRemoved = Deduplicator.Run(result.Global, result.Maps, result.Screens);
		}
		else
		{
			foreach (var scope in AllScopes)
				Deduplicator.RecordReferences(scope.Output);
		}

		var layout = StringBuilder.Create();
		bool first = true;

		foreach (var scope in result.AllScopes())
		{
			foreach (var entry in scope.Layout)
			{
				if (!first)
					layout.Append('\n');

				first = false;
				layout.Append(ScopeKindName(scope.Kind) + " " + scope.Name + " " + StateNamespaceName(entry.Namespace) + "." + SlotKindName(entry.Kind)
					+ "[" + entry.Index + "] " + entry.Name);
			}
		}

		result.LayoutText = layout.ToString();
		result.LayoutHash = Crc32Of(Utf8Bytes(result.LayoutText));

		foreach (var scope in AllScopes)
		{
			scope.Output.GroupsChunk.Set(ScriptEncoder.EncodeGroups(scope.Output.Groups));
			scope.Output.BindingsChunk.Set(ScriptEncoder.EncodeBindings(scope.Output.Bindings));
		}

		return result;
	}
}

string PresetKey(ScopeContext scope, string name)
{
	return scope.Name + ":" + name;
}

void DeclareScreen(Compiler c, ScopeContext scope)
{
	if (c.Symbols.TryResolve(SymbolKind.Screen, scope.Name) is uint16 id)
		scope.ScreenId.Set(id);

	if (c.Options.Screens.Get(scope.Name) is ScreenSignature signature)
	{
		foreach (var arg in signature.Args)
			DeclareSlot(c, scope, SlotKind.Var, arg, SourceLocation.None());

		for (var i = 0; i < signature.Nodes.Length; i += 1)
			scope.Nodes.Set(signature.Nodes[i], i);
	}
}

void ProcessItems(Compiler c, ScopeContext scope, SyntaxNode[] items)
{
	foreach (var item in items)
	{
		switch (item.Kind)
		{
			case NodeKind.Decl:
				DeclareSlot(c, scope, item.Decl);
				break;
			case NodeKind.Group:
				AddGroup(c, scope, item.Group);
				break;
			case NodeKind.Preset:
				break;
			case NodeKind.Binding:
				AddBinding(c, scope, item.Binding, ExpansionContext.Empty(), null, null);
				break;
			case NodeKind.Entity:
				ProcessEntity(c, scope, item);
				break;
			case NodeKind.Conversation:
				ProcessConversation(c, scope, item);
				break;
			case NodeKind.Use:
				ProcessUse(c, scope, item.Use, null);
				break;
			default:
				c.Diagnostics.Error("E003", item.KindName() + " is not allowed here.", item.Location);
				break;
		}
	}
}

SlotKind SlotKindOf(DeclKind kind)
{
	switch (kind)
	{
		case DeclKind.Flag:
			return SlotKind.Flag;
		case DeclKind.Var:
			return SlotKind.Var;
		default:
			return SlotKind.Var32;
	}
}

void DeclareSlot(Compiler c, ScopeContext scope, DeclNode decl)
{
	DeclareSlot(c, scope, SlotKindOf(decl.Kind), decl.Name, decl.Location);
}

Optional<SlotInfo> DeclareSlot(Compiler c, ScopeContext scope, SlotKind kind, string name, SourceLocation location)
{
	if (scope.Slots.ContainsKey(name))
	{
		c.Diagnostics.Error("E002", "'" + name + "' is already declared in this scope.", location);

		return null;
	}

	int index = scope.NextIndex(kind);

	if (index > Wire.MaxSlotIndex)
	{
		c.Diagnostics.Error("E010", "Too many " + SlotKindName(kind) + " slots in '" + scope.Name + "'.", location);

		return null;
	}

	var info = SlotInfo { Kind = kind, Slot = Wire.Slot(scope.Namespace(), index) };

	scope.Slots.Set(name, info);
	scope.Output.Layout.Add(LayoutEntry { Namespace = scope.Namespace(), Kind = kind, Name = name, Index = index });

	if (kind == SlotKind.Flag)
		c.DeclaredFlags.Add(DeclaredFlag { Scope = scope, Name = name, Slot = info.Slot, Location = location });

	return info;
}

/// Allocates a slot with a generated name (once flags, preset instance state).
SlotInfo AllocateSlot(Compiler c, ScopeContext scope, SlotKind kind, string name, SourceLocation location)
{
	int index = scope.NextIndex(kind);

	if (index > Wire.MaxSlotIndex)
	{
		c.Diagnostics.Error("E010", "Too many " + SlotKindName(kind) + " slots in '" + scope.Name + "'.", location);
		index = Wire.MaxSlotIndex;
	}

	var info = SlotInfo { Kind = kind, Slot = Wire.Slot(scope.Namespace(), index) };

	scope.Output.Layout.Add(LayoutEntry { Namespace = scope.Namespace(), Kind = kind, Name = name, Index = index });

	return info;
}

void AddPreset(Compiler c, ScopeContext scope, PresetNode preset)
{
	if (ActionTable.ByName(preset.Name) is OpInfo action)
	{
		c.Diagnostics.Error("E019", "Preset '" + preset.Name + "' collides with a built-in name.", preset.Location);

		return;
	}

	if (ConditionTable.ByName(preset.Name) is OpInfo condition)
	{
		c.Diagnostics.Error("E019", "Preset '" + preset.Name + "' collides with a built-in name.", preset.Location);

		return;
	}

	if (scope.Presets.ContainsKey(preset.Name))
	{
		c.Diagnostics.Error("E002", "Preset '" + preset.Name + "' is already declared in this scope.", preset.Location);

		return;
	}

	if (!scope.Is(c.Global) && c.Global.Presets.ContainsKey(preset.Name))
		c.Diagnostics.Warning("W007", "Preset '" + preset.Name + "' hides a global preset.", preset.Location);

	scope.Presets.Set(preset.Name, preset);
	c.DeclaredPresets.Add(DeclaredPreset { Scope = scope, Preset = preset });
}

Optional<FoundPreset> FindPreset(Compiler c, ScopeContext scope, string name)
{
	if (scope.Presets.TryGet(name) is PresetNode preset)
		return FoundPreset { Preset = preset, Owner = scope };

	if (c.Global.Presets.TryGet(name) is PresetNode globalPreset)
		return FoundPreset { Preset = globalPreset, Owner = c.Global };

	return null;
}

void MarkPresetUsed(Compiler c, ScopeContext owner, string name)
{
	c.UsedPresets.Add(PresetKey(owner, name));
}

void AddGroup(Compiler c, ScopeContext scope, GroupNode group)
{
	var mode = GroupMode.First;

	if (group.Mode is GroupMode written)
		mode = written;

	if (scope.NamedGroups.ContainsKey(group.Name))
	{
		c.Diagnostics.Error("E002", "Group '" + group.Name + "' is already declared in this scope.", group.Location);

		return;
	}

	AddPendingGroup(c, scope, group.Name, mode, group.Rules, group.Location, ExpansionContext.Empty(), null);
}

PendingGroup AddPendingGroup(Compiler c, ScopeContext scope, string name, GroupMode mode, RuleNode[] rules, SourceLocation location, ExpansionContext env, string origin)
{
	var pending = PendingGroup { Name = name, Mode = mode, Rules = rules, Location = location, Env = env, Origin = origin, Index = scope.Groups.Count() };

	if (pending.Index > Wire.MaxLocalGroupIndex)
		c.Diagnostics.Error("E010", "Too many groups in '" + scope.Name + "'.", location);

	scope.Groups.Add(pending);
	scope.NamedGroups.Set(name, pending);

	ValidateGroupShape(c, pending);

	return pending;
}

void ValidateGroupShape(Compiler c, PendingGroup group)
{
	bool unconditionalSeen = false;

	for (var i = 0; i < group.Rules.Length; i += 1)
	{
		var rule = group.Rules[i];

		if (rule.IsElse && i != group.Rules.Length - 1)
			c.Diagnostics.Error("E011", "'else' must be the last rule of group '" + group.Name + "'.", rule.Location);

		if (rule.Then != null && group.Mode == GroupMode.All)
			c.Diagnostics.Error("E005", "'then' is not allowed in group '" + group.Name + "' with mode 'all'.", rule.ThenLocation);

		if (unconditionalSeen && group.Mode == GroupMode.First)
			c.Diagnostics.Warning("W005", "Rule " + (i + 1) + " of group '" + group.Name + "' is unreachable.", rule.Location);

		if (rule.Condition == null && !rule.Once)
			unconditionalSeen = true;
	}
}

void AddBinding(Compiler c, ScopeContext scope, BindingNode binding, ExpansionContext env, string entityName, string origin)
{
	scope.Bindings.Add(PendingBinding
	{
		TriggerName = binding.Trigger.Name,
		TriggerArgs = binding.Trigger.Args,
		Place = binding.Place,
		GroupName = binding.Group,
		Location = binding.Location,
		Env = env,
		EntityName = entityName,
		Origin = origin
	});
}

void ProcessEntity(Compiler c, ScopeContext scope, SyntaxNode entity)
{
	if (scope.Kind != ScopeKind.Map)
	{
		c.Diagnostics.Error("E003", "Entities can only be declared inside a map.", entity.Location);

		return;
	}

	if (scope.Entities.ContainsKey(entity.Name))
	{
		c.Diagnostics.Error("E002", "Entity '" + entity.Name + "' is already declared.", entity.Location);

		return;
	}

	int id = scope.Entities.Count();

	scope.Entities.Set(entity.Name, id);
	scope.Output.Entities.Set(entity.Name, id);
	scope.Output.EntityInfos.Add(EntityInfo { Name = entity.Name, Id = id, X = (int)entity.X, Y = (int)entity.Y, Kind = entity.EntityKind });

	ProcessEntityItems(c, scope, entity.Name, entity.Items);
}

void ProcessConversation(Compiler c, ScopeContext scope, SyntaxNode conversation)
{
	if (!scope.Entities.ContainsKey(conversation.Name))
	{
		c.Diagnostics.Error("E001", "Unknown entity '" + conversation.Name + "' in conversation.", conversation.Location);

		return;
	}

	ProcessEntityItems(c, scope, conversation.Name, conversation.Items);
}

void ProcessEntityItems(Compiler c, ScopeContext scope, string entityName, SyntaxNode[] items)
{
	var env = ExpansionContext.ForEntity(entityName);

	if (!scope.Conversations.ContainsKey(entityName))
	{
		scope.Conversations.Set(entityName, ConversationData
		{
			Entity = entityName,
			Location = items.Length > 0 ? items[0].Location : SourceLocation.None(),
			Greet = null,
			Topics = List<TopicNode>.Create(),
			OnItems = List<OnItemNode>.Create()
		});
	}

	foreach (var item in items)
	{
		switch (item.Kind)
		{
			case NodeKind.Binding:
				AddBinding(c, scope, item.Binding, env, entityName, null);
				break;
			case NodeKind.Bark:
				AddBark(c, scope, entityName, item.Bark, env);
				break;
			case NodeKind.Routine:
				AddRoutine(c, scope, item.Routine, entityName);
				break;
			case NodeKind.Greet:
			{
				var conversation = scope.Conversations.GetOrDefault(entityName, new ConversationData());

				if (conversation.Greet is GreetNode existing)
				{
					c.Diagnostics.Warning("W009", "'" + entityName + "' has more than one greeting; the first is used.", item.Greet.Location);
				}
				else
				{
					conversation.Greet = item.Greet;
					scope.Conversations.Set(entityName, conversation);
				}

				break;
			}
			case NodeKind.Topic:
				scope.Conversations.GetOrDefault(entityName, new ConversationData()).Topics.Add(item.Topic);
				break;
			case NodeKind.OnItem:
				scope.Conversations.GetOrDefault(entityName, new ConversationData()).OnItems.Add(item.OnItem);
				break;
			case NodeKind.Use:
				ProcessUse(c, scope, item.Use, entityName);
				break;
			default:
				c.Diagnostics.Error("E003", item.KindName() + " is not allowed in an entity.", item.Location);
				break;
		}
	}
}

void AddRoutine(Compiler c, ScopeContext scope, RoutineNode routine, string entityName)
{
	if (scope.Routines.ContainsKey(routine.Name))
	{
		c.Diagnostics.Error("E002", "Routine '" + routine.Name + "' is already declared in this map.", routine.Location);

		return;
	}

	scope.Output.RoutineInfos.Add(RoutineInfo { Id = scope.Routines.Count(), Name = routine.Name, Entity = entityName, Node = routine });
	scope.Routines.Set(routine.Name, scope.Routines.Count());
	scope.RoutineNodes.Add(routine);
	scope.Output.Routines.Add(routine);
}

void AddBark(Compiler c, ScopeContext scope, string entityName, BarkNode bark, ExpansionContext env)
{
	string groupName = entityName + "$bark" + scope.Groups.Count();
	var location = bark.Location;
	var call = CallNode.Create(location, "bark", new ArgNode[] { ArgNode.Ident(location, entityName), bark.Text });
	var rule = RuleNode
	{
		Location = location, Once = false, IsElse = false, Condition = bark.Condition, Actions = new CallNode[] { call }, Then = null,
		ThenLocation = SourceLocation.None()
	};

	AddPendingGroup(c, scope, groupName, GroupMode.First, new RuleNode[] { rule }, location, env, "bark of " + entityName);

	int64 interval = bark.Every.ToTicks();

	scope.Bindings.Add(PendingBinding
	{
		TriggerName = "map_tick",
		TriggerArgs = new ArgNode[] { ArgNode.Int(location, interval, false) },
		Place = null,
		GroupName = groupName,
		Location = location,
		Env = env,
		EntityName = null,
		Origin = "bark of " + entityName
	});
}

void FinishConversations(Compiler c, ScopeContext scope)
{
	foreach (var conversation in scope.Conversations.Values())
	{
		if (conversation.HasContent())
			EmitConversation(c, scope, conversation);
	}
}

void EmitConversation(Compiler c, ScopeContext scope, ConversationData conversation)
{
	string entity = conversation.Entity;
	var env = ExpansionContext.ForEntity(entity);
	var location = conversation.Location;
	int entityId = scope.Entities.GetOrDefault(entity, 0);
	string origin = "conversation of " + entity;
	var topicWords = List<string>.Create();
	string greeting = null;

	foreach (var topic in conversation.Topics)
	{
		if (topic.Word != "*")
			topicWords.Add(topic.Word);
	}

	if (conversation.Greet is GreetNode greetName)
		greeting = greetName.Text.Name;

	scope.Output.Conversations.Set(entity, ConversationInfo { Entity = entity, Greeting = greeting, Topics = ArrayOf(topicWords) });

	// greeting: speak -> say(greeting), then the native conversation screen takes over
	var greetActions = List<CallNode>.Create();

	if (conversation.Greet is GreetNode greet)
		greetActions.Add(CallNode.Create(greet.Location, "say", new ArgNode[] { greet.Text }));

	greetActions.Add(CallNode.Create(location, "push_screen", new ArgNode[]
	{
		ArgNode.Symbol(location, "S", "conversation"), ArgNode.Int(location, 0, false), ArgNode.Int(location, 1, false), ArgNode.Int(location, entityId, false)
	}));

	var greetRule = RuleNode
	{
		Location = location, Once = false, IsElse = false, Condition = null, Actions = ArrayOf(greetActions), Then = null, ThenLocation = SourceLocation.None()
	};

	AddPendingGroup(c, scope, entity + "$greet", GroupMode.First, new RuleNode[] { greetRule }, location, env, origin);
	scope.Bindings.Add(PendingBinding
	{
		TriggerName = "speak", TriggerArgs = new ArgNode[0], Place = null, GroupName = entity + "$greet", Location = location, Env = env,
		EntityName = entity, Origin = origin
	});

	if (conversation.Topics.Count() > 0)
	{
		var rules = List<RuleNode>.Create();

		for (var i = 0; i < conversation.Topics.Count(); i += 1)
		{
			var topic = conversation.Topics.Get(i);
			bool isDefault = topic.Word == "*";

			if (isDefault && i != conversation.Topics.Count() - 1)
				c.Diagnostics.Error("E011", "The default topic \"*\" must be the last topic.", topic.Location);

			Optional<ConditionNode> condition = topic.Condition;

			if (!isDefault)
				condition = WithArgumentCompare(topic.Condition, ArgNode.Symbol(topic.Location, "K", topic.Word.ToLower()), topic.Location);

			rules.Add(RuleNode
			{
				Location = topic.Location, Once = false, IsElse = isDefault && topic.Condition == null, Condition = condition, Actions = topic.Actions,
				Then = null, ThenLocation = SourceLocation.None()
			});
		}

		AddPendingGroup(c, scope, entity + "$keyword", GroupMode.First, ArrayOf(rules), location, env, origin);
		scope.Bindings.Add(PendingBinding
		{
			TriggerName = "keyword", TriggerArgs = new ArgNode[0], Place = null, GroupName = entity + "$keyword", Location = location, Env = env,
			EntityName = entity, Origin = origin
		});
	}

	// the on_item blocks grouped by trigger, in the order of their first appearance
	var triggerNames = List<string>.Create();

	foreach (var onItem in conversation.OnItems)
	{
		if (!ContainsText(triggerNames, onItem.TriggerName))
			triggerNames.Add(onItem.TriggerName);
	}

	foreach (var triggerName in triggerNames)
	{
		var rules = List<RuleNode>.Create();
		var firstLocation = SourceLocation.None();

		foreach (var onItem in conversation.OnItems)
		{
			if (onItem.TriggerName != triggerName)
				continue;

			if (rules.Count() == 0)
				firstLocation = onItem.Location;

			rules.Add(RuleNode
			{
				Location = onItem.Location, Once = false, IsElse = false, Condition = WithArgumentCompare(onItem.Condition, onItem.Argument, onItem.Location),
				Actions = onItem.Actions, Then = null, ThenLocation = SourceLocation.None()
			});
		}

		if (TriggerTable.ByName(triggerName) == null)
		{
			c.Diagnostics.Error("E001", "Unknown trigger '" + triggerName + "'.", firstLocation);

			continue;
		}

		AddPendingGroup(c, scope, entity + "$" + triggerName, GroupMode.First, ArrayOf(rules), location, env, origin);
		scope.Bindings.Add(PendingBinding
		{
			TriggerName = triggerName, TriggerArgs = new ArgNode[0], Place = null, GroupName = entity + "$" + triggerName, Location = location,
			Env = env, EntityName = entity, Origin = origin
		});
	}
}

ConditionNode WithArgumentCompare(Optional<ConditionNode> original, ArgNode value, SourceLocation location)
{
	var atom = AtomNode { Kind = AtomKind.Compare, Location = location, Left = ArgNode.Ident(location, "arg"), Comparison = Comparison.Equal, Right = value };
	var compare = LiteralNode { Location = location, Not = false, Atom = atom };
	var clauses = List<ClauseNode>.Create();

	clauses.Add(ClauseNode { Location = location, Literals = new LiteralNode[] { compare } });

	if (original is ConditionNode condition)
		clauses.AddRange(condition.Clauses);

	return ConditionNode { Location = location, Clauses = ArrayOf(clauses) };
}

void ProcessUse(Compiler c, ScopeContext scope, UseNode use, string entityName)
{
	var found = FindPreset(c, scope, use.Name);

	if (found is FoundPreset hit)
	{
		var preset = hit.Preset;

		MarkPresetUsed(c, hit.Owner, use.Name);

		if (preset.Kind != PresetKind.Pattern)
		{
			c.Diagnostics.Error("E017", "Preset '" + use.Name + "' is a fragment; only patterns can be used with 'use'.", use.Location);

			return;
		}

		var bound = BindPresetArguments(c, preset, use.Args, ExpansionContext.Empty(), use.Location);

		if (bound is Dictionary<string, ArgNode> parameters)
		{
			int instance = c.PresetInstances.Get();

			c.PresetInstances.Set(instance + 1);

			string origin = preset.Name + " @ " + Path.GetFileName(use.Location.File) + ":" + use.Location.Line;
			var instanceSlots = Dictionary<string, SlotInfo>.Create();

			foreach (var decl in preset.Decls)
				instanceSlots.Set(decl.Name, AllocateSlot(c, scope, SlotKindOf(decl.Kind), "__" + preset.Name + "_" + instance + "_" + decl.Name, use.Location));

			var stack = List<string>.Create();

			stack.Add(preset.Name);

			var env = ExpansionContext { Params = parameters, InstanceSlots = instanceSlots, ImplicitEntity = entityName, Depth = 0, Stack = stack };
			string groupName = preset.Name + "@" + instance;
			var mode = GroupMode.First;

			if (preset.Mode is GroupMode written)
				mode = written;

			AddPendingGroup(c, scope, groupName, mode, preset.Rules, preset.Location, env, origin);

			if (preset.Trigger is CallNode trigger)
			{
				var triggerArgs = new ArgNode[trigger.Args.Length];

				for (var i = 0; i < trigger.Args.Length; i += 1)
					triggerArgs[i] = ResolveArgument(trigger.Args[i], env);

				scope.Bindings.Add(PendingBinding
				{
					TriggerName = trigger.Name, TriggerArgs = triggerArgs, Place = use.Place, GroupName = groupName, Location = use.Location, Env = env,
					EntityName = entityName, Origin = origin
				});
			}
		}

		return;
	}

	c.Diagnostics.Error("E018", "Unknown preset '" + use.Name + "'.", use.Location);
}

/// Binds the arguments of a preset use or call to its parameters (defaults, type check E017). No value on errors.
Optional<Dictionary<string, ArgNode>> BindPresetArguments(Compiler c, PresetNode preset, ArgNode[] args, ExpansionContext callerEnv, SourceLocation location)
{
	if (args.Length > preset.Params.Length)
	{
		c.Diagnostics.Error("E017", "Preset '" + preset.Name + "' takes at most " + preset.Params.Length + " argument(s) but got " + args.Length + ".", location);

		return null;
	}

	var parameters = Dictionary<string, ArgNode>.Create();
	bool ok = true;

	for (var i = 0; i < preset.Params.Length; i += 1)
	{
		var parameter = preset.Params[i];
		Optional<ArgNode> value = parameter.Default;

		if (i < args.Length)
			value = ResolveArgument(args[i], callerEnv);

		if (value is ArgNode given)
		{
			if (!MatchesParameterKind(parameter.Kind, given))
			{
				c.Diagnostics.Error("E017", "Argument " + (i + 1) + " of preset '" + preset.Name + "' does not match parameter kind '" + parameter.Kind + "'.", given.Location);
				ok = false;

				continue;
			}

			parameters.Set(parameter.Name, given);
		}
		else
		{
			c.Diagnostics.Error("E017", "Preset '" + preset.Name + "' needs a value for parameter '" + parameter.Name + "'.", location);
			ok = false;
		}
	}

	if (!ok)
		return null;

	return parameters;
}

bool MatchesParameterKind(string kind, ArgNode value)
{
	if (kind == null || kind == "sym")
		return value.Kind == ArgKind.Symbol || value.Kind == ArgKind.Ident || value.Kind == ArgKind.Int;

	switch (kind)
	{
		case "int":
			return value.Kind == ArgKind.Int;
		case "text":
			return value.IsSymbolWithPrefix("T");
		case "item":
			return value.IsSymbolWithPrefix("I");
		case "tile":
			return value.IsSymbolWithPrefix("TILE") || value.Kind == ArgKind.Int || value.Kind == ArgKind.Rel;
		case "flag":
		case "var":
		case "group":
			return value.Kind == ArgKind.Ident;
		case "word":
			return value.IsSymbolWithPrefix("K") || value.IsSymbolWithPrefix("W");
		case "pos":
			return value.Kind == ArgKind.Pos || value.Kind == ArgKind.Here;
		default:
			return false;
	}
}

ArgNode ResolveArgument(ArgNode arg, ExpansionContext env)
{
	if (arg.Kind == ArgKind.Ident)
	{
		if (env.Params.TryGet(arg.Name) is ArgNode value)
			return value;
	}

	return arg;
}
