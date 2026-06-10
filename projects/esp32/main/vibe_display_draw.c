#include "vibe_display_draw.h"

#include <stddef.h>

static uint16_t *draw_framebuffer;
static int draw_width;
static int draw_height;

void vibe_display_draw_bind(uint16_t *framebuffer, int width, int height)
{
    draw_framebuffer = framebuffer;
    draw_width = width;
    draw_height = height;
}

void vibe_display_draw_fill_screen(uint16_t color)
{
    if (draw_framebuffer == NULL || draw_width <= 0 || draw_height <= 0) {
        return;
    }

    for (int i = 0; i < draw_width * draw_height; i++) {
        draw_framebuffer[i] = color;
    }
}

void vibe_display_draw_fill_rect(int x, int y, int w, int h, uint16_t color)
{
    if (draw_framebuffer == NULL || draw_width <= 0 || draw_height <= 0) {
        return;
    }

    if (x < 0) {
        w += x;
        x = 0;
    }
    if (y < 0) {
        h += y;
        y = 0;
    }
    if (x + w > draw_width) {
        w = draw_width - x;
    }
    if (y + h > draw_height) {
        h = draw_height - y;
    }
    if (w <= 0 || h <= 0) {
        return;
    }

    for (int row = y; row < y + h; row++) {
        uint16_t *line = draw_framebuffer + row * draw_width + x;
        for (int col = 0; col < w; col++) {
            line[col] = color;
        }
    }
}

void vibe_display_draw_blend_pixel(int x, int y, uint16_t color, uint8_t alpha_level)
{
    if (draw_framebuffer == NULL || alpha_level == 0 || x < 0 || y < 0 || x >= draw_width || y >= draw_height) {
        return;
    }
    if (alpha_level >= 3) {
        draw_framebuffer[y * draw_width + x] = color;
        return;
    }

    uint16_t bg = draw_framebuffer[y * draw_width + x];
    uint8_t fg_r = (uint8_t)((color >> 11) & 0x1f);
    uint8_t fg_g = (uint8_t)((color >> 5) & 0x3f);
    uint8_t fg_b = (uint8_t)(color & 0x1f);
    uint8_t bg_r = (uint8_t)((bg >> 11) & 0x1f);
    uint8_t bg_g = (uint8_t)((bg >> 5) & 0x3f);
    uint8_t bg_b = (uint8_t)(bg & 0x1f);
    uint8_t inv = (uint8_t)(3 - alpha_level);
    uint8_t r = (uint8_t)((fg_r * alpha_level + bg_r * inv + 1) / 3);
    uint8_t g = (uint8_t)((fg_g * alpha_level + bg_g * inv + 1) / 3);
    uint8_t b = (uint8_t)((fg_b * alpha_level + bg_b * inv + 1) / 3);
    draw_framebuffer[y * draw_width + x] = (uint16_t)((r << 11) | (g << 5) | b);
}

void vibe_display_draw_fill_circle(int cx, int cy, int radius, uint16_t color)
{
    int radius_squared = radius * radius;
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            if (x * x + y * y <= radius_squared) {
                vibe_display_draw_fill_rect(cx + x, cy + y, 1, 1, color);
            }
        }
    }
}

void vibe_display_draw_fill_triangle(int ax, int ay, int bx, int by, int cx, int cy, uint16_t color)
{
    int min_x = ax < bx ? ax : bx;
    min_x = min_x < cx ? min_x : cx;
    int max_x = ax > bx ? ax : bx;
    max_x = max_x > cx ? max_x : cx;
    int min_y = ay < by ? ay : by;
    min_y = min_y < cy ? min_y : cy;
    int max_y = ay > by ? ay : by;
    max_y = max_y > cy ? max_y : cy;

    int area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    if (area == 0) {
        return;
    }

    for (int y = min_y; y <= max_y; y++) {
        for (int x = min_x; x <= max_x; x++) {
            int w0 = (bx - ax) * (y - ay) - (by - ay) * (x - ax);
            int w1 = (cx - bx) * (y - by) - (cy - by) * (x - bx);
            int w2 = (ax - cx) * (y - cy) - (ay - cy) * (x - cx);
            if ((w0 >= 0 && w1 >= 0 && w2 >= 0) || (w0 <= 0 && w1 <= 0 && w2 <= 0)) {
                vibe_display_draw_fill_rect(x, y, 1, 1, color);
            }
        }
    }
}
