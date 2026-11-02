// Checks screen and prefab files (YAML) against spec/schemas/screen.schema.json, which is embedded into the program at
// compile time (C#: an embedded resource and JsonSchema.Net).
//
// The validator implements the part of JSON Schema (draft 2020-12) the screen schema uses: type, enum, const, pattern,
// minimum, maximum, required, properties, additionalProperties, minProperties, maxProperties, items, minItems, maxItems,
// uniqueItems, $ref (local), allOf, anyOf, oneOf, not and unevaluatedProperties. Annotations (title, description, default)
// are ignored.

namespace Amber.Screens.ScreenSchema;

using System;
using Amber.Base;

// System has a JsonValue and a JsonKind of its own: the JSON types of Amber.Base are written with their namespace.

const string SchemaText = embed("../../spec/schemas/screen.schema.json");

Amber.Base.JsonValue Root = LoadSchema();

Amber.Base.JsonValue LoadSchema()
{
	var parsed = ParseJson(SchemaText);

	if (parsed is Amber.Base.JsonValue schema)
		return schema;

	Environment.Panic("The embedded screen schema is broken: " + parsed.Message);

	return Amber.Base.JsonValue.Null();
}

/// Validates the text of a YAML file. Returns the problems (location and message), empty if the file is valid.
List<string> Validate(string yaml)
{
	var problems = List<string>.Create();
	var parsed = ParseYaml(yaml);

	if (parsed is YamlNode document)
	{
		var result = Check(Root, ToJson(document), "");

		foreach (var problem in result.Errors)
			problems.Add(problem);
	}
	else
	{
		problems.Add(": " + parsed.Message);
	}

	return problems;
}

/// YAML to JSON with typed scalars (plain integers and booleans), like a JSON compatible YAML parser.
Amber.Base.JsonValue ToJson(YamlNode node)
{
	switch (node.Kind)
	{
		case YamlKind.Mapping:
		{
			var result = Amber.Base.JsonValue.NewObject();

			for (var i = 0; i < node.Count(); i += 1)
				result.Set(node.KeyAt(i), ToJson(node.ItemAt(i)));

			return result;
		}
		case YamlKind.Sequence:
		{
			var result = Amber.Base.JsonValue.NewArray();

			for (var i = 0; i < node.Count(); i += 1)
				result.Add(ToJson(node.ItemAt(i)));

			return result;
		}
		default:
		{
			string text = node.Value == null ? "" : node.Value;

			if (node.Plain)
			{
				if (TryParseLong(text) is int64 integer)
					return Amber.Base.JsonValue.OfInteger(integer);

				if (TryParseBool(text) is bool flag)
					return Amber.Base.JsonValue.OfBool(flag);
			}

			return Amber.Base.JsonValue.OfString(text);
		}
	}
}

/// The outcome of checking an instance against a schema: the problems and the names of the properties the schema
/// evaluated (for unevaluatedProperties).
struct CheckResult
{
	List<string> Errors;
	HashSet<string> Evaluated;

	static CheckResult Create()
	{
		return CheckResult { Errors = List<string>.Create(), Evaluated = HashSet<string>.Create() };
	}

	bool Valid()
	{
		return Errors.Count() == 0;
	}

	void Fail(string path, string message)
	{
		Errors.Add(path + ": " + message);
	}

	/// Takes over the errors of a subschema, and its evaluated properties if it was valid.
	void Merge(CheckResult other)
	{
		foreach (var problem in other.Errors)
			Errors.Add(problem);

		if (other.Valid())
		{
			foreach (var name in other.Evaluated.ToArray())
				Evaluated.Add(name);
		}
	}

	void MergeEvaluated(CheckResult other)
	{
		foreach (var name in other.Evaluated.ToArray())
			Evaluated.Add(name);
	}
}

string TypeName(Amber.Base.JsonValue value)
{
	switch (value.Kind)
	{
		case Amber.Base.JsonKind.Null:
			return "null";
		case Amber.Base.JsonKind.Bool:
			return "boolean";
		case Amber.Base.JsonKind.Number:
			return value.IsInteger ? "integer" : "number";
		case Amber.Base.JsonKind.String:
			return "string";
		case Amber.Base.JsonKind.Array:
			return "array";
		default:
			return "object";
	}
}

