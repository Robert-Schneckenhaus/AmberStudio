#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "amber_pack.h"
#include "amber_rt.h"

#define PHASE_ENTER 0
#define PHASE_NEXT_RULE 1
#define PHASE_RUN_ACTIONS 2

#define CHANGE_SET 0
#define CHANGE_CLEAR 1
#define CHANGE_TOGGLE 2

typedef struct rule_header
{
	int condition_words;
	int action_words;
	uint16_t next;
	uint32_t condition_offset;
	uint32_t action_offset;
	uint32_t next_rule_offset;
} rule_header;

typedef struct binding
{
	unsigned trigger;
	unsigned scope;
	uint16_t group;
	uint16_t p1;
	uint16_t p2;
	uint16_t sx;
	uint16_t sy;
	uint16_t sw;
	uint16_t sh;
} binding;

static void trace(amb_interp *in, const char *format, ...)
{
	char line[192];
	int used;
	va_list arguments;

	if (in->host.trace == NULL)
		return;

	used = snprintf(line, sizeof line, "tick=%lld ", in->ticks);
	va_start(arguments, format);
	vsnprintf(line + used, sizeof line - (size_t)used, format, arguments);
	va_end(arguments);
	in->host.trace(in->host.user, line);
}

static const char *kind_name(int kind)
{
	return kind == AMB_KIND_GLOBAL ? "Global" : kind == AMB_KIND_MAP ? "Map" : "Screen";
}

static void state_init(amb_state *state, int flags, int vars, int vars32)
{
	memset(state, 0, sizeof *state);
	state->flags = (uint16_t)flags;
	state->vars = (uint16_t)vars;
	state->vars32 = (uint16_t)vars32;
}

static int state_fits(int flags, int vars, int vars32)
{
	return flags >= 0 && vars >= 0 && vars32 >= 0 && (flags + 7) / 8 <= AMB_MAX_FLAG_BYTES && vars <= AMB_MAX_VARS && vars32 <= AMB_MAX_VARS32;
}

int amb_flag(const amb_state *state, int index)
{
	return (state->flag_bytes[index >> 3] & (1 << (index & 7))) != 0;
}

/* sets a flag and returns 1 if the value changed */
static int set_flag(amb_state *state, int index, int value)
{
	if (amb_flag(state, index) == value)
		return 0;

	if (value)
		state->flag_bytes[index >> 3] |= (uint8_t)(1 << (index & 7));
	else
		state->flag_bytes[index >> 3] &= (uint8_t)~(1 << (index & 7));

	return 1;
}

int amb_script_init(amb_script *script, const uint8_t *groups, uint32_t groups_size, const uint8_t *bindings, uint32_t bindings_size)
{
	script->groups = groups;
	script->groups_size = groups_size;
	script->bindings = bindings;
	script->bindings_size = bindings_size;

	if (groups_size != 0 && (groups_size < 4 || groups_size < 4 + (uint32_t)amb_be16(groups) * 4))
		return -1;

	if (bindings_size != 0 && (bindings_size < 4 || bindings_size < 4 + (uint32_t)amb_be16(bindings) * 16))
		return -1;

	return 0;
}

static int chunk_init(amb_chunk *chunk, int key, int kind, int id, const amb_script *script, int flags, int vars, int vars32)
{
	if (!state_fits(flags, vars, vars32))
		return -1;

	memset(chunk, 0, sizeof *chunk);
	chunk->used = 1;
	chunk->key = key;
	chunk->kind = kind;
	chunk->id = id;
	chunk->script = *script;
	chunk->group_count = script->groups_size == 0 ? 0 : amb_be16(script->groups);
	chunk->binding_count = script->bindings_size == 0 ? 0 : amb_be16(script->bindings);
	state_init(&chunk->state, flags, vars, vars32);

	return chunk->binding_count <= AMB_MAX_BINDINGS ? 0 : -1;
}

void amb_trigger_init(amb_trigger *trigger, unsigned type)
{
	memset(trigger, 0, sizeof *trigger);
	trigger->type = type;
	trigger->map_id = -1;
	trigger->x = AMB_NONE;
	trigger->y = AMB_NONE;
	trigger->other_x = AMB_NONE;
	trigger->other_y = AMB_NONE;
	trigger->entity_id = -1;
	trigger->screen_id = -1;
	trigger->node_id = -1;
	trigger->param = AMB_NONE;
}

