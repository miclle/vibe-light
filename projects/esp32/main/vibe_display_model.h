#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "vibe_status.h"

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_DISPLAY_ROW_TEXT_MAX 48
#define VIBE_DISPLAY_COUNT_TEXT_MAX 8
#define VIBE_DISPLAY_ANIMATION_PATH_STEPS 425
#define VIBE_DISPLAY_ANIMATION_SUBSTEPS 2
#define VIBE_DISPLAY_ANIMATION_PERIOD_MS 240
#define VIBE_DISPLAY_MAZE_STAGE_X 0
#define VIBE_DISPLAY_MAZE_STAGE_Y 82
#define VIBE_DISPLAY_MAZE_STAGE_W 320
#define VIBE_DISPLAY_MAZE_STAGE_H 320
#define VIBE_DISPLAY_MAZE_FRAME_H 320
#define VIBE_DISPLAY_MAZE_REFERENCE_MIN_X 15
#define VIBE_DISPLAY_MAZE_REFERENCE_MAX_X 303
#define VIBE_DISPLAY_MAZE_PATH_INSET 14
#define VIBE_DISPLAY_MAZE_WALL_THICKNESS 1
#define VIBE_DISPLAY_MAZE_BORDER_GAP 8
#define VIBE_DISPLAY_MAZE_PELLET_COUNT 213
#define VIBE_DISPLAY_MAZE_PELLET_RECOVERY_MS 5000
#define VIBE_DISPLAY_MAZE_PELLET_RECOVERY_TICKS \
    ((VIBE_DISPLAY_MAZE_PELLET_RECOVERY_MS + VIBE_DISPLAY_ANIMATION_PERIOD_MS - 1) / VIBE_DISPLAY_ANIMATION_PERIOD_MS)
#define VIBE_DISPLAY_MAZE_POWER_PELLET_RADIUS 3
#define VIBE_DISPLAY_CODEX_ACTOR_RADIUS 7
#define VIBE_DISPLAY_CODEX_ACTOR_EYE_RADIUS 0
#define VIBE_DISPLAY_TASK_PANEL_X 0
#define VIBE_DISPLAY_TASK_PANEL_Y 402
#define VIBE_DISPLAY_TASK_PANEL_W 320
#define VIBE_DISPLAY_TASK_PANEL_H 418
#define VIBE_DISPLAY_TASK_ROW_Y 418
#define VIBE_DISPLAY_TASK_ROW_STRIDE 44
#define VIBE_DISPLAY_TASK_DETAIL_ROW_STRIDE 64
#define VIBE_DISPLAY_TASK_DETAIL_Y_OFFSET 24
#define VIBE_DISPLAY_TASK_ROW_TEXT_H 14
#define VIBE_DISPLAY_TASK_DETAIL_TEXT_H 21
#define VIBE_DISPLAY_TASK_SWATCH_W 4
#define VIBE_DISPLAY_TASK_SWATCH_H 18

typedef struct {
    uint32_t value;
    bool has_value;
} vibe_display_signature_t;

typedef struct {
    char badge[8];
    char title[VIBE_DISPLAY_ROW_TEXT_MAX];
    char subtitle[VIBE_DISPLAY_ROW_TEXT_MAX];
} vibe_display_task_row_t;

typedef struct {
    char active[VIBE_DISPLAY_COUNT_TEXT_MAX];
    char waiting[VIBE_DISPLAY_COUNT_TEXT_MAX];
    char error[VIBE_DISPLAY_COUNT_TEXT_MAX];
} vibe_display_count_summary_t;

typedef struct {
    char active[16];
    char waiting[16];
    char error[16];
} vibe_display_maze_count_text_t;

typedef enum {
    VIBE_DISPLAY_DIRECTION_RIGHT = 0,
    VIBE_DISPLAY_DIRECTION_DOWN,
    VIBE_DISPLAY_DIRECTION_LEFT,
    VIBE_DISPLAY_DIRECTION_UP,
} vibe_display_direction_t;

typedef struct {
    int x;
    int y;
    vibe_display_direction_t direction;
    bool mouth_open;
} vibe_display_animation_frame_t;

typedef struct {
    int mouth_tip_x;
    int mouth_tip_y;
    int mouth_a_x;
    int mouth_a_y;
    int mouth_b_x;
    int mouth_b_y;
    int eye_x;
    int eye_y;
} vibe_display_animation_actor_t;

void vibe_display_signature_reset(vibe_display_signature_t *signature);
uint32_t vibe_display_packet_signature(const vibe_status_packet_t *packet);
bool vibe_display_should_render(vibe_display_signature_t *signature, const vibe_status_packet_t *packet);
void vibe_display_format_task_row(const vibe_status_task_t *task, int index, vibe_display_task_row_t *row);
void vibe_display_format_count_summary(const vibe_status_packet_t *packet, vibe_display_count_summary_t *summary);
void vibe_display_format_maze_count_text(const vibe_status_packet_t *packet, vibe_display_maze_count_text_t *text);
void vibe_display_footer_text(const vibe_status_packet_t *packet, char *text, size_t text_size);
bool vibe_display_animation_enabled(vibe_display_state_t state);
int vibe_display_animation_step(int active_count);
int vibe_display_animation_actor_count(int task_count, int active_count);
void vibe_display_animation_frame(int tick, int active_count, vibe_display_animation_frame_t *frame);
void vibe_display_animation_actor_frame(int tick, int actor_index, int actor_count, int active_count, vibe_display_animation_frame_t *frame);
int vibe_display_maze_display_x(int reference_x);
int vibe_display_maze_display_run_width(int reference_x, int reference_length);
void vibe_display_maze_pellet_position(int pellet_index, int pellet_count, vibe_display_animation_frame_t *frame);
bool vibe_display_maze_is_power_pellet(int pellet_index, int pellet_count);
bool vibe_display_maze_pellet_visible(int pellet_index,
                                      int tick,
                                      int actor_count,
                                      int active_count,
                                      int recovery_ticks);
void vibe_display_animation_actor_shape(const vibe_display_animation_frame_t *frame, vibe_display_animation_actor_t *actor);

#ifdef __cplusplus
}
#endif
