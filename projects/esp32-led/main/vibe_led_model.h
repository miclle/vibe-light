#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "vibe_status.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool red_on;
    bool yellow_on;
    bool green_on;
} vibe_led_state_t;

typedef struct {
    int codex_7d_red_threshold_percent;
    int64_t success_hold_ms;
} vibe_led_policy_t;

#define VIBE_LED_SLOW_BLINK_HALF_PERIOD_MS 500

vibe_led_state_t vibe_led_state_for_status(
    const vibe_status_packet_t *packet,
    int64_t now_ms,
    const vibe_led_policy_t *policy
);
bool vibe_led_state_any_on(vibe_led_state_t state);
vibe_led_state_t vibe_led_state_apply_slow_blink(vibe_led_state_t active, int64_t now_ms);

#ifdef __cplusplus
}
#endif