int amb_init(amb_interp *in, const amb_host *host, const amb_script *global, int flags, int vars, int vars32, int max_threads, int max_chain_steps, int max_events)
{
	memset(in, 0, sizeof *in);
	in->host = *host;
	in->max_threads = max_threads > AMB_MAX_THREADS ? AMB_MAX_THREADS : max_threads;
	in->max_chain_steps = max_chain_steps;
	in->max_events = max_events > AMB_MAX_EVENTS ? AMB_MAX_EVENTS : max_events;
	in->next_key = 1;
	in->random = 0x2545F491u;

	return chunk_init(&in->global, in->next_key++, AMB_KIND_GLOBAL, 0, global, flags, vars, vars32);
}

amb_chunk *amb_find_map(amb_interp *in, int map_id)
{
	int i;

	for (i = 0; i < AMB_MAX_MAPS; i++)
	{
		if (in->maps[i].used && in->maps[i].id == map_id)
			return &in->maps[i];
	}

	return NULL;
}

amb_chunk *amb_load_map(amb_interp *in, int map_id, const amb_script *script, int flags, int vars, int vars32)
{
	amb_chunk *slot = amb_find_map(in, map_id);
	int i;

	for (i = 0; slot == NULL && i < AMB_MAX_MAPS; i++)
	{
		if (!in->maps[i].used)
			slot = &in->maps[i];
	}

	if (slot == NULL || chunk_init(slot, in->next_key++, AMB_KIND_MAP, map_id, script, flags, vars, vars32) != 0)
		return NULL;

	return slot;
}

void amb_unload_map(amb_interp *in, int map_id, int except_thread)
{
	amb_chunk *map = amb_find_map(in, map_id);
	int i;

	for (i = 0; i < in->max_threads; i++)
	{
		if (i != except_thread && in->threads[i].active && in->threads[i].owner_map == map_id)
			in->threads[i].active = 0;
	}

	if (map != NULL)
		map->used = 0;
}

amb_chunk *amb_load_screen(amb_interp *in, int screen_id, const amb_script *script, int flags, int vars, int vars32)
{
	amb_chunk *slot = NULL;
	int i;

	for (i = 0; slot == NULL && i < AMB_MAX_SCREENS; i++)
	{
		if (!in->screens[i].used)
			slot = &in->screens[i];
	}

	if (slot == NULL || chunk_init(slot, in->next_key++, AMB_KIND_SCREEN, screen_id, script, flags, vars, vars32) != 0)
		return NULL;

	return slot;
}

void amb_unload_screen(amb_interp *in, amb_chunk *screen)
{
	int i;

	for (i = 0; i < in->max_threads; i++)
	{
		if (in->threads[i].active && in->threads[i].screen == screen)
			in->threads[i].active = 0;
	}

	screen->used = 0;
}

int amb_active_threads(const amb_interp *in)
{
	int i;
	int count = 0;

	for (i = 0; i < in->max_threads; i++)
		count += in->threads[i].active != 0;

	return count;
}

uint16_t amb_next_random16(amb_interp *in)
{
	in->random ^= in->random << 13;
	in->random ^= in->random >> 17;
	in->random ^= in->random << 5;

	return (uint16_t)(in->random >> 16);
}

void amb_set_random(amb_interp *in, uint32_t state)
{
	in->random = state == 0 ? 1 : state;
}

static uint32_t hash_word(uint32_t crc, uint16_t value)
{
	uint8_t bytes[2];

	bytes[0] = (uint8_t)(value >> 8);
	bytes[1] = (uint8_t)(value & 0xFF);

	return amb_crc32_add(crc, bytes, 2);
}

static uint32_t hash_dword(uint32_t crc, uint32_t value)
{
	return hash_word(hash_word(crc, (uint16_t)(value >> 16)), (uint16_t)(value & 0xFFFF));
}

static uint32_t hash_state(uint32_t crc, const amb_state *state)
{
	int i;

	crc = amb_crc32_add(crc, state->flag_bytes, (uint32_t)(state->flags + 7) / 8);

	for (i = 0; i < state->vars; i++)
		crc = hash_word(crc, (uint16_t)state->var[i]);

	for (i = 0; i < state->vars32; i++)
		crc = hash_dword(crc, (uint32_t)state->var32[i]);

	return crc;
}

uint32_t amb_state_hash(amb_interp *in, int map_id)
{
	uint32_t crc = amb_crc32_start();
	amb_chunk *map = map_id >= 0 ? amb_find_map(in, map_id) : NULL;

	crc = hash_state(crc, &in->global.state);

	if (map != NULL)
		crc = hash_state(crc, &map->state);

	crc = hash_dword(crc, in->random);

	return amb_crc32_finish(crc);
}

