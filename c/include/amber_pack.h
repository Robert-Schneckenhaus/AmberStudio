/*
 * Amber pack reader (spec section 9): header, table of contents, CRC-16, chunks without or with RLE0 compression.
 * Portable C99 without allocation; the pack is a block of memory the caller provides (a file read into RAM, a ROM image).
 * Deflate chunks (compression 2) are not supported: the Amiga profile of the cook does not write them.
 */
#ifndef AMBER_PACK_H
#define AMBER_PACK_H

#include <stdint.h>

#define AMB_OK 0
#define AMB_ERR_FORMAT (-1)
#define AMB_ERR_NOT_FOUND (-2)
#define AMB_ERR_CRC (-3)
#define AMB_ERR_COMPRESSION (-4)
#define AMB_ERR_SPACE (-5)

#define AMB_CHUNK_SCRIPTS 0x0001
#define AMB_CHUNK_BINDINGS 0x0002
#define AMB_CHUNK_SCREEN 0x0003
#define AMB_CHUNK_MAP 0x0004
#define AMB_CHUNK_TILESET_LOGIC 0x0005
#define AMB_CHUNK_TABLE 0x0006
#define AMB_CHUNK_TEXT 0x0007
#define AMB_CHUNK_NATIVES 0x0008
#define AMB_CHUNK_SYMBOLS 0x0009
#define AMB_CHUNK_LAYOUT 0x000A
#define AMB_CHUNK_WORDS 0x000B

#define AMB_COMPRESSION_NONE 0
#define AMB_COMPRESSION_RLE0 1
#define AMB_COMPRESSION_DEFLATE 2

#define AMB_HEADER_SIZE 40
#define AMB_ENTRY_SIZE 20

typedef struct amb_pack_header
{
	uint16_t format_version;
	uint16_t profile;
	uint16_t flags;
	uint16_t toc_count;
	uint32_t toc_offset;
	uint32_t layout_hash;
	uint16_t max_threads;
	uint16_t max_chain_steps;
	uint16_t max_screen_depth;
	uint16_t max_pending_events;
	uint16_t global_flags;
	uint16_t global_vars;
	uint16_t global_vars32;
	uint16_t native_count;
} amb_pack_header;

typedef struct amb_pack_entry
{
	uint16_t type;
	uint16_t id;
	uint32_t offset;
	uint32_t packed_size;
	uint32_t unpacked_size;
	uint16_t compression;
	uint16_t crc16;
} amb_pack_entry;

typedef struct amb_pack
{
	const uint8_t *data;
	uint32_t size;
	amb_pack_header header;
} amb_pack;

/* big endian reads */
uint16_t amb_be16(const uint8_t *p);
uint32_t amb_be32(const uint8_t *p);

/* CRC-16/CCITT-FALSE (0x1021, start 0xFFFF) and CRC-32 (IEEE, as the state hash of the golden traces) */
uint16_t amb_crc16(const uint8_t *data, uint32_t size);
uint32_t amb_crc32_start(void);
uint32_t amb_crc32_add(uint32_t crc, const uint8_t *data, uint32_t size);
uint32_t amb_crc32_finish(uint32_t crc);

/* Checks the header and the table of contents. The data has to stay valid as long as the pack is used. */
int amb_pack_open(amb_pack *pack, const uint8_t *data, uint32_t size);

/* The table of contents is sorted by type and ID; returns AMB_ERR_NOT_FOUND if there is no such chunk. */
int amb_pack_find(const amb_pack *pack, uint16_t type, uint16_t id, amb_pack_entry *entry);
int amb_pack_entry_at(const amb_pack *pack, int index, amb_pack_entry *entry);

/*
 * The unpacked bytes of a chunk. A chunk without compression is returned as a pointer into the pack (no copy); a compressed
 * one is unpacked into the scratch buffer (AMB_ERR_SPACE if it is too small). The CRC-16 is checked in both cases.
 */
int amb_pack_get(const amb_pack *pack, uint16_t type, uint16_t id, uint8_t *scratch, uint32_t scratch_size, const uint8_t **out, uint32_t *out_size);

#endif