bool HasType(Amber.Base.JsonValue value, string type)
{
	switch (type)
	{
		case "null":
			return value.Kind == Amber.Base.JsonKind.Null;
		case "boolean":
			return value.Kind == Amber.Base.JsonKind.Bool;
		case "integer":
			return value.Kind == Amber.Base.JsonKind.Number && (value.IsInteger || value.Number == Math.Floor(value.Number));
		case "number":
			return value.Kind == Amber.Base.JsonKind.Number;
		case "string":
			return value.Kind == Amber.Base.JsonKind.String;
		case "array":
			return value.Kind == Amber.Base.JsonKind.Array;
		case "object":
			return value.Kind == Amber.Base.JsonKind.Object;
		default:
			return false;
	}
}

/// Resolves "#/$defs/name" (and other local JSON pointers) in the root schema.
Optional<Amber.Base.JsonValue> Resolve(string reference)
{
	if (!reference.StartsWith("#"))
		return null;

	var current = Root;

	foreach (var part in reference.Substring(1).Split('/'))
	{
		if (part.Length == 0)
			continue;

		if (current.Get(part.Replace("~1", "/").Replace("~0", "~")) is Amber.Base.JsonValue next)
			current = next;
		else
			return null;
	}

	return current;
}

CheckResult Check(Amber.Base.JsonValue schema, Amber.Base.JsonValue instance, string path)
{
	var result = CheckResult.Create();

	if (schema.Kind == Amber.Base.JsonKind.Bool)
	{
		if (!schema.Bool)
			result.Fail(path, "no value is allowed here");

		return result;
	}

	if (schema.Kind != Amber.Base.JsonKind.Object)
		return result;

	if (schema.Get("$ref") is Amber.Base.JsonValue reference)
	{
		if (Resolve(reference.Text) is Amber.Base.JsonValue target)
			result.Merge(Check(target, instance, path));
		else
			result.Fail(path, "unknown schema reference '" + reference.Text + "'");
	}

	if (schema.Get("type") is Amber.Base.JsonValue type)
	{
		bool matches = false;

		if (type.Kind == Amber.Base.JsonKind.Array)
		{
			foreach (var alternative in type.Items)
			{
				if (HasType(instance, alternative.Text))
					matches = true;
			}
		}
		else
		{
			matches = HasType(instance, type.Text);
		}

		if (!matches)
		{
			result.Fail(path, "Value is \"" + TypeName(instance) + "\" but should be \"" + (type.Kind == Amber.Base.JsonKind.Array ? type.ToJson() : type.Text) + "\"");

			return result;
		}
	}

	if (schema.Get("enum") is Amber.Base.JsonValue allowed)
	{
		bool found = false;

		foreach (var candidate in allowed.Items)
		{
			if (candidate.SameAs(instance))
				found = true;
		}

		if (!found)
			result.Fail(path, "Value should match one of the values specified by the enum");
	}

	if (schema.Get("const") is Amber.Base.JsonValue constant)
	{
		if (!constant.SameAs(instance))
			result.Fail(path, "Expected " + constant.ToJson());
	}

	if (instance.Kind == Amber.Base.JsonKind.String)
	{
		if (schema.Get("pattern") is Amber.Base.JsonValue pattern)
		{
			if (!RegexMatch(pattern.Text, instance.Text))
				result.Fail(path, "The string value is not a match for the indicated regular expression");
		}
	}

	if (instance.Kind == Amber.Base.JsonKind.Number)
	{
		if (schema.Get("minimum") is Amber.Base.JsonValue minimum)
		{
			if (instance.Number < minimum.Number)
				result.Fail(path, instance.ToJson() + " should be at least " + minimum.ToJson());
		}

		if (schema.Get("maximum") is Amber.Base.JsonValue maximum)
		{
			if (instance.Number > maximum.Number)
				result.Fail(path, instance.ToJson() + " should be at most " + maximum.ToJson());
		}
	}

	if (instance.Kind == Amber.Base.JsonKind.Object)
		CheckObject(schema, instance, path, result);

	if (instance.Kind == Amber.Base.JsonKind.Array)
		CheckArray(schema, instance, path, result);

	if (schema.Get("allOf") is Amber.Base.JsonValue allOf)
	{
		foreach (var part in allOf.Items)
			result.Merge(Check(part, instance, path));
	}

	if (schema.Get("anyOf") is Amber.Base.JsonValue anyOf)
	{
		bool any = false;

		foreach (var part in anyOf.Items)
		{
			var sub = Check(part, instance, path);

			if (sub.Valid())
			{
				any = true;
				result.MergeEvaluated(sub);
			}
		}

		if (!any)
			result.Fail(path, "Value should match at least one of the anyOf schemas");
	}

	if (schema.Get("oneOf") is Amber.Base.JsonValue oneOf)
	{
		int matches = 0;

		foreach (var part in oneOf.Items)
		{
			var sub = Check(part, instance, path);

			if (sub.Valid())
			{
				matches += 1;
				result.MergeEvaluated(sub);
			}
		}

		if (matches != 1)
			result.Fail(path, "Expected 1 matching subschema but found " + matches);
	}

	if (schema.Get("not") is Amber.Base.JsonValue negated)
	{
		if (Check(negated, instance, path).Valid())
			result.Fail(path, "Schema is not expected to match");
	}

	if (instance.Kind == Amber.Base.JsonKind.Object)
	{
		if (schema.Get("unevaluatedProperties") is Amber.Base.JsonValue unevaluated)
		{
			for (var i = 0; i < instance.Keys.Count(); i += 1)
			{
				string name = instance.Keys.Get(i);

				if (result.Evaluated.Contains(name))
					continue;

				var sub = Check(unevaluated, instance.Items.Get(i), path + "/" + name);

				if (!sub.Valid())
					result.Fail(path, "The property '" + name + "' is not allowed");

				result.Evaluated.Add(name);
			}
		}
	}

	return result;
}