void amb_trace_hash(amb_interp *in, int map_id)
{
	trace(in, "hash crc32=0x%08X", (unsigned)amb_state_hash(in, map_id));
}

/* ---- reading the chunks ---------------------------------------------------------------------------------------- */

static int read_binding(const amb_chunk *chunk, int index, binding *out)
{
	const uint8_t *p = chunk->script.bindings + 4 + (uint32_t)index * 16;
	uint16_t first = amb_be16(p);

	out->trigger = first >> 8;
	out->scope = first & 0xFF;
	out->group = amb_be16(p + 2);
	out->p1 = amb_be16(p + 4);
	out->p2 = amb_be16(p + 6);
	out->sx = amb_be16(p + 8);
	out->sy = amb_be16(p + 10);
	out->sw = amb_be16(p + 12);
	out->sh = amb_be16(p + 14);

	return 0;
}

static int read_rule_header(const amb_chunk *chunk, uint32_t rule_offset, rule_header *header)
{
	const uint8_t *groups = chunk->script.groups;
	uint32_t size = chunk->script.groups_size;

	if (rule_offset + 8 > size)
		return -1;

	header->condition_words = amb_be16(groups + rule_offset);
	header->action_words = amb_be16(groups + rule_offset + 2);
	header->next = amb_be16(groups + rule_offset + 4);
	header->condition_offset = rule_offset + 8;
	header->action_offset = header->condition_offset + (uint32_t)header->condition_words * 2;
	header->next_rule_offset = header->action_offset + (uint32_t)header->action_words * 2;

	return header->next_rule_offset <= size ? 0 : -1;
}

/* reads the instruction at the offset: op, length in words, flags and the operands; returns 0 or -1 if it exceeds the chunk */
static int read_instruction(const amb_chunk *chunk, uint32_t offset, uint16_t *operands, unsigned *op, int *length, int *or_next, int *neg)
{
	const uint8_t *groups = chunk->script.groups;
	uint16_t instruction;
	int i;

	if (offset + 2 > chunk->script.groups_size)
		return -1;

	instruction = amb_be16(groups + offset);
	*op = instruction >> 8;
	*length = (instruction >> 2) & 0x3F;
	*or_next = (instruction & 2) != 0;
	*neg = (instruction & 1) != 0;

	if (offset + 2 + (uint32_t)*length * 2 > chunk->script.groups_size)
		return -1;

	for (i = 0; i < *length; i++)
		operands[i] = amb_be16(groups + offset + 2 + (uint32_t)i * 2);

	return 0;
}

/* ---- state access ---------------------------------------------------------------------------------------------- */

static amb_state *find_state(amb_interp *in, const amb_thread *thread, uint16_t slot)
{
	switch (slot >> 14)
	{
		case AMB_NS_GLOBAL:
			return &in->global.state;
		case AMB_NS_MAP:
		{
			amb_chunk *map = thread->owner_map >= 0 ? amb_find_map(in, thread->owner_map) : NULL;

			return map == NULL ? NULL : &map->state;
		}
		case AMB_NS_SCREEN:
			return thread->screen == NULL ? NULL : &thread->screen->state;
		default:
			return NULL;
	}
}

/* the screen a change of a screen slot belongs to, else -1 (reactive events of screens carry it) */
static int screen_key_of(const amb_thread *thread, uint16_t slot)
{
	return (slot >> 14) == AMB_NS_SCREEN && thread->screen != NULL ? thread->screen->key : -1;
}

static int get_var(amb_interp *in, const amb_thread *thread, uint16_t slot, int16_t *value)
{
	int index = slot & 0x3FFF;
	amb_state *state;

	if ((slot >> 14) == AMB_NS_THREAD)
	{
		if (index >= 8)
			return 0;

		*value = thread->locals[index];

		return 1;
	}

	state = find_state(in, thread, slot);

	if (state == NULL || index >= state->vars)
		return 0;

	*value = state->var[index];

	return 1;
}

static int compare(long long left, uint16_t comparison, long long right)
{
	switch (comparison)
	{
		case AMB_CMP_EQUAL: return left == right;
		case AMB_CMP_NOT_EQUAL: return left != right;
		case AMB_CMP_LESS: return left < right;
		case AMB_CMP_LESS_OR_EQUAL: return left <= right;
		case AMB_CMP_GREATER: return left > right;
		case AMB_CMP_GREATER_OR_EQUAL: return left >= right;
		default: return 0;
	}
}

