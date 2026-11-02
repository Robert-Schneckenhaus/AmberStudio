/*
 * amber_trace: runs a golden trace scenario (spec section 12.3) against a pack with the C interpreter and prints the trace.
 * The C counterpart of Amber.Conformance.ScenarioRunner: the traces have to be identical line by line.
 *
 *   amber_trace scenario.scenario [game.pack]
 *
 * The scenario names its pack ("pack game.pack"), or the pack is the second argument. Exit code 0 if all expectations held,
 * 1 if one failed, 2 for a broken scenario or pack.
 */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "amber_pack.h"
#include "amber_rt.h"

#define MAX_STEP_ARGS 16
#define MAX_ITEMS 64
#define TICKS_PER_HOUR 6000

typedef struct step
{
	int tick;
	int line;
	char command[32];
	int argc;
	char args[MAX_STEP_ARGS][96];
} step;

typedef struct symbol
{
	int kind;
	int id;
	char name[64];
} symbol;

typedef struct entity
{
	char name[64];
	int id;
} entity;

typedef struct map_info
{
	int id;
	char name[64];
	int flags, vars, vars32;
	int entity_count;
	entity entities[16];
	amb_script script;
} map_info;

typedef struct layout_slot
{
	char scope_kind[16];
	char scope_name[64];
	char kind[16];
	int index;
	char name[64];
} layout_slot;

typedef struct host_state
{
	amb_interp *interp;
	int map_id;
	int gold;
	int item_ids[MAX_ITEMS];
	int item_counts[MAX_ITEMS];
	int item_total;
	int words[MAX_ITEMS];
	int word_total;
	int waiting[AMB_MAX_THREADS];
} host_state;

static const char *scenario_name = "scenario";
static host_state host;
static symbol *symbols;
static int symbol_count;
static map_info maps[AMB_MAX_MAPS];
static int map_count;
static layout_slot *layout;
static int layout_count;
static int failures;

static void die(const char *format, ...)
{
	va_list arguments;

	va_start(arguments, format);
	vfprintf(stderr, format, arguments);
	va_end(arguments);
	fputc('\n', stderr);
	exit(2);
}

static uint8_t *read_file(const char *path, uint32_t *size)
{
	FILE *file = fopen(path, "rb");
	long length;
	uint8_t *data;

	if (file == NULL)
		die("cannot open %s", path);

	fseek(file, 0, SEEK_END);
	length = ftell(file);
	fseek(file, 0, SEEK_SET);
	data = (uint8_t *)malloc((size_t)length + 1);

	if (data == NULL || fread(data, 1, (size_t)length, file) != (size_t)length)
		die("cannot read %s", path);

	fclose(file);
	data[length] = 0;
	*size = (uint32_t)length;

	return data;
}

/* ---- trace output ---------------------------------------------------------------------------------------------- */

static void print_line(void *user, const char *line)
{
	(void)user;
	puts(line);
}

static void emit(const char *format, ...)
{
	char text[256];
	va_list arguments;

	va_start(arguments, format);
	vsnprintf(text, sizeof text, format, arguments);
	va_end(arguments);
	printf("tick=%lld %s\n", host.interp->ticks, text);
}

/* ---- the host of the scenario ---------------------------------------------------------------------------------- */

static int item_count(int id)
{
	int i;

	for (i = 0; i < host.item_total; i++)
	{
		if (host.item_ids[i] == id)
			return host.item_counts[i];
	}

	return 0;
}

static void set_item_count(int id, int count)
{
	int i;

	for (i = 0; i < host.item_total; i++)
	{
		if (host.item_ids[i] == id)
		{
			host.item_counts[i] = count;

			return;
		}
	}

	if (host.item_total < MAX_ITEMS)
	{
		host.item_ids[host.item_total] = id;
		host.item_counts[host.item_total++] = count;
	}
}

static int knows_word(int id)
{
	int i;

	for (i = 0; i < host.word_total; i++)
	{
		if (host.words[i] == id)
			return 1;
	}

	return 0;
}

static int compare(long long a, unsigned comparison, long long b)
{
	switch (comparison)
	{
		case AMB_CMP_EQUAL: return a == b;
		case AMB_CMP_NOT_EQUAL: return a != b;
		case AMB_CMP_LESS: return a < b;
		case AMB_CMP_LESS_OR_EQUAL: return a <= b;
		case AMB_CMP_GREATER: return a > b;
		case AMB_CMP_GREATER_OR_EQUAL: return a >= b;
		default: return 0;
	}
}

