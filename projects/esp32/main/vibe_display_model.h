#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "vibe_status.h"

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_DISPLAY_ROW_TEXT_MAX 48
#define VIBE_DISPLAY_COUNT_TEXT_MAX 8
#define VIBE_DISPLAY_MAZE_SCORE_TEXT_MAX 16
#define VIBE_DISPLAY_MAZE_LEVEL_TEXT_MAX 4
#define VIBE_DISPLAY_ANIMATION_PATH_STEPS 425
#define VIBE_DISPLAY_ANIMATION_SUBSTEPS 2
#define VIBE_DISPLAY_ANIMATION_PERIOD_MS 240
#define VIBE_DISPLAY_MAZE_STAGE_X 0
#define VIBE_DISPLAY_MAZE_STAGE_Y 90
#define VIBE_DISPLAY_MAZE_STAGE_W 320
#define VIBE_DISPLAY_MAZE_STAGE_H 320
#define VIBE_DISPLAY_MAZE_FRAME_H 320
#define VIBE_DISPLAY_MAZE_REFERENCE_MIN_X 15
#define VIBE_DISPLAY_MAZE_REFERENCE_MAX_X 303
#define VIBE_DISPLAY_MAZE_PATH_INSET 14
#define VIBE_DISPLAY_MAZE_WALL_THICKNESS 1
#define VIBE_DISPLAY_MAZE_BORDER_GAP 8
#define VIBE_DISPLAY_MAZE_PELLET_COUNT 213
#define VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS \
    (VIBE_DISPLAY_ANIMATION_PATH_STEPS * VIBE_DISPLAY_ANIMATION_SUBSTEPS)
#define VIBE_DISPLAY_MAZE_POWER_PELLET_RADIUS 3
#define VIBE_DISPLAY_MAZE_SCORE_CLEAR_Y 16
#define VIBE_DISPLAY_MAZE_SCORE_CLEAR_H 10
#define VIBE_DISPLAY_MAZE_SCORE_VALUE_Y 16
#define VIBE_DISPLAY_MAZE_SCORE_VALUE_H 10
#define VIBE_DISPLAY_MAZE_SCORE_LEFT_X 16
#define VIBE_DISPLAY_MAZE_SCORE_RIGHT_X 83
#define VIBE_DISPLAY_MAZE_HIGH_SCORE_LEFT_X 126
#define VIBE_DISPLAY_MAZE_HIGH_SCORE_RIGHT_X 193
#define VIBE_DISPLAY_MAZE_LEVEL_CLEAR_Y 12
#define VIBE_DISPLAY_MAZE_LEVEL_CLEAR_H 14
#define VIBE_DISPLAY_MAZE_LEVEL_VALUE_Y 14
#define VIBE_DISPLAY_MAZE_LEVEL_LEFT_X 238
#define VIBE_DISPLAY_MAZE_LEVEL_RIGHT_X 303
#define VIBE_DISPLAY_MAZE_LEVEL_VALUE_X 284
#define VIBE_DISPLAY_CODEX_ACTOR_RADIUS 7
#define VIBE_DISPLAY_CODEX_ACTOR_EYE_RADIUS 0
#define VIBE_DISPLAY_MAZE_GHOST_CENTER_X 160
#define VIBE_DISPLAY_MAZE_GHOST_CENTER_Y 235
#define VIBE_DISPLAY_MAZE_GHOST_BLINK_TICKS 20
#define VIBE_DISPLAY_TASK_PANEL_X 0
#define VIBE_DISPLAY_TASK_PANEL_Y 410
#define VIBE_DISPLAY_TASK_PANEL_W 320
#define VIBE_DISPLAY_TASK_PANEL_H 410
#define VIBE_DISPLAY_TASK_ROW_Y 426
#define VIBE_DISPLAY_TASK_ROW_STRIDE 44
#define VIBE_DISPLAY_TASK_DETAIL_ROW_STRIDE 64
#define VIBE_DISPLAY_TASK_DETAIL_Y_OFFSET 24
#define VIBE_DISPLAY_TASK_ROW_TEXT_H 14
#define VIBE_DISPLAY_TASK_DETAIL_TEXT_H 21
#define VIBE_DISPLAY_TASK_SWATCH_X 0
#define VIBE_DISPLAY_TASK_TEXT_X 16
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
    char trailing[12];
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