static int16_t saturate(long value)
{
	return (int16_t)(value < -32768 ? -32768 : value > 32767 ? 32767 : value);
}

static amb_thread_ctx context_of(const amb_thread *thread, int thread_id)
{
	amb_thread_ctx context;

	context.thread_id = thread_id;
	context.owner_map = thread->owner_map;
	context.trigger_x = thread->x;
	context.trigger_y = thread->y;
	context.trigger_arg = thread->arg;
	context.result = thread->result;
	context.screen_key = thread->screen != NULL ? thread->screen->key : -1;

	return context;
}

/* ---- events ---------------------------------------------------------------------------------------------------- */

static void enqueue(amb_interp *in, unsigned type, uint16_t slot, int value, int map_id, int screen_key)
{
	amb_event *event;

	if (in->event_count >= in->max_events)
	{
		trace(in, "drop event %s (queue full)", amb_trigger_name(type));

		return;
	}

	event = &in->events[(in->event_head + in->event_count) % AMB_MAX_EVENTS];
	event->type = type;
	event->slot = slot;
	event->value = value;
	event->map_id = map_id;
	event->screen_key = screen_key;
	in->event_count++;
}

/* ---- threads --------------------------------------------------------------------------------------------------- */

static void advance(amb_interp *in, int thread_id);

static int start_thread(amb_interp *in, amb_chunk *chunk, int key, uint16_t group, const char *description, uint16_t x, uint16_t y, uint32_t arg, int owner_map)
{
	int free_slot = -1;
	int i;
	amb_thread *thread;

	for (i = 0; i < in->max_threads; i++)
	{
		if (in->threads[i].active && in->threads[i].binding_key == key)
		{
			trace(in, "skip %s (already running)", description);

			return 0;
		}

		if (free_slot < 0 && !in->threads[i].active)
			free_slot = i;
	}

	if (free_slot < 0)
	{
		trace(in, "drop %s (no free thread)", description);

		return 0;
	}

	thread = &in->threads[free_slot];
	memset(thread, 0, sizeof *thread);
	thread->active = 1;
	thread->phase = PHASE_ENTER;
	thread->home = chunk;
	thread->current = chunk;
	thread->owner_map = chunk->kind == AMB_KIND_MAP ? chunk->id : owner_map;
	thread->screen = chunk->kind == AMB_KIND_SCREEN ? chunk : NULL;
	thread->group = group;
	thread->arg = arg;
	thread->x = x;
	thread->y = y;
	thread->binding_key = key;

	trace(in, "%s thread=%d", description, free_slot);
	advance(in, free_slot);

	return 1;
}

static int start_binding_thread(amb_interp *in, amb_chunk *chunk, int binding_index, const binding *b, uint16_t x, uint16_t y, uint32_t arg, int owner_map)
{
	char description[96];

	snprintf(description, sizeof description, "start %s chunk=%s:%d binding=%d", amb_trigger_name(b->trigger), kind_name(chunk->kind), chunk->id, binding_index);

	return start_thread(in, chunk, chunk->key * 4096 + binding_index, b->group, description, x, y, arg, owner_map);
}

int amb_run_group(amb_interp *in, amb_chunk *chunk, uint16_t group, uint32_t arg, int owner_map)
{
	char description[64];

	snprintf(description, sizeof description, "run group %04X chunk=%s:%d", (unsigned)group, kind_name(chunk->kind), chunk->id);

	return start_thread(in, chunk, chunk->key * 4096 + 2048 + (group & 0x7FFF), group, description, AMB_NONE, AMB_NONE, arg, owner_map);
}

static int inside(const binding *b, uint16_t x, uint16_t y)
{
	if (x == AMB_NONE || y == AMB_NONE)
		return 0;

	return x >= b->sx && x < b->sx + b->sw && y >= b->sy && y < b->sy + b->sh;
}

