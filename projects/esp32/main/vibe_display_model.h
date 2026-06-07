#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "vibe_status.h"

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_DISPLAY_ROW_TEXT_MAX 48

typedef struct {
    uint32_t value;
    bool has_value;
} vibe_display_signature_t;

typedef struct {
    char badge[8];
    char title[VIBE_DISPLAY_ROW_TEXT_MAX];
    char subtitle[VIBE_DISPLAY_ROW_TEXT_MAX];
} vibe_display_task_row_t;

void vibe_display_signature_reset(vibe_display_signature_t *signature);
uint32_t vibe_display_packet_signature(const vibe_status_packet_t *packet);
bool vibe_display_should_render(vibe_display_signature_t *signature, const vibe_status_packet_t *packet);
void vibe_display_format_task_row(const vibe_status_task_t *task, int index, vibe_display_task_row_t *row);

#ifdef __cplusplus
}
#endif
