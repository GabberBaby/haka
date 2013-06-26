
#ifndef _HAKA_PACKET_MODULE_H
#define _HAKA_PACKET_MODULE_H

#include <haka/module.h>
#include <haka/packet.h>
#include <haka/types.h>


typedef enum {
	FILTER_ACCEPT,
	FILTER_DROP
} filter_result;

/* Opaque state structure. */
struct packet_module_state;

struct packet_module {
	struct module    module;

	bool           (*multi_threaded)();
	struct packet_module_state *(*init_state)(int thread_id);
	void           (*cleanup_state)(struct packet_module_state *state);
	int            (*receive)(struct packet_module_state *state, struct packet **pkt);
	void           (*verdict)(struct packet *pkt, filter_result result);
	size_t         (*get_length)(struct packet *pkt);
	uint8         *(*make_modifiable)(struct packet *pkt);
	int            (*resize)(struct packet *pkt, size_t size);
	uint64         (*get_id)(struct packet *pkt);
	const uint8   *(*get_data)(struct packet *pkt);
	const char    *(*get_dissector)(struct packet *pkt);
};

#endif /* _HAKA_PACKET_MODULE_H */