static int matches(const binding *b, const amb_trigger *t)
{
	switch (b->scope)
	{
		case AMB_SCOPE_TILE:
			if (t->x != b->sx || t->y != b->sy)
				return 0;

			break;
		case AMB_SCOPE_AREA:
			if (b->trigger == AMB_TRIG_ENTER_TILE || b->trigger == AMB_TRIG_LEAVE_TILE)
			{
				if (!inside(b, t->x, t->y) || inside(b, t->other_x, t->other_y))
					return 0;
			}
			else if (!inside(b, t->x, t->y))
			{
				return 0;
			}

			break;
		case AMB_SCOPE_ENTITY:
			if (t->entity_id != (int)b->sx)
				return 0;

			break;
		case AMB_SCOPE_SCREEN:
			if (t->screen_id != (int)b->sx)
				return 0;

			break;
		case AMB_SCOPE_NODE:
			if (t->node_id != (int)b->sx)
				return 0;

			break;
		default:
			break;
	}

	switch (b->trigger)
	{
		case AMB_TRIG_SEE_PARTY:
			return t->param <= b->p1;
		case AMB_TRIG_CLICK:
		case AMB_TRIG_REGION_CLICK:
			return b->p1 == AMB_NONE || (b->p1 & t->param) != 0;
		case AMB_TRIG_USE_ITEM:
		case AMB_TRIG_CAST_SPELL:
		case AMB_TRIG_BATTLE_END:
		case AMB_TRIG_ITEM_GAINED:
		case AMB_TRIG_MEMBER_JOINED:
		case AMB_TRIG_MEMBER_LEFT:
		case AMB_TRIG_WEATHER_CHANGE:
		case AMB_TRIG_HOUR:
		case AMB_TRIG_KEY:
			return b->p1 == AMB_NONE || b->p1 == t->param;
		default:
			return 1;
	}
}

static int dispatch(amb_interp *in, amb_chunk *chunk, const amb_trigger *t, int owner_map)
{
	int started = 0;
	int i;

	for (i = 0; i < chunk->binding_count; i++)
	{
		binding b;

		read_binding(chunk, i, &b);

		if (b.trigger == t->type && matches(&b, t) && start_binding_thread(in, chunk, i, &b, t->x, t->y, t->arg, owner_map))
			started++;
	}

	return started;
}

int amb_trigger_event(amb_interp *in, const amb_trigger *trigger)
{
	int started = dispatch(in, &in->global, trigger, trigger->map_id);

	if (trigger->map_id >= 0)
	{
		amb_chunk *map = amb_find_map(in, trigger->map_id);

		if (map != NULL)
			started += dispatch(in, map, trigger, trigger->map_id);
	}

	if (trigger->screen_id >= 0)
	{
		int i;

		for (i = 0; i < AMB_MAX_SCREENS; i++)
		{
			if (in->screens[i].used && in->screens[i].id == trigger->screen_id)
				started += dispatch(in, &in->screens[i], trigger, trigger->map_id);
		}
	}

	return started;
}

static void dispatch_reactive_in(amb_interp *in, amb_chunk *chunk, const amb_event *event)
{
	int i;

	for (i = 0; i < chunk->binding_count; i++)
	{
		binding b;

		read_binding(chunk, i, &b);

		if (b.trigger != event->type || b.p1 != event->slot)
			continue;

		if (b.trigger == AMB_TRIG_FLAG_CHANGED)
		{
			int mode_matches = b.p2 == 0 || (b.p2 == 1 && event->value != 0) || (b.p2 == 2 && event->value == 0);

			if (!mode_matches)
				continue;
		}

		start_binding_thread(in, chunk, i, &b, AMB_NONE, AMB_NONE, (uint32_t)(int32_t)event->value, event->map_id);
	}
}

static void dispatch_reactive(amb_interp *in, const amb_event *event)
{
	dispatch_reactive_in(in, &in->global, event);

	if (event->map_id >= 0)
	{
		amb_chunk *map = amb_find_map(in, event->map_id);

		if (map != NULL)
			dispatch_reactive_in(in, map, event);
	}

	if (event->screen_key >= 0)
	{
		int i;

		for (i = 0; i < AMB_MAX_SCREENS; i++)
		{
			if (in->screens[i].used && in->screens[i].key == event->screen_key)
				dispatch_reactive_in(in, &in->screens[i], event);
		}
	}
}

static void run_map_ticks(amb_interp *in, amb_chunk *map)
{
	int i;

	for (i = 0; i < map->binding_count; i++)
	{
		binding b;

		read_binding(map, i, &b);

		if (b.trigger != AMB_TRIG_MAP_TICK || b.p1 == 0)
			continue;

		if (++map->tick_counters[i] >= b.p1)
		{
			map->tick_counters[i] = 0;
			start_binding_thread(in, map, i, &b, AMB_NONE, AMB_NONE, 0, map->id);
		}
	}
}

