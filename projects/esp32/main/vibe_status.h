#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_STATUS_TEXT_MAX 96

typedef enum {
    VIBE_DISPLAY_IDLE = 0,
    VIBE_DISPLAY_BUSY,
    VIBE_DISPLAY_WAITING,
    VIBE_DISPLAY_SUCCESS,
    VIBE_DISPLAY_ERROR,
    VIBE_DISPLAY_OFFLINE,
} vibe_display_state_t;

typedef struct {
    int version;
    char source[VIBE_STATUS_TEXT_MAX];
    vibe_display_state_t state;
    char state_text[VIBE_STATUS_TEXT_MAX];
    char detail[VIBE_STATUS_TEXT_MAX];
    int64_t timestamp_ms;
} vibe_status_packet_t;

void vibe_status_default(vibe_status_packet_t *packet);
bool vibe_status_parse_json(const uint8_t *data, size_t length, vibe_status_packet_t *packet);
const char *vibe_display_state_to_string(vibe_display_state_t state);
const char *vibe_display_state_to_title(vibe_display_state_t state);
vibe_display_state_t vibe_display_state_from_string(const char *value, bool *known);

#ifdef __cplusplus
}
#endif
