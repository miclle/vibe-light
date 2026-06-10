#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int vibe_display_maze_text_width(const char *text, int scale);
void vibe_display_maze_text_draw(int x, int y, const char *text, int scale, uint16_t color, int max_x);
void vibe_display_maze_text_draw_centered(int left, int right, int y, const char *text, uint16_t color, int max_x);

#ifdef __cplusplus
}
#endif