void amb_tick(amb_interp *in)
{
	int pending;
	int i;

	in->ticks++;
	pending = in->event_count;

	for (i = 0; i < pending; i++)
	{
		amb_event event = in->events[in->event_head];

		in->event_head = (in->event_head + 1) % AMB_MAX_EVENTS;
		in->event_count--;
		dispatch_reactive(in, &event);
	}

	for (i = 0; i < AMB_MAX_MAPS; i++)
	{
		if (in->maps[i].used)
			run_map_ticks(in, &in->maps[i]);
	}

	for (i = 0; i < in->max_threads; i++)
	{
		amb_thread *thread = &in->threads[i];

		if (thread->active && thread->waiting && thread->wait_ticks > 0 && --thread->wait_ticks == 0)
			amb_resume(in, i, 0);
	}
}

void amb_resume(amb_interp *in, int thread_id, int16_t result)
{
	amb_thread *thread;

	if (thread_id < 0 || thread_id >= in->max_threads)
		return;

	thread = &in->threads[thread_id];

	if (!thread->active || !thread->waiting)
		return;

	thread->result = result;
	thread->waiting = 0;
	thread->wait_ticks = 0;

	trace(in, "resume thread=%d result=%d", thread_id, (int)result);
	advance(in, thread_id);
}

/* ---- running rules --------------------------------------------------------------------------------------------- */

static void finish(amb_interp *in, int thread_id)
{
	amb_thread *thread = &in->threads[thread_id];

	if (thread->autosave && thread->active)
	{
		amb_thread_ctx context = context_of(thread, thread_id);

		in->host.execute(in->host.user, AMB_ACT_AUTOSAVE, NULL, 0, &context);
		thread->autosave = 0;
	}

	if (thread->active)
		trace(in, "end thread=%d", thread_id);

	thread->active = 0;
}

static int fault(amb_interp *in, amb_thread *thread, const char *format, unsigned value)
{
	char message[96];

	snprintf(message, sizeof message, format, value);
	trace(in, "fault: %s", message);
	thread->active = 0;

	return AMB_DONE;
}

static int change_flag(amb_interp *in, amb_thread *thread, uint16_t slot, int change)
{
	amb_state *state = find_state(in, thread, slot);
	int index = slot & 0x3FFF;
	int value;

	if (state == NULL || index >= state->flags)
		return fault(in, thread, "invalid flag slot %04X", slot);

	value = change == CHANGE_SET ? 1 : change == CHANGE_CLEAR ? 0 : !amb_flag(state, index);

	if (set_flag(state, index, value))
		enqueue(in, AMB_TRIG_FLAG_CHANGED, slot, value, thread->owner_map, screen_key_of(thread, slot));

	return AMB_DONE;
}

static int change_var(amb_interp *in, amb_thread *thread, uint16_t slot, int16_t value, int relative)
{
	int index = slot & 0x3FFF;
	amb_state *state;
	int16_t result;

	if ((slot >> 14) == AMB_NS_THREAD)
	{
		if (index >= 8)
			return fault(in, thread, "invalid thread variable %u", (unsigned)index);

		thread->locals[index] = relative ? saturate((long)thread->locals[index] + value) : value;

		return AMB_DONE;
	}

	state = find_state(in, thread, slot);

	if (state == NULL || index >= state->vars)
		return fault(in, thread, "invalid variable slot %04X", slot);

	result = relative ? saturate((long)state->var[index] + value) : value;

	if (state->var[index] != result)
	{
		state->var[index] = result;
		enqueue(in, AMB_TRIG_VAR_CHANGED, slot, result, thread->owner_map, screen_key_of(thread, slot));
	}

	return AMB_DONE;
}

static int change_var32(amb_interp *in, amb_thread *thread, uint16_t slot, int32_t value, int relative)
{
	amb_state *state = find_state(in, thread, slot);
	int index = slot & 0x3FFF;
	long long result;

	if (state == NULL || index >= state->vars32)
		return fault(in, thread, "invalid 32 bit variable slot %04X", slot);

	result = relative ? (long long)state->var32[index] + value : value;
	state->var32[index] = (int32_t)(result < -2147483647LL - 1 ? -2147483647LL - 1 : result > 2147483647LL ? 2147483647LL : result);

	return AMB_DONE;
}

