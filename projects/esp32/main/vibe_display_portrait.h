#pragma once

#include <stdint.h>

#include "vibe_status.h"

#ifdef __cplusplus
extern "C" {
#endif

void vibe_display_portrait_render(const vibe_status_packet_t *packet,
                                  int animation_phase,
                                  uint16_t *framebuffer,
                                  int screen_w,
                                  int screen_h,
                                  const char *firmware_version);
void vibe_display_portrait_render_animation_phase(const vibe_status_packet_t *packet,
                                                  int animation_phase,
                                                  uint16_t *framebuffer,
                                                  int screen_w,
                                                  int screen_h);

#ifdef __cplusplus
}
#endif