typedef struct {
    char five_hour[12];
    char weekly[12];
    char reset_hint[24];
} vibe_display_usage_summary_t;

typedef struct {
    char label[24];
    char detail[VIBE_STATUS_TEXT_MAX];
    int detail_scale;
    int detail_max_width;
    bool quiet_header;
} vibe_display_empty_state_t;

typedef struct {
    int value;
    bool dirty;
} vibe_display_maze_high_score_t;

typedef struct {
    int x;
    int y;
    bool eyes_closed;
} vibe_display_maze_ghost_frame_t;

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
void vibe_display_format_task_row_at(const vibe_status_task_t *task,
                                     int64_t now_ms,
                                     int index,
                                     vibe_display_task_row_t *row);
void vibe_display_format_task_row_at_phase(const vibe_status_task_t *task,
                                           int64_t now_ms,
                                           int index,
                                           int phase,
                                           vibe_display_task_row_t *row);
bool vibe_display_should_render_task_detail(const vibe_status_task_t *task);
void vibe_display_format_count_summary(const vibe_status_packet_t *packet, vibe_display_count_summary_t *summary);
void vibe_display_format_maze_count_text(const vibe_status_packet_t *packet, vibe_display_maze_count_text_t *text);
int vibe_display_maze_score(int tick, int actor_count, int active_count, int reset_ticks);
void vibe_display_format_maze_score_text(int score, char *text, size_t text_size);
int vibe_display_maze_level(int tick, int actor_count, int reset_ticks);
void vibe_display_format_maze_level_text(int level, char *text, size_t text_size);
void vibe_display_maze_high_score_init(vibe_display_maze_high_score_t *high_score, int stored_value);
bool vibe_display_maze_high_score_update(vibe_display_maze_high_score_t *high_score, int score);
void vibe_display_maze_ghost_frame(int tick, vibe_display_maze_ghost_frame_t *frame);
void vibe_display_format_usage_summary(const vibe_status_packet_t *packet, vibe_display_usage_summary_t *summary);
void vibe_display_format_empty_state(const vibe_status_packet_t *packet, vibe_display_empty_state_t *empty);
void vibe_display_footer_text(const vibe_status_packet_t *packet, char *text, size_t text_size);
bool vibe_display_animation_enabled(vibe_display_state_t state);
bool vibe_display_phase_refresh_enabled(vibe_display_state_t state);
bool vibe_display_should_preserve_animation_tick(vibe_display_state_t previous_state,
                                                 vibe_display_state_t next_state,
                                                 bool animation_running);
int vibe_display_animation_step(int active_count);
int vibe_display_animation_actor_count(int task_count, int active_count);
void vibe_display_animation_frame(int tick, int active_count, vibe_display_animation_frame_t *frame);
void vibe_display_animation_actor_frame(int tick, int actor_index, int actor_count, int active_count, vibe_display_animation_frame_t *frame);
int vibe_display_maze_display_x(int reference_x);
int vibe_display_maze_display_run_width(int reference_x, int reference_length);
void vibe_display_maze_pellet_position(int pellet_index, int pellet_count, vibe_display_animation_frame_t *frame);
bool vibe_display_maze_is_power_pellet(int pellet_index, int pellet_count);
void vibe_display_maze_warm_pellet_cache(int actor_count);
bool vibe_display_maze_pellet_visible(int pellet_index,
                                      int tick,
                                      int actor_count,
                                      int active_count,
                                      int reset_ticks);
void vibe_display_animation_actor_shape(const vibe_display_animation_frame_t *frame, vibe_display_animation_actor_t *actor);

#ifdef __cplusplus
}
#endif
