/*
 * Amber rule interpreter (spec section 2): the C counterpart of Amber.Runtime.Interpreter. Portable C99 for the desktop and the
 * Amiga: no allocation, fixed tables (see the AMB_MAX_ constants), big endian chunks read word by word.
 *
 * Screen instances (load_screen, run_group, the screen triggers) are included; their bindings can only use the screen triggers
 * (screen_open, screen_close, screen_resume, click, hover, key), so the reactive events of screens are only relevant for a future compiler.
 */
#ifndef AMBER_RT_H
#define AMBER_RT_H

#include <stdint.h>
#include "amber_tables.h"

#define AMB_MAX_THREADS 16
#define AMB_MAX_MAPS 8
#define AMB_MAX_SCREENS 4
#define AMB_MAX_EVENTS 32
#define AMB_MAX_BINDINGS 64
#define AMB_MAX_FLAG_BYTES 128
#define AMB_MAX_VARS 128
#define AMB_MAX_VARS32 32
#define AMB_MAX_OPERANDS 64

#define AMB_NONE 0xFFFF

/* the kinds of chunks, in the order of Amber.Script.Common.ScopeKind */
#define AMB_KIND_GLOBAL 0
#define AMB_KIND_MAP 1
#define AMB_KIND_SCREEN 2

/* the result of an action of the host */
#define AMB_DONE 0
#define AMB_BLOCKED 1

/* flags, variables and 32 bit variables of one namespace instance (global, one map) */
typedef struct amb_state
{
	uint16_t flags;
	uint16_t vars;
	uint16_t vars32;
	uint8_t flag_bytes[AMB_MAX_FLAG_BYTES];
	int16_t var[AMB_MAX_VARS];
	int32_t var32[AMB_MAX_VARS32];
} amb_state;

/* the groups and bindings of a chunk: memory of the pack, big endian (spec sections 3 and 6) */
typedef struct amb_script
{
	const uint8_t *groups;
	uint32_t groups_size;
	const uint8_t *bindings;
	uint32_t bindings_size;
} amb_script;

typedef struct amb_chunk
{
	int used;
	int key;
	int kind;
	int id;
	amb_script script;
	int group_count;
	int binding_count;
	amb_state state;
	int32_t tick_counters[AMB_MAX_BINDINGS];
} amb_chunk;

/* what the host gets with every action and condition */
typedef struct amb_thread_ctx
{
	int thread_id;
	int owner_map;
	uint16_t trigger_x;
	uint16_t trigger_y;
	uint32_t trigger_arg;
	int16_t result;
	int screen_key;
} amb_thread_ctx;

typedef struct amb_host
{
	void *user;
	/* executes an action; returns AMB_DONE or AMB_BLOCKED (the host calls amb_resume later) */
	int (*execute)(void *user, unsigned op, const uint16_t *operands, int count, const amb_thread_ctx *ctx);
	int (*evaluate)(void *user, unsigned op, const uint16_t *operands, int count, const amb_thread_ctx *ctx);
	/* one trace line (spec section 12.3), without a line end; may be NULL */
	void (*trace)(void *user, const char *line);
} amb_host;

/* an event of the host which starts the threads of the matching bindings */
typedef struct amb_trigger
{
	unsigned type;
	int map_id;
	uint16_t x;
	uint16_t y;
	uint16_t other_x;
	uint16_t other_y;
	int entity_id;
	int screen_id;
	int node_id;
	uint16_t param;
	uint32_t arg;
} amb_trigger;

typedef struct amb_thread
{
	int active;
	int waiting;
	int wait_ticks;
	int phase;
	amb_chunk *home;
	amb_chunk *current;
	amb_chunk *screen;
	int owner_map;
	uint16_t group;
	int mode;
	int rule_index;
	int rule_count;
	uint32_t rule_offset;
	uint32_t action_offset;
	uint32_t action_end;
	uint16_t next;
	int16_t result;
	uint32_t arg;
	uint16_t x;
	uint16_t y;
	int steps;
	int binding_key;
	int autosave;
	int16_t locals[8];
} amb_thread;

typedef struct amb_event
{
	unsigned type;
	uint16_t slot;
	int value;
	int map_id;
	int screen_key;
} amb_event;

typedef struct amb_interp
{
	amb_host host;
	int max_threads;
	int max_chain_steps;
	int max_events;
	amb_thread threads[AMB_MAX_THREADS];
	amb_event events[AMB_MAX_EVENTS];
	int event_head;
	int event_count;
	amb_chunk global;
	amb_chunk maps[AMB_MAX_MAPS];
	amb_chunk screens[AMB_MAX_SCREENS];
	int next_key;
	long long ticks;
	uint32_t random;
} amb_interp;

/* a script from the two chunks (either may be empty); returns 0 or -1 if the tables are truncated */
int amb_script_init(amb_script *script, const uint8_t *groups, uint32_t groups_size, const uint8_t *bindings, uint32_t bindings_size);

void amb_trigger_init(amb_trigger *trigger, unsigned type);

/* limits from the pack header; the global state has the given sizes (-1 if they exceed the AMB_MAX_ tables) */
int amb_init(amb_interp *in, const amb_host *host, const amb_script *global, int flags, int vars, int vars32, int max_threads, int max_chain_steps, int max_events);

/* loads a map with fresh state; returns its chunk (to read the state) or NULL */
amb_chunk *amb_load_map(amb_interp *in, int map_id, const amb_script *script, int flags, int vars, int vars32);
amb_chunk *amb_find_map(amb_interp *in, int map_id);
void amb_unload_map(amb_interp *in, int map_id, int except_thread);

/* loads a screen instance with fresh state (a screen can be open twice: every instance has its own key); returns it or NULL */
amb_chunk *amb_load_screen(amb_interp *in, int screen_id, const amb_script *script, int flags, int vars, int vars32);
/* unloads a screen: the threads which belong to it end */
void amb_unload_screen(amb_interp *in, amb_chunk *screen);

/*
 * Runs a group of a loaded chunk directly, for handlers which are not bindings (the on_click, on_open ... groups of a screen
 * definition). The value becomes the trigger argument. Returns 0 if the group is already running or no thread is free.
 */
int amb_run_group(amb_interp *in, amb_chunk *chunk, uint16_t group, uint32_t arg, int owner_map);

/* starts the threads of all matching bindings; returns their number */
int amb_trigger_event(amb_interp *in, const amb_trigger *trigger);

/* continues a blocked thread with the result of the awaited action */
void amb_resume(amb_interp *in, int thread_id, int16_t result);

/* advances the clock by one tick: queued events, map ticks and wait timers */
void amb_tick(amb_interp *in);

int amb_active_threads(const amb_interp *in);

uint16_t amb_next_random16(amb_interp *in);
void amb_set_random(amb_interp *in, uint32_t state);

int amb_flag(const amb_state *state, int index);

/* the state hash of the golden traces: CRC-32 over the global state, the state of the map (if map_id >= 0) and the random state */
uint32_t amb_state_hash(amb_interp *in, int map_id);

void amb_trace_hash(amb_interp *in, int map_id);

#endif