static int32_t combine(uint16_t high, uint16_t low)
{
	return (int32_t)(((uint32_t)high << 16) | low);
}

static int host_execute(void *user, unsigned op, const uint16_t *operands, int count, const amb_thread_ctx *ctx)
{
	(void)user;
	(void)count;

	switch (op)
	{
		case AMB_ACT_GIVE_GOLD:
			host.gold += combine(operands[0], operands[1]);

			return AMB_DONE;
		case AMB_ACT_TAKE_GOLD:
			host.gold -= combine(operands[0], operands[1]);

			if (host.gold < 0)
				host.gold = 0;

			return AMB_DONE;
		case AMB_ACT_GIVE_ITEM:
			set_item_count(operands[0], item_count(operands[0]) + operands[1]);

			return AMB_DONE;
		case AMB_ACT_TAKE_ITEM:
		{
			int left = item_count(operands[0]) - operands[1];

			set_item_count(operands[0], left < 0 ? 0 : left);

			return AMB_DONE;
		}
		case AMB_ACT_LEARN_WORD:
			if (!knows_word(operands[0]) && host.word_total < MAX_ITEMS)
				host.words[host.word_total++] = operands[0];

			return AMB_DONE;
		default:
			break;
	}

	if (amb_action_blocking(op))
	{
		host.waiting[ctx->thread_id] = (int)op;

		return AMB_BLOCKED;
	}

	return AMB_DONE;
}

static int host_evaluate(void *user, unsigned op, const uint16_t *operands, int count, const amb_thread_ctx *ctx)
{
	(void)user;
	(void)count;
	(void)ctx;

	switch (op)
	{
		case AMB_COND_WORD_KNOWN:
			return knows_word(operands[0]);
		case AMB_COND_HAS_ITEM:
			return item_count(operands[0]) >= operands[1];
		case AMB_COND_GOLD:
			return compare(host.gold, operands[0], combine(operands[1], operands[2]));
		case AMB_COND_PARTY_SIZE:
			return compare(1, operands[0], (int16_t)operands[1]);
		case AMB_COND_IN_MAP:
			return operands[0] == host.map_id;
		case AMB_COND_HOUR_IN:
		{
			int hour = (int)((9 + host.interp->ticks / TICKS_PER_HOUR) % 24);

			return operands[0] <= operands[1] ? hour >= operands[0] && hour < operands[1] : hour >= operands[0] || hour < operands[1];
		}
		default:
			return 0;
	}
}

/* ---- reading the pack ------------------------------------------------------------------------------------------ */

static const uint8_t *get_chunk(const amb_pack *pack, uint16_t type, uint16_t id, uint32_t *size)
{
	amb_pack_entry entry;
	const uint8_t *data;
	uint8_t *scratch;
	int status = amb_pack_find(pack, type, id, &entry);

	if (status != AMB_OK)
		return NULL;

	scratch = (uint8_t *)malloc(entry.unpacked_size + 1);
	status = amb_pack_get(pack, type, id, scratch, entry.unpacked_size, &data, size);

	if (status != AMB_OK)
		die("chunk %u:%u is damaged (status %d)", (unsigned)type, (unsigned)id, status);

	return data;
}

typedef struct cursor
{
	const uint8_t *data;
	uint32_t size;
	uint32_t position;
} cursor;

static void need(cursor *c, uint32_t count)
{
	if (c->position + count > c->size)
		die("a chunk is truncated");
}

static int cursor_word(cursor *c)
{
	need(c, 2);
	c->position += 2;

	return amb_be16(c->data + c->position - 2);
}

static uint32_t cursor_dword(cursor *c)
{
	need(c, 4);
	c->position += 4;

	return amb_be32(c->data + c->position - 4);
}

static int cursor_byte(cursor *c)
{
	need(c, 1);

	return c->data[c->position++];
}

static void cursor_text(cursor *c, int length, char *out, size_t capacity)
{
	need(c, (uint32_t)length + (uint32_t)(length % 2));

	if ((size_t)length >= capacity)
		die("a name is too long");

	memcpy(out, c->data + c->position, (size_t)length);
	out[length] = 0;
	c->position += (uint32_t)length + (uint32_t)(length % 2);
}

static const uint8_t *cursor_block(cursor *c, uint32_t *size)
{
	const uint8_t *data;

	*size = cursor_dword(c);
	need(c, *size);
	data = c->data + c->position;
	c->position += *size;

	while (c->position % 4 != 0)
		c->position++;

	return data;
}

