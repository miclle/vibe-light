#pragma once

#include "vibe_status.h"

#ifdef __cplusplus
extern "C" {
#endif

void vibe_display_init(void);
void vibe_display_show_status(const vibe_status_packet_t *packet);
void vibe_display_show_error(const char *message);

#ifdef __cplusplus
}
#endif
