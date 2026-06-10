#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void vibe_display_draw_bind(uint16_t *framebuffer, int width, int height);
void vibe_display_draw_fill_screen(uint16_t color);
void vibe_display_draw_fill_rect(int x, int y, int w, int h, uint16_t color);
void vibe_display_draw_blend_pixel(int x, int y, uint16_t color, uint8_t alpha_level);
void vibe_display_draw_fill_circle(int cx, int cy, int radius, uint16_t color);
void vibe_display_draw_fill_triangle(int ax, int ay, int bx, int by, int cx, int cy, uint16_t color);

#ifdef __cplusplus
}
#endif
