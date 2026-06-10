#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void vibe_display_text_bind(int screen_width);
void vibe_display_text_draw(int x, int y, const char *text, int scale, uint16_t color);
void vibe_display_text_draw_ellipsis(int x, int y, const char *text, int scale, uint16_t color, int max_width);
int vibe_display_text_width(const char *text, int scale);

#ifdef __cplusplus
}
#endif