void CheckObject(Amber.Base.JsonValue schema, Amber.Base.JsonValue instance, string path, CheckResult result)
{
	if (schema.Get("required") is Amber.Base.JsonValue required)
	{
		var missing = List<string>.Create();

		foreach (var name in required.Items)
		{
			if (!instance.Has(name.Text))
				missing.Add(JsonQuote(name.Text));
		}

		if (missing.Count() > 0)
			result.Fail(path, "Required properties [" + JoinList(",", missing) + "] are not present");
	}

	if (schema.Get("minProperties") is Amber.Base.JsonValue minProperties)
	{
		if ((int64)instance.Count() < minProperties.Integer)
			result.Fail(path, "Value should have at least " + minProperties.Integer + " properties");
	}

	if (schema.Get("maxProperties") is Amber.Base.JsonValue maxProperties)
	{
		if ((int64)instance.Count() > maxProperties.Integer)
			result.Fail(path, "Value should have at most " + maxProperties.Integer + " properties");
	}

	var properties = Amber.Base.JsonValue.NewObject();

	if (schema.Get("properties") is Amber.Base.JsonValue declared)
		properties = declared;

	for (var i = 0; i < instance.Keys.Count(); i += 1)
	{
		string name = instance.Keys.Get(i);
		var value = instance.Items.Get(i);

		if (properties.Get(name) is Amber.Base.JsonValue propertySchema)
		{
			var sub = Check(propertySchema, value, path + "/" + name);

			foreach (var problem in sub.Errors)
				result.Errors.Add(problem);

			result.Evaluated.Add(name);
		}
		else if (schema.Get("additionalProperties") is Amber.Base.JsonValue additional)
		{
			var sub = Check(additional, value, path + "/" + name);

			if (!sub.Valid())
			{
				if (additional.Kind == Amber.Base.JsonKind.Bool)
					result.Fail(path, "The property '" + name + "' is not allowed");
				else
				{
					foreach (var problem in sub.Errors)
						result.Errors.Add(problem);
				}
			}

			result.Evaluated.Add(name);
		}
	}
}

void CheckArray(Amber.Base.JsonValue schema, Amber.Base.JsonValue instance, string path, CheckResult result)
{
	if (schema.Get("minItems") is Amber.Base.JsonValue minItems)
	{
		if ((int64)instance.Count() < minItems.Integer)
			result.Fail(path, "Value should have at least " + minItems.Integer + " items");
	}

	if (schema.Get("maxItems") is Amber.Base.JsonValue maxItems)
	{
		if ((int64)instance.Count() > maxItems.Integer)
			result.Fail(path, "Value should have at most " + maxItems.Integer + " items");
	}

	if (schema.Get("uniqueItems") is Amber.Base.JsonValue unique)
	{
		if (unique.Kind == Amber.Base.JsonKind.Bool && unique.Bool)
		{
			for (var i = 0; i < instance.Count(); i += 1)
			{
				for (var j = i + 1; j < instance.Count(); j += 1)
				{
					if (instance.Items.Get(i).SameAs(instance.Items.Get(j)))
						result.Fail(path, "Found duplicates at indices [" + i + ", " + j + "]");
				}
			}
		}
	}

	if (schema.Get("items") is Amber.Base.JsonValue items)
	{
		for (var i = 0; i < instance.Count(); i += 1)
		{
			var sub = Check(items, instance.Items.Get(i), path + "/" + i);

			foreach (var problem in sub.Errors)
				result.Errors.Add(problem);
		}
	}
}

