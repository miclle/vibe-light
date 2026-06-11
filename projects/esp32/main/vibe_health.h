#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int animation_tick;
    bool backlight_on;
    bool connected;
    const char *device;
    unsigned free_heap_bytes;
    const char *last_parse_error;
    const char *last_state;
    unsigned min_free_heap_bytes;
    int64_t uptime_ms;
} vibe_health_snapshot_t;

int vibe_health_format_json(char *payload, size_t payload_size, const vibe_health_snapshot_t *snapshot);

#ifdef __cplusplus
}
#endif