static void load_map(const amb_pack *pack, int id)
{
	uint32_t size;
	const uint8_t *data = get_chunk(pack, AMB_CHUNK_MAP, (uint16_t)id, &size);
	cursor c;
	map_info *map;
	int name_length;
	int i;
	int entity_count;
	uint32_t groups_size;
	uint32_t bindings_size;
	const uint8_t *groups;
	const uint8_t *bindings;

	if (map_count >= AMB_MAX_MAPS)
		die("too many maps");

	map = &maps[map_count++];
	c.data = data;
	c.size = size;
	c.position = 0;
	map->id = id;
	name_length = cursor_word(&c);
	map->flags = cursor_word(&c);
	map->vars = cursor_word(&c);
	map->vars32 = cursor_word(&c);
	entity_count = cursor_word(&c);
	cursor_word(&c);
	cursor_text(&c, name_length, map->name, sizeof map->name);

	for (i = 0; i < entity_count; i++)
	{
		int entity_id = cursor_word(&c);
		int length;

		cursor_word(&c);
		cursor_word(&c);
		cursor_byte(&c);
		length = cursor_byte(&c);

		if (i < 16)
		{
			map->entities[i].id = entity_id;
			cursor_text(&c, length, map->entities[i].name, sizeof map->entities[i].name);
			map->entity_count = i + 1;
		}
		else
		{
			char skipped[64];

			cursor_text(&c, length, skipped, sizeof skipped);
		}
	}

	groups = cursor_block(&c, &groups_size);
	bindings = cursor_block(&c, &bindings_size);

	if (amb_script_init(&map->script, groups, groups_size, bindings, bindings_size) != 0)
		die("the scripts of map '%s' are truncated", map->name);
}

static void load_symbols(const amb_pack *pack)
{
	uint32_t size;
	const uint8_t *data = get_chunk(pack, AMB_CHUNK_SYMBOLS, 0, &size);
	cursor c;
	int count;
	int i;

	if (data == NULL)
		return;

	c.data = data;
	c.size = size;
	c.position = 0;
	count = cursor_word(&c);
	symbols = (symbol *)calloc((size_t)count + 1, sizeof(symbol));

	for (i = 0; i < count; i++)
	{
		int length;

		symbols[i].kind = cursor_byte(&c);
		cursor_byte(&c);
		symbols[i].id = cursor_word(&c);
		length = cursor_word(&c);
		cursor_text(&c, length, symbols[i].name, sizeof symbols[i].name);
	}

	symbol_count = count;
}

static void load_layout(const amb_pack *pack)
{
	uint32_t size;
	const uint8_t *data = get_chunk(pack, AMB_CHUNK_LAYOUT, 0, &size);
	char *text;
	char *line;
	int capacity = 0;

	if (data == NULL)
		return;

	text = (char *)malloc(size + 1);
	memcpy(text, data, size);
	text[size] = 0;

	for (line = strtok(text, "\r\n"); line != NULL; line = strtok(NULL, "\r\n"))
	{
		char kind_scope[16], scope_name[64], slot[64], name[64];
		char *dot;
		char *open;
		layout_slot *entry;

		if (line[0] == '#' || sscanf(line, "%15s %63s %63s %63s", kind_scope, scope_name, slot, name) != 4)
			continue;

		if (layout_count == capacity)
		{
			capacity = capacity == 0 ? 32 : capacity * 2;
			layout = (layout_slot *)realloc(layout, (size_t)capacity * sizeof(layout_slot));
		}

		entry = &layout[layout_count++];
		dot = strchr(slot, '.');
		open = strchr(slot, '[');

		if (dot == NULL || open == NULL || open < dot)
			die("'%s' is not a layout line", line);

		*open = 0;
		strcpy(entry->scope_kind, kind_scope);
		strcpy(entry->scope_name, scope_name);
		strcpy(entry->kind, dot + 1);
		entry->index = atoi(open + 1);
		strcpy(entry->name, name);
	}

	free(text);
}

/* ---- the scenario ---------------------------------------------------------------------------------------------- */

static int parse_number(const char *text, long long *value)
{
	char *end;

	*value = strtoll(text, &end, 10);

	return end != text && *end == 0;
}

static long long value_of(const step *s, const char *text)
{
	long long number;
	char prefix[16];
	const char *dot;
	int kind;
	int i;

	if (parse_number(text, &number))
		return number;

	dot = strchr(text, '.');

	if (dot != NULL && (size_t)(dot - text) < sizeof prefix)
	{
		memcpy(prefix, text, (size_t)(dot - text));
		prefix[dot - text] = 0;
		kind = amb_symbol_kind(prefix);

		for (i = 0; kind >= 0 && i < symbol_count; i++)
		{
			if (symbols[i].kind == kind && strcmp(symbols[i].name, dot + 1) == 0)
				return symbols[i].id;
		}
	}

	die("%s(%d): '%s' is not a number or a symbol.", scenario_name, s->line, text);

	return 0;
}

