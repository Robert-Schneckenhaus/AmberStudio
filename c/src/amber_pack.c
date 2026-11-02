#include "amber_pack.h"

uint16_t amb_be16(const uint8_t *p)
{
	return (uint16_t)((p[0] << 8) | p[1]);
}

uint32_t amb_be32(const uint8_t *p)
{
	return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

uint16_t amb_crc16(const uint8_t *data, uint32_t size)
{
	uint16_t crc = 0xFFFF;
	uint32_t i;
	int bit;

	for (i = 0; i < size; i++)
	{
		crc ^= (uint16_t)(data[i] << 8);

		for (bit = 0; bit < 8; bit++)
			crc = (uint16_t)((crc & 0x8000) ? (crc << 1) ^ 0x1021 : (crc << 1));
	}

	return crc;
}

uint32_t amb_crc32_start(void)
{
	return 0xFFFFFFFFu;
}

uint32_t amb_crc32_add(uint32_t crc, const uint8_t *data, uint32_t size)
{
	uint32_t i;
	int bit;

	for (i = 0; i < size; i++)
	{
		crc ^= data[i];

		for (bit = 0; bit < 8; bit++)
			crc = (crc & 1) ? (crc >> 1) ^ 0xEDB88320u : (crc >> 1);
	}

	return crc;
}

uint32_t amb_crc32_finish(uint32_t crc)
{
	return crc ^ 0xFFFFFFFFu;
}

static void read_entry(const uint8_t *p, amb_pack_entry *entry)
{
	entry->type = amb_be16(p);
	entry->id = amb_be16(p + 2);
	entry->offset = amb_be32(p + 4);
	entry->packed_size = amb_be32(p + 8);
	entry->unpacked_size = amb_be32(p + 12);
	entry->compression = amb_be16(p + 16);
	entry->crc16 = amb_be16(p + 18);
}

int amb_pack_open(amb_pack *pack, const uint8_t *data, uint32_t size)
{
	amb_pack_header *h = &pack->header;
	uint32_t toc_end;
	int i;

	if (size < AMB_HEADER_SIZE || data[0] != 'A' || data[1] != 'M' || data[2] != 'B' || data[3] != 'P')
		return AMB_ERR_FORMAT;

	h->format_version = amb_be16(data + 4);
	h->profile = amb_be16(data + 6);
	h->flags = amb_be16(data + 8);
	h->toc_count = amb_be16(data + 10);
	h->toc_offset = amb_be32(data + 12);
	h->layout_hash = amb_be32(data + 16);
	h->max_threads = amb_be16(data + 20);
	h->max_chain_steps = amb_be16(data + 22);
	h->max_screen_depth = amb_be16(data + 24);
	h->max_pending_events = amb_be16(data + 26);
	h->global_flags = amb_be16(data + 28);
	h->global_vars = amb_be16(data + 30);
	h->global_vars32 = amb_be16(data + 32);
	h->native_count = amb_be16(data + 34);

	if (h->format_version != 0 || (h->toc_offset % 4) != 0 || h->toc_offset < AMB_HEADER_SIZE)
		return AMB_ERR_FORMAT;

	toc_end = h->toc_offset + (uint32_t)h->toc_count * AMB_ENTRY_SIZE;

	if (toc_end > size || toc_end < h->toc_offset)
		return AMB_ERR_FORMAT;

	pack->data = data;
	pack->size = size;

	for (i = 0; i < h->toc_count; i++)
	{
		amb_pack_entry entry;

		read_entry(data + h->toc_offset + (uint32_t)i * AMB_ENTRY_SIZE, &entry);

		if ((entry.offset % 4) != 0 || entry.offset < AMB_HEADER_SIZE || entry.offset > h->toc_offset || entry.packed_size > h->toc_offset - entry.offset)
			return AMB_ERR_FORMAT;
	}

	return AMB_OK;
}

int amb_pack_entry_at(const amb_pack *pack, int index, amb_pack_entry *entry)
{
	if (index < 0 || index >= pack->header.toc_count)
		return AMB_ERR_NOT_FOUND;

	read_entry(pack->data + pack->header.toc_offset + (uint32_t)index * AMB_ENTRY_SIZE, entry);

	return AMB_OK;
}

int amb_pack_find(const amb_pack *pack, uint16_t type, uint16_t id, amb_pack_entry *entry)
{
	int low = 0;
	int high = (int)pack->header.toc_count - 1;

	while (low <= high)
	{
		int middle = (low + high) / 2;
		amb_pack_entry candidate;

		read_entry(pack->data + pack->header.toc_offset + (uint32_t)middle * AMB_ENTRY_SIZE, &candidate);

		if (candidate.type == type && candidate.id == id)
		{
			*entry = candidate;

			return AMB_OK;
		}

		if (candidate.type < type || (candidate.type == type && candidate.id < id))
			low = middle + 1;
		else
			high = middle - 1;
	}

	return AMB_ERR_NOT_FOUND;
}

/* RLE0: a zero byte is followed by the number of further zeros */
static int unpack_rle0(const uint8_t *packed, uint32_t packed_size, uint8_t *out, uint32_t out_size)
{
	uint32_t i = 0;
	uint32_t n = 0;

	while (i < packed_size)
	{
		if (packed[i] != 0)
		{
			if (n >= out_size)
				return AMB_ERR_COMPRESSION;

			out[n++] = packed[i++];
		}
		else
		{
			uint32_t count;

			if (i + 1 >= packed_size)
				return AMB_ERR_COMPRESSION;

			count = (uint32_t)packed[i + 1] + 1;
			i += 2;

			if (n + count > out_size)
				return AMB_ERR_COMPRESSION;

			while (count--)
				out[n++] = 0;
		}
	}

	return n == out_size ? AMB_OK : AMB_ERR_COMPRESSION;
}

int amb_pack_get(const amb_pack *pack, uint16_t type, uint16_t id, uint8_t *scratch, uint32_t scratch_size, const uint8_t **out, uint32_t *out_size)
{
	amb_pack_entry entry;
	const uint8_t *packed;
	int status;

	status = amb_pack_find(pack, type, id, &entry);

	if (status != AMB_OK)
		return status;

	packed = pack->data + entry.offset;

	if (amb_crc16(packed, entry.packed_size) != entry.crc16)
		return AMB_ERR_CRC;

	switch (entry.compression)
	{
		case AMB_COMPRESSION_NONE:
			if (entry.packed_size != entry.unpacked_size)
				return AMB_ERR_FORMAT;

			*out = packed;
			*out_size = entry.packed_size;

			return AMB_OK;
		case AMB_COMPRESSION_RLE0:
			if (entry.unpacked_size > scratch_size)
				return AMB_ERR_SPACE;

			status = unpack_rle0(packed, entry.packed_size, scratch, entry.unpacked_size);

			if (status != AMB_OK)
				return status;

			*out = scratch;
			*out_size = entry.unpacked_size;

			return AMB_OK;
		default:
			return AMB_ERR_COMPRESSION;
	}
}