// ---------------------------------------------------------------------------------------------------------------------
// A small regular expression matcher for the patterns of the schema: ^ and $ anchors, literals, '.', character classes
// [a-z_] (with ranges and ^ for negation), and the quantifiers *, + and ?.
// ---------------------------------------------------------------------------------------------------------------------

/// One element of a pattern: a character class (or a single character) and its quantifier.
struct RegexAtom
{
	bool Any;
	bool Negated;
	string Chars;
	int Min;
	int Max;
}

List<RegexAtom> CompileRegex(string pattern, int start, int end)
{
	var atoms = List<RegexAtom>.Create();
	int i = start;

	while (i < end)
	{
		var atom = RegexAtom { Any = false, Negated = false, Chars = "", Min = 1, Max = 1 };
		char c = pattern[i];

		if (c == '[')
		{
			i += 1;

			if (i < end && pattern[i] == '^')
			{
				atom.Negated = true;
				i += 1;
			}

			var chars = StringBuilder.Create();

			while (i < end && pattern[i] != ']')
			{
				char first = pattern[i];

				if (first == '\\' && i + 1 < end)
				{
					i += 1;
					first = pattern[i];
				}

				if (i + 2 < end && pattern[i + 1] == '-' && pattern[i + 2] != ']')
				{
					char last = pattern[i + 2];

					for (var code = (int)first; code <= (int)last; code += 1)
						chars.Append((char)code);

					i += 3;
				}
				else
				{
					chars.Append(first);
					i += 1;
				}
			}

			i += 1;
			atom.Chars = chars.ToString();
		}
		else if (c == '.')
		{
			atom.Any = true;
			i += 1;
		}
		else
		{
			if (c == '\\' && i + 1 < end)
			{
				i += 1;
				c = pattern[i];
			}

			atom.Chars = pattern.Substring(i, 1);
			i += 1;
		}

		if (i < end && pattern[i] == '*')
		{
			atom.Min = 0;
			atom.Max = int.MaxValue;
			i += 1;
		}
		else if (i < end && pattern[i] == '+')
		{
			atom.Max = int.MaxValue;
			i += 1;
		}
		else if (i < end && pattern[i] == '?')
		{
			atom.Min = 0;
			i += 1;
		}

		atoms.Add(atom);
	}

	return atoms;
}

bool AtomMatches(RegexAtom atom, char c)
{
	if (atom.Any)
		return c != '\n';

	return atom.Chars.Contains(c) != atom.Negated;
}

bool MatchAt(List<RegexAtom> atoms, int atomIndex, string text, int position, bool anchoredEnd)
{
	if (atomIndex == atoms.Count())
		return !anchoredEnd || position == text.Length;

	var atom = atoms.Get(atomIndex);
	int count = 0;

	while (count < atom.Min)
	{
		if (position + count >= text.Length || !AtomMatches(atom, text[position + count]))
			return false;

		count += 1;
	}

	// greedy, with backtracking
	int longest = count;

	while (longest < atom.Max && position + longest < text.Length && AtomMatches(atom, text[position + longest]))
		longest += 1;

	for (var length = longest; length >= count; length -= 1)
	{
		if (MatchAt(atoms, atomIndex + 1, text, position + length, anchoredEnd))
			return true;
	}

	return false;
}

bool RegexMatch(string pattern, string text)
{
	bool anchoredStart = pattern.StartsWith("^");
	bool anchoredEnd = pattern.EndsWith("$") && !pattern.EndsWith("\\$");
	var atoms = CompileRegex(pattern, anchoredStart ? 1 : 0, anchoredEnd ? pattern.Length - 1 : pattern.Length);

	if (anchoredStart)
		return MatchAt(atoms, 0, text, 0, anchoredEnd);

	for (var start = 0; start <= text.Length; start += 1)
	{
		if (MatchAt(atoms, 0, text, start, anchoredEnd))
			return true;
	}

	return false;
}