static const map_info *current_map;

static const layout_slot *find_slot(const char *scope_kind, const char *scope_name, const char *kind, const char *name)
{
	int i;

	for (i = 0; i < layout_count; i++)
	{
		if (strcmp(layout[i].scope_kind, scope_kind) == 0 && strcmp(layout[i].scope_name, scope_name) == 0 && strcmp(layout[i].kind, kind) == 0 && strcmp(layout[i].name, name) == 0)
			return &layout[i];
	}

	return NULL;
}

/* ---- screens --------------------------------------------------------------------------------------------------- */

typedef struct screen_info
{
	int id;
	char name[64];
	int flags, vars, vars32;
	amb_script script;
	amb_chunk *open;
} screen_info;

static screen_info screens[AMB_MAX_SCREENS * 2];
static int screen_count;

/* the SCREEN chunk: u32 definition length, u16 flags/vars/vars32/reserved, the definition, then the groups and bindings blocks */
static void load_screen(const amb_pack *pack, int id)
{
	uint32_t size;
	const uint8_t *data = get_chunk(pack, AMB_CHUNK_SCREEN, (uint16_t)id, &size);
	cursor c;
	screen_info *screen;
	uint32_t definition_length;
	uint32_t groups_size;
	uint32_t bindings_size;
	const uint8_t *groups;
	const uint8_t *bindings;
	int i;

	if (screen_count >= AMB_MAX_SCREENS * 2)
		die("too many screens");

	screen = &screens[screen_count++];
	memset(screen, 0, sizeof *screen);
	screen->id = id;
	snprintf(screen->name, sizeof screen->name, "#%d", id);

	for (i = 0; i < symbol_count; i++)
	{
		if (symbols[i].kind == AMB_SYM_SCREEN && symbols[i].id == id)
			snprintf(screen->name, sizeof screen->name, "%s", symbols[i].name);
	}

	c.data = data;
	c.size = size;
	c.position = 0;
	definition_length = cursor_dword(&c);
	screen->flags = cursor_word(&c);
	screen->vars = cursor_word(&c);
	screen->vars32 = cursor_word(&c);
	cursor_word(&c);
	need(&c, definition_length);
	c.position += definition_length;

	while (c.position % 4 != 0)
		c.position++;

	groups = cursor_block(&c, &groups_size);
	bindings = cursor_block(&c, &bindings_size);

	if (amb_script_init(&screen->script, groups, groups_size, bindings, bindings_size) != 0)
		die("the scripts of screen '%s' are truncated", screen->name);
}

static screen_info *find_screen(const step *s, const char *name)
{
	int i;

	for (i = 0; i < screen_count; i++)
	{
		if (strcmp(screens[i].name, name) == 0)
			return &screens[i];
	}

	die("%s(%d): the screen '%s' does not exist.", scenario_name, s->line, name);

	return NULL;
}

static screen_info *find_open_screen(const step *s, const char *name)
{
	screen_info *screen = find_screen(s, name);

	if (screen->open == NULL)
		die("%s(%d): the screen '%s' is not open.", scenario_name, s->line, name);

	return screen;
}

static void do_open(const step *s)
{
	screen_info *screen;
	amb_trigger trigger;
	char values[512];
	int i;
	int started;

	if (s->argc < 1)
		die("%s(%d): the screen '' does not exist.", scenario_name, s->line);

	screen = find_screen(s, s->args[0]);

	if (screen->open != NULL)
		die("%s(%d): the screen '%s' is already open.", scenario_name, s->line, screen->name);

	screen->open = amb_load_screen(host.interp, screen->id, &screen->script, screen->flags, screen->vars, screen->vars32);

	if (screen->open == NULL)
		die("the screen '%s' does not fit into the tables of the runtime", screen->name);

	values[0] = 0;

	for (i = 1; i < s->argc; i++)
	{
		if (i - 1 < screen->open->state.vars)
			screen->open->state.var[i - 1] = (int16_t)value_of(s, s->args[i]);

		strcat(values, " ");
		strcat(values, s->args[i]);
	}

	emit("open screen %s%s", screen->name, values);
	amb_trigger_init(&trigger, AMB_TRIG_SCREEN_OPEN);
	trigger.map_id = host.map_id;
	trigger.screen_id = screen->id;
	started = amb_trigger_event(host.interp, &trigger);
	emit("opened screen %s threads=%d", screen->name, started);
}