static int execute_action(amb_interp *in, int thread_id, amb_thread *thread, unsigned op, const uint16_t *operands, int count)
{
	amb_thread_ctx context;
	int outcome;

	switch (op)
	{
		case AMB_ACT_SET_FLAG:
			return change_flag(in, thread, operands[0], CHANGE_SET);
		case AMB_ACT_CLEAR_FLAG:
			return change_flag(in, thread, operands[0], CHANGE_CLEAR);
		case AMB_ACT_TOGGLE_FLAG:
			return change_flag(in, thread, operands[0], CHANGE_TOGGLE);
		case AMB_ACT_SET_VAR:
			return change_var(in, thread, operands[0], (int16_t)operands[1], 0);
		case AMB_ACT_ADD_VAR:
			return change_var(in, thread, operands[0], (int16_t)operands[1], 1);
		case AMB_ACT_SET_VAR32:
			return change_var32(in, thread, operands[0], (int32_t)(((uint32_t)operands[1] << 16) | operands[2]), 0);
		case AMB_ACT_ADD_VAR32:
			return change_var32(in, thread, operands[0], (int32_t)(((uint32_t)operands[1] << 16) | operands[2]), 1);
		case AMB_ACT_COPY_VAR:
		{
			int16_t value;

			if (!get_var(in, thread, operands[1], &value))
				return fault(in, thread, "invalid slot %04X", operands[1]);

			return change_var(in, thread, operands[0], value, 0);
		}
		case AMB_ACT_RAISE:
			enqueue(in, AMB_TRIG_CUSTOM, operands[0], (int16_t)operands[1], thread->owner_map, -1);

			return AMB_DONE;
		case AMB_ACT_WAIT:
			thread->wait_ticks = operands[0] < 1 ? 1 : operands[0];
			trace(in, "act wait ticks=%d", thread->wait_ticks);

			return AMB_BLOCKED;
		case AMB_ACT_AUTOSAVE:
			thread->autosave = 1;

			return AMB_DONE;
		default:
			break;
	}

	context = context_of(thread, thread_id);
	outcome = in->host.execute(in->host.user, op, operands, count, &context);

	trace(in, outcome == AMB_BLOCKED ? "act %s blocked" : "act %s", amb_action_name(op));

	/* push_screen with the nowait flag never blocks */
	if ((op == AMB_ACT_PUSH_SCREEN || op == AMB_ACT_REPLACE_SCREEN) && count > 1 && (operands[1] & 1) != 0)
		return AMB_DONE;

	return outcome;
}

/* returns 0 if the thread blocked or ended */
static int run_actions(amb_interp *in, int thread_id)
{
	amb_thread *thread = &in->threads[thread_id];
	uint16_t operands[AMB_MAX_OPERANDS];

	while (thread->action_offset < thread->action_end)
	{
		unsigned op;
		int length;
		int or_next;
		int neg;
		int outcome;

		if (read_instruction(thread->current, thread->action_offset, operands, &op, &length, &or_next, &neg) != 0)
		{
			trace(in, "fault: instruction exceeds the chunk");
			thread->active = 0;

			return 0;
		}

		thread->action_offset += 2 + (uint32_t)length * 2;
		outcome = execute_action(in, thread_id, thread, op, operands, length);

		if (!thread->active)
			return 0;

		if (outcome == AMB_BLOCKED)
		{
			thread->waiting = 1;

			return 0;
		}
	}

	return 1;
}

static int evaluate_condition(amb_interp *in, int thread_id, amb_thread *thread, unsigned op, const uint16_t *operands, int count)
{
	amb_thread_ctx context;

	switch (op)
	{
		case AMB_COND_FLAG:
		{
			amb_state *state = find_state(in, thread, operands[0]);
			int index = operands[0] & 0x3FFF;

			return state != NULL && index < state->flags && amb_flag(state, index);
		}
		case AMB_COND_VAR:
		{
			int16_t value;

			return get_var(in, thread, operands[0], &value) && compare(value, operands[1], (int16_t)operands[2]);
		}
		case AMB_COND_VAR32:
		{
			amb_state *state = find_state(in, thread, operands[0]);
			int index = operands[0] & 0x3FFF;

			return state != NULL && index < state->vars32 && compare(state->var32[index], operands[1], (int32_t)(((uint32_t)operands[2] << 16) | operands[3]));
		}
		case AMB_COND_VAR_VAR:
		{
			int16_t a;
			int16_t b;

			return get_var(in, thread, operands[0], &a) && get_var(in, thread, operands[2], &b) && compare(a, operands[1], b);
		}
		case AMB_COND_RESULT:
			return compare(thread->result, operands[0], (int16_t)operands[1]);
		case AMB_COND_ARG:
			return compare((int32_t)thread->arg, operands[0], (int32_t)(((uint32_t)operands[1] << 16) | operands[2]));
		case AMB_COND_CHANCE:
			return ((uint32_t)amb_next_random16(in) * 100u) >> 16 < operands[0];
		default:
			break;
	}

	context = context_of(thread, thread_id);

	return in->host.evaluate(in->host.user, op, operands, count, &context);
}

