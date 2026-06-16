#pragma once

#include <stdint.h>

#include "vibe_status.h"

#ifdef __cplusplus
extern "C" {
#endif

void vibe_display_landscape_render(const vibe_status_packet_t *packet,
                                   int animation_phase,
                                   uint16_t *portrait_framebuffer,
                                   int portrait_w,
                                   int portrait_h,
                                   uint16_t *landscape_framebuffer);

#ifdef __cplusplus
}
#endif