static void do_close(const step *s)
{
	screen_info *screen;
	amb_trigger trigger;
	int started;

	if (s->argc < 1)
		die("%s(%d): the screen '' does not exist.", scenario_name, s->line);

	screen = find_open_screen(s, s->args[0]);
	emit("close screen %s", screen->name);
	amb_trigger_init(&trigger, AMB_TRIG_SCREEN_CLOSE);
	trigger.map_id = host.map_id;
	trigger.screen_id = screen->id;
	started = amb_trigger_event(host.interp, &trigger);
	amb_unload_screen(host.interp, screen->open);
	screen->open = NULL;
	emit("closed screen %s threads=%d", screen->name, started);
}

static void do_run(const step *s)
{
	screen_info *screen;
	int index;
	long long arg = 0;
	int started;

	if (s->argc < 1)
		die("%s(%d): the screen '' does not exist.", scenario_name, s->line);

	screen = find_open_screen(s, s->args[0]);

	if (s->argc < 2)
		die("%s(%d): 'run' needs a group index.", scenario_name, s->line);

	index = (int)value_of(s, s->args[1]);

	if (s->argc > 2)
		arg = value_of(s, s->args[2]);

	emit("run screen %s group %d arg=%lld", screen->name, index, arg);
	started = amb_run_group(host.interp, screen->open, (uint16_t)(0x8000 | index), (uint32_t)arg, host.map_id);
	emit("ran screen %s started=%d", screen->name, started);
}

static const amb_state *state_of(const step *s, const char *kind, const char *name, int *index)
{
	const layout_slot *slot = NULL;
	const char *dot = strchr(name, '.');

	/* "screen.name": a slot of an open screen */
	if (dot != NULL && dot > name)
	{
		char screen_name[64];
		screen_info *screen;

		if ((size_t)(dot - name) >= sizeof screen_name)
			die("%s(%d): a name is too long.", scenario_name, s->line);

		memcpy(screen_name, name, (size_t)(dot - name));
		screen_name[dot - name] = 0;
		screen = find_open_screen(s, screen_name);
		slot = find_slot("Screen", screen_name, kind, dot + 1);

		if (slot == NULL)
			die("%s(%d): unknown %s '%s'.", scenario_name, s->line, kind, name);

		*index = slot->index;

		return &screen->open->state;
	}

	if (current_map != NULL)
		slot = find_slot("Map", current_map->name, kind, name);

	if (slot != NULL)
	{
		*index = slot->index;

		return &amb_find_map(host.interp, current_map->id)->state;
	}

	slot = find_slot("Global", "global", kind, name);

	if (slot == NULL)
		die("%s(%d): unknown %s '%s'.", scenario_name, s->line, kind, name);

	*index = slot->index;

	return &host.interp->global.state;
}

static void do_fire(const step *s)
{
	int type;
	unsigned trigger_type;
	amb_trigger trigger;
	char rest[512];
	int i;
	int started;

	if (s->argc < 1)
		die("%s(%d): 'fire' needs a trigger name.", scenario_name, s->line);

	type = amb_trigger_by_name(s->args[0]);

	if (type < 0)
		die("%s(%d): unknown trigger '%s'.", scenario_name, s->line, s->args[0]);

	trigger_type = (unsigned)type;
	amb_trigger_init(&trigger, trigger_type);
	trigger.map_id = host.map_id;
	rest[0] = 0;

	for (i = 1; i < s->argc; i++)
	{
		const char *pair = s->args[i];
		const char *equals = strchr(pair, '=');
		char key[16];
		const char *value;

		if (equals == NULL || equals == pair || (size_t)(equals - pair) >= sizeof key)
			die("%s(%d): '%s' is not key=value.", scenario_name, s->line, pair);

		memcpy(key, pair, (size_t)(equals - pair));
		key[equals - pair] = 0;
		value = equals + 1;

		if (strcmp(key, "x") == 0) trigger.x = (uint16_t)value_of(s, value);
		else if (strcmp(key, "y") == 0) trigger.y = (uint16_t)value_of(s, value);
		else if (strcmp(key, "ox") == 0) trigger.other_x = (uint16_t)value_of(s, value);
		else if (strcmp(key, "oy") == 0) trigger.other_y = (uint16_t)value_of(s, value);
		else if (strcmp(key, "param") == 0) trigger.param = (uint16_t)value_of(s, value);
		else if (strcmp(key, "arg") == 0) trigger.arg = (uint32_t)value_of(s, value);
		else if (strcmp(key, "screen") == 0) trigger.screen_id = (int)value_of(s, value);
		else if (strcmp(key, "node") == 0) trigger.node_id = (int)value_of(s, value);
		else if (strcmp(key, "entity") == 0)
		{
			int j;
			int found = 0;

			for (j = 0; current_map != NULL && j < current_map->entity_count; j++)
			{
				if (strcmp(current_map->entities[j].name, value) == 0)
				{
					trigger.entity_id = current_map->entities[j].id;
					found = 1;
				}
			}

			if (!found)
				trigger.entity_id = (int)value_of(s, value);
		}
		else
			die("%s(%d): unknown trigger parameter '%s'.", scenario_name, s->line, key);

		if (rest[0] != 0)
			strcat(rest, " ");

		strcat(rest, pair);
	}

	emit("fire %s%s%s", amb_trigger_name(trigger_type), rest[0] ? " " : "", rest);
	started = amb_trigger_event(host.interp, &trigger);
	emit("fired %s threads=%d", amb_trigger_name(trigger_type), started);
}

