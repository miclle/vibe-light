#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "vibe_status.h"

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_DISPLAY_ROW_TEXT_MAX 48
#define VIBE_DISPLAY_ANIMATION_PATH_STEPS 96

typedef struct {
    uint32_t value;
    bool has_value;
} vibe_display_signature_t;

typedef struct {
    char badge[8];
    char title[VIBE_DISPLAY_ROW_TEXT_MAX];
    char subtitle[VIBE_DISPLAY_ROW_TEXT_MAX];
} vibe_display_task_row_t;

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
void vibe_display_footer_text(const vibe_status_packet_t *packet, char *text, size_t text_size);
bool vibe_display_animation_enabled(vibe_display_state_t state);
int vibe_display_animation_step(int active_count);
void vibe_display_animation_frame(int tick, int active_count, vibe_display_animation_frame_t *frame);
void vibe_display_animation_actor_shape(const vibe_display_animation_frame_t *frame, vibe_display_animation_actor_t *actor);

#ifdef __cplusplus
}
#endif
