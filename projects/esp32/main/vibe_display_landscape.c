#include "vibe_display_landscape.h"

#include "vibe_display_draw.h"
#include "vibe_display_model.h"
#include "vibe_display_render.h"
#include "vibe_display_score.h"
#include "vibe_display_text.h"
#include "vibe_landscape_maze_data.h"

static void render_landscape_maze(void);
static void draw_landscape_maze_bitmap(const vibe_display_landscape_layout_t *layout);
static void rotate_landscape_to_portrait_framebuffer(uint16_t *portrait_framebuffer,
                                                     int portrait_w,
                                                     int portrait_h,
                                                     uint16_t *landscape_framebuffer);

void vibe_display_landscape_render(const vibe_status_packet_t *packet,
                                   int animation_phase,
                                   uint16_t *portrait_framebuffer,
                                   int portrait_w,
                                   int portrait_h,
                                   uint16_t *landscape_framebuffer)
{
    if (packet == NULL || portrait_framebuffer == NULL || landscape_framebuffer == NULL ||
        portrait_w <= 0 || portrait_h <= 0) {
        return;
    }

    vibe_display_draw_bind(landscape_framebuffer, VIBE_DISPLAY_LANDSCAPE_W, VIBE_DISPLAY_LANDSCAPE_H);
    vibe_display_text_bind(VIBE_DISPLAY_LANDSCAPE_W);
    vibe_display_draw_fill_screen(RGB565_BLACK);

    int actor_count = vibe_display_animation_actor_count(packet->task_count, packet->active_count);
    int score = vibe_display_animation_enabled(packet->state)
                    ? vibe_display_maze_score(animation_phase,
                                              actor_count,
                                              packet->active_count,
                                              VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS)
                    : 0;
    int level = vibe_display_animation_enabled(packet->state)
                    ? vibe_display_maze_level(animation_phase,
                                              actor_count,
                                              VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS)
                    : 1;
    (void)level;
    if (vibe_display_animation_enabled(packet->state)) {
        vibe_display_score_update(score);
    }

    render_landscape_maze();
    rotate_landscape_to_portrait_framebuffer(portrait_framebuffer,
                                             portrait_w,
                                             portrait_h,
                                             landscape_framebuffer);
}

static void render_landscape_maze(void)
{
    vibe_display_landscape_layout_t layout;
    vibe_display_landscape_layout(&layout);

    vibe_display_draw_fill_rect(layout.maze_x, layout.maze_y, layout.maze_w, layout.maze_h, RGB565_BLACK);
    draw_landscape_maze_bitmap(&layout);
}

static void draw_landscape_maze_bitmap(const vibe_display_landscape_layout_t *layout)
{
    if (layout == NULL) {
        return;
    }

    for (int i = 0; i < VIBE_LANDSCAPE_MAZE_RUN_COUNT; i++) {
        const vibe_landscape_maze_run_t *run = &VIBE_LANDSCAPE_MAZE_RUNS[i];
        int x0 = layout->maze_x + ((int)run->x * layout->maze_w) / VIBE_LANDSCAPE_MAZE_BITMAP_W;
        int x1 = layout->maze_x + (((int)run->x + (int)run->length) * layout->maze_w) / VIBE_LANDSCAPE_MAZE_BITMAP_W;
        int y0 = layout->maze_y + ((int)run->y * layout->maze_h) / VIBE_LANDSCAPE_MAZE_BITMAP_H;
        int y1 = layout->maze_y + (((int)run->y + 1) * layout->maze_h) / VIBE_LANDSCAPE_MAZE_BITMAP_H;
        int w = x1 - x0;
        int h = y1 - y0;
        uint16_t color = RGB565_WHITE;
        if (run->color_index < VIBE_LANDSCAPE_MAZE_PALETTE_COUNT) {
            color = VIBE_LANDSCAPE_MAZE_PALETTE[run->color_index];
        }
        vibe_display_draw_fill_rect(x0, y0, w > 0 ? w : 1, h > 0 ? h : 1, color);
    }
}

static void rotate_landscape_to_portrait_framebuffer(uint16_t *portrait_framebuffer,
                                                     int portrait_w,
                                                     int portrait_h,
                                                     uint16_t *landscape_framebuffer)
{
    if (portrait_framebuffer == NULL || landscape_framebuffer == NULL) {
        return;
    }

    for (int ly = 0; ly < VIBE_DISPLAY_LANDSCAPE_H; ly++) {
        for (int lx = 0; lx < VIBE_DISPLAY_LANDSCAPE_W; lx++) {
            int px = ly;
            int py = portrait_h - 1 - lx;
            portrait_framebuffer[py * portrait_w + px] = landscape_framebuffer[ly * VIBE_DISPLAY_LANDSCAPE_W + lx];
        }
    }
    vibe_display_draw_bind(portrait_framebuffer, portrait_w, portrait_h);
    vibe_display_text_bind(portrait_w);
}