static void do_answer(const step *s, const char *action, const char *value)
{
	int op = amb_action_by_name(action);
	int16_t result = 0;
	int thread = -1;
	int i;

	if (op < 0)
		die("%s(%d): unknown action '%s'.", scenario_name, s->line, action);

	if (value != NULL)
		result = (int16_t)value_of(s, value);

	for (i = 0; i < host.interp->max_threads; i++)
	{
		if (host.waiting[i] == op)
		{
			thread = i;
			host.waiting[i] = -1;

			break;
		}
	}

	emit("answer %s %d thread=%d", action, (int)result, thread);

	if (thread < 0)
	{
		fprintf(stderr, "failed: %s(%d): nobody is waiting for '%s'\n", scenario_name, s->line, action);
		failures++;
	}
	else
	{
		amb_resume(host.interp, thread, result);
	}
}

static void do_expect(const step *s)
{
	const char *what = s->argc > 0 ? s->args[0] : NULL;
	const char *subject = s->argc > 1 ? s->args[1] : "";
	const char *given = s->argc > 2 ? s->args[2] : NULL;
	long long expected = 0;
	long long actual = 0;
	char text[256];
	char *double_space;
	size_t length;
	int index;

	if (what == NULL)
		die("%s(%d): 'expect' needs a kind.", scenario_name, s->line);

	if (strcmp(what, "flag") == 0)
	{
		const amb_state *state = state_of(s, "Flag", subject, &index);

		expected = given == NULL ? 1 : value_of(s, given);
		actual = amb_flag(state, index);
	}
	else if (strcmp(what, "var") == 0)
	{
		const amb_state *state;

		if (given == NULL)
			die("%s(%d): 'expect var' needs a value.", scenario_name, s->line);

		state = state_of(s, "Var", subject, &index);
		expected = value_of(s, given);
		actual = state->var[index];
	}
	else if (strcmp(what, "var32") == 0)
	{
		const amb_state *state;

		if (given == NULL)
			die("%s(%d): 'expect var32' needs a value.", scenario_name, s->line);

		state = state_of(s, "Var32", subject, &index);
		expected = value_of(s, given);
		actual = state->var32[index];
	}
	else if (strcmp(what, "gold") == 0)
	{
		expected = value_of(s, subject);
		actual = host.gold;
		given = NULL;
	}
	else if (strcmp(what, "item") == 0)
	{
		if (given == NULL)
			die("%s(%d): 'expect item' needs a count.", scenario_name, s->line);

		expected = value_of(s, given);
		actual = item_count((int)value_of(s, subject));
	}
	else if (strcmp(what, "word") == 0)
	{
		expected = given == NULL ? 1 : value_of(s, given);
		actual = knows_word((int)value_of(s, subject));
	}
	else if (strcmp(what, "threads") == 0)
	{
		expected = value_of(s, subject);
		actual = amb_active_threads(host.interp);
		given = NULL;
	}
	else if (strcmp(what, "waiting") == 0)
	{
		int op = amb_action_by_name(subject);
		int i;

		if (op < 0)
			die("%s(%d): unknown action '%s'.", scenario_name, s->line, subject);

		expected = given == NULL ? 1 : value_of(s, given);
		actual = 0;

		for (i = 0; i < host.interp->max_threads; i++)
			actual += host.waiting[i] == op;
	}
	else
		die("%s(%d): unknown expectation '%s'.", scenario_name, s->line, what);

	snprintf(text, sizeof text, "expect %s %s%s%s", what, subject, given == NULL ? "" : " ", given == NULL ? "" : given);

	/* the C# runner collapses double spaces and trims the end */
	while ((double_space = strstr(text, "  ")) != NULL)
		memmove(double_space, double_space + 1, strlen(double_space));

	length = strlen(text);

	while (length > 0 && text[length - 1] == ' ')
		text[--length] = 0;

	if (actual == expected)
	{
		emit("%s ok", text);
	}
	else
	{
		emit("%s FAILED (expected %d, actual %d)", text, (int)expected, (int)actual);
		fprintf(stderr, "failed: %s(%d): %s: expected %d, actual %d\n", scenario_name, s->line, text, (int)expected, (int)actual);
		failures++;
	}
}