static int evaluate_conditions(amb_interp *in, int thread_id, const rule_header *header)
{
	amb_thread *thread = &in->threads[thread_id];
	uint16_t operands[AMB_MAX_OPERANDS];
	uint32_t offset = header->condition_offset;
	int clause_true = 0;

	while (offset < header->action_offset)
	{
		unsigned op;
		int length;
		int or_next;
		int neg;
		int value;

		if (read_instruction(thread->current, offset, operands, &op, &length, &or_next, &neg) != 0)
			return 0;

		offset += 2 + (uint32_t)length * 2;
		value = evaluate_condition(in, thread_id, thread, op, operands, length) ^ neg;
		clause_true |= value;

		if (!or_next)
		{
			if (!clause_true)
				return 0;

			clause_true = 0;
		}
	}

	return 1;
}

static int enter_group(amb_interp *in, amb_thread *thread)
{
	const amb_chunk *chunk;
	int index;
	uint32_t offset;
	uint16_t first;

	if (++thread->steps > in->max_chain_steps)
	{
		trace(in, "abort thread: chain longer than %d steps", in->max_chain_steps);

		return 0;
	}

	chunk = (thread->group != AMB_NONE && (thread->group & 0x8000)) ? thread->current : &in->global;
	index = thread->group & 0x7FFF;

	if (index >= chunk->group_count)
	{
		trace(in, "abort thread: group %d does not exist in %s:%d", index, kind_name(chunk->kind), chunk->id);

		return 0;
	}

	offset = amb_be32(chunk->script.groups + 4 + (uint32_t)index * 4);

	if ((offset & 1) != 0 || offset + 4 > chunk->script.groups_size)
	{
		trace(in, "abort thread: group %d has an invalid offset", index);

		return 0;
	}

	first = amb_be16(chunk->script.groups + offset);
	thread->current = (amb_chunk *)chunk;
	thread->mode = first >> 8;
	thread->rule_count = first & 0xFF;
	thread->rule_index = 0;
	thread->rule_offset = offset + 4;

	return 1;
}

static void advance(amb_interp *in, int thread_id)
{
	amb_thread *thread = &in->threads[thread_id];

	while (thread->active && !thread->waiting)
	{
		switch (thread->phase)
		{
			case PHASE_ENTER:
				if (!enter_group(in, thread))
				{
					finish(in, thread_id);

					return;
				}

				thread->phase = PHASE_NEXT_RULE;

				break;
			case PHASE_NEXT_RULE:
			{
				rule_header header;

				if (thread->rule_index >= thread->rule_count)
				{
					finish(in, thread_id);

					return;
				}

				if (read_rule_header(thread->current, thread->rule_offset, &header) != 0)
				{
					trace(in, "fault: rule exceeds the chunk");
					thread->active = 0;

					return;
				}

				if (evaluate_conditions(in, thread_id, &header))
				{
					thread->action_offset = header.action_offset;
					thread->action_end = header.next_rule_offset;
					thread->next = header.next;
					thread->phase = PHASE_RUN_ACTIONS;
				}
				else
				{
					thread->rule_offset = header.next_rule_offset;
					thread->rule_index++;
				}

				break;
			}
			case PHASE_RUN_ACTIONS:
			{
				if (!run_actions(in, thread_id))
					return;

				if (thread->mode == AMB_MODE_FIRST)
				{
					if (thread->next != AMB_NONE)
					{
						thread->group = thread->next;
						thread->phase = PHASE_ENTER;
					}
					else
					{
						finish(in, thread_id);

						return;
					}
				}
				else
				{
					rule_header header;

					if (read_rule_header(thread->current, thread->rule_offset, &header) != 0)
					{
						thread->active = 0;

						return;
					}

					thread->rule_offset = header.next_rule_offset;
					thread->rule_index++;
					thread->phase = PHASE_NEXT_RULE;
				}

				break;
			}
			default:
				thread->active = 0;

				return;
		}
	}
}