static void do_hash(void)
{
	emit("hash crc32=0x%08X gold=%d", (unsigned)amb_state_hash(host.interp, host.map_id), host.gold);
}

static void execute_step(const step *s)
{
	if (strcmp(s->command, "fire") == 0)
		do_fire(s);
	else if (strcmp(s->command, "open") == 0)
		do_open(s);
	else if (strcmp(s->command, "close") == 0)
		do_close(s);
	else if (strcmp(s->command, "run") == 0)
		do_run(s);
	else if (strcmp(s->command, "answer") == 0)
	{
		if (s->argc < 1)
			die("%s(%d): 'answer' needs an action name.", scenario_name, s->line);

		do_answer(s, s->args[0], s->argc > 1 ? s->args[1] : NULL);
	}
	else if (strcmp(s->command, "battle_result") == 0)
		do_answer(s, "battle", s->argc > 0 ? s->args[0] : NULL);
	else if (strcmp(s->command, "expect") == 0)
		do_expect(s);
	else if (strcmp(s->command, "hash") == 0)
		do_hash();
	else
		die("%s(%d): unknown command '%s'.", scenario_name, s->line, s->command);
}

/* splits the text of a line (comment removed) into whitespace separated tokens; returns their number */
static int tokenize(char *line, char *tokens[], int max)
{
	int count = 0;
	char *comment = strchr(line, '#');

	if (comment != NULL)
		*comment = 0;

	while (*line != 0)
	{
		while (*line == ' ' || *line == '\t' || *line == '\r')
			line++;

		if (*line == 0)
			break;

		if (count < max)
			tokens[count++] = line;

		while (*line != 0 && *line != ' ' && *line != '\t' && *line != '\r')
			line++;

		if (*line != 0)
			*line++ = 0;
	}

	return count;
}

int main(int argc, char **argv)
{
	uint32_t scenario_size;
	uint32_t pack_size;
	char *text;
	char *line_start;
	step *steps = NULL;
	int step_count = 0;
	int step_capacity = 0;
	long long seed = 1;
	long long end_tick = -1;
	char map_name[64] = "";
	char pack_path[512] = "";
	amb_pack pack;
	amb_host callbacks;
	amb_script global_script;
	amb_interp *interp;
	uint32_t size;
	const uint8_t *pack_data;
	const uint8_t *groups;
	const uint8_t *bindings;
	uint32_t groups_size = 0;
	uint32_t bindings_size = 0;
	int line_number = 0;
	int i;
	int next = 0;
	long long tick;
	const map_info *map = NULL;

	if (argc < 2)
	{
		fprintf(stderr, "usage: amber_trace scenario.scenario [game.pack]\n");

		return 2;
	}

	scenario_name = argv[1];
	text = (char *)read_file(argv[1], &scenario_size);

	for (line_start = text; line_start != NULL && *line_start != 0; )
	{
		char *line_end = strchr(line_start, '\n');
		char *tokens[3 + MAX_STEP_ARGS];
		int count;

		if (line_end != NULL)
			*line_end = 0;

		line_number++;
		count = tokenize(line_start, tokens, 3 + MAX_STEP_ARGS);

		if (count > 0)
		{
			long long number;

			if (strcmp(tokens[0], "seed") == 0 && count >= 2 && parse_number(tokens[1], &number) && number >= 0)
				seed = number;
			else if (strcmp(tokens[0], "pack") == 0 && count >= 2)
			{
				/* relative to the scenario file */
				const char *slash = strrchr(argv[1], '/');
				const char *backslash = strrchr(argv[1], '\\');
				const char *last = slash > backslash ? slash : backslash;

				if (last != NULL && tokens[1][0] != '/' && tokens[1][1] != ':')
					snprintf(pack_path, sizeof pack_path, "%.*s%s", (int)(last - argv[1] + 1), argv[1], tokens[1]);
				else
					snprintf(pack_path, sizeof pack_path, "%s", tokens[1]);
			}
			else if (strcmp(tokens[0], "script") == 0)
				die("%s(%d): the C runtime runs cooked packs, not scripts (use 'pack').", scenario_name, line_number);
			else if (strcmp(tokens[0], "load") == 0 && count == 3 && strcmp(tokens[1], "map") == 0)
				snprintf(map_name, sizeof map_name, "%s", tokens[2]);
			else if (strcmp(tokens[0], "end") == 0 && count >= 2 && parse_number(tokens[1], &number) && number >= 0)
				end_tick = number;
			else if (strcmp(tokens[0], "at") == 0 && count >= 3 && parse_number(tokens[1], &number) && number >= 0)
			{
				step *s;

				if (step_count == step_capacity)
				{
					step_capacity = step_capacity == 0 ? 32 : step_capacity * 2;
					steps = (step *)realloc(steps, (size_t)step_capacity * sizeof(step));
				}

				s = &steps[step_count++];
				memset(s, 0, sizeof *s);
				s->tick = (int)number;
				s->line = line_number;
				snprintf(s->command, sizeof s->command, "%s", tokens[2]);

				for (i = 3; i < count && s->argc < MAX_STEP_ARGS; i++)
					snprintf(s->args[s->argc++], sizeof s->args[0], "%s", tokens[i]);

				if (step_count > 1 && steps[step_count - 2].tick > s->tick)
					die("%s(%d): the ticks must not go backwards.", scenario_name, line_number);
			}
			else
				die("%s(%d): unknown line.", scenario_name, line_number);
		}

		line_start = line_end == NULL ? NULL : line_end + 1;
	}

	if (argc > 2)
		snprintf(pack_path, sizeof pack_path, "%s", argv[2]);

	if (pack_path[0] == 0)
		die("%s: no pack (directive 'pack' or second argument).", scenario_name);

	if (end_tick < 0)
		end_tick = step_count > 0 ? steps[step_count - 1].tick : 0;

	pack_data = read_file(pack_path, &pack_size);

	if (amb_pack_open(&pack, pack_data, pack_size) != AMB_OK)
		die("%s is not a valid pack.", pack_path);

	load_symbols(&pack);
	load_layout(&pack);

	for (i = 0; i < pack.header.toc_count; i++)
	{
		amb_pack_entry entry;

		amb_pack_entry_at(&pack, i, &entry);

		if (entry.type == AMB_CHUNK_MAP)
			load_map(&pack, entry.id);

		if (entry.type == AMB_CHUNK_SCREEN)
			load_screen(&pack, entry.id);
	}

	groups = get_chunk(&pack, AMB_CHUNK_SCRIPTS, 0, &groups_size);
	bindings = get_chunk(&pack, AMB_CHUNK_BINDINGS, 0, &bindings_size);

	if (amb_script_init(&global_script, groups, groups == NULL ? 0 : groups_size, bindings, bindings == NULL ? 0 : bindings_size) != 0)
		die("the global scripts are truncated");

	interp = (amb_interp *)malloc(sizeof(amb_interp));
	memset(&host, 0, sizeof host);
	memset(host.waiting, -1, sizeof host.waiting);
	host.interp = interp;
	host.map_id = -1;
	callbacks.user = NULL;
	callbacks.execute = host_execute;
	callbacks.evaluate = host_evaluate;
	callbacks.trace = print_line;

	if (amb_init(interp, &callbacks, &global_script, pack.header.global_flags, pack.header.global_vars, pack.header.global_vars32, pack.header.max_threads, pack.header.max_chain_steps, pack.header.max_pending_events) != 0)
		die("the global state does not fit into the tables of the runtime");

	if (map_name[0] != 0)
	{
		for (i = 0; i < map_count; i++)
		{
			if (strcmp(maps[i].name, map_name) == 0)
				map = &maps[i];
		}

		if (map == NULL)
			die("%s: the map '%s' does not exist.", scenario_name, map_name);

		host.map_id = map->id;
		current_map = map;
	}

	amb_set_random(interp, (uint32_t)seed);

	if (map != NULL && amb_load_map(interp, map->id, &map->script, map->flags, map->vars, map->vars32) == NULL)
		die("the map '%s' does not fit into the tables of the runtime", map->name);

	for (tick = 0; tick <= end_tick; tick++)
	{
		while (next < step_count && steps[next].tick == tick)
			execute_step(&steps[next++]);

		amb_tick(interp);
	}

	do_hash();
	(void)size;
	(void)scenario_size;

	return failures == 0 ? 0 : 1;
}
