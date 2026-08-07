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
// VIBE_LED_TRAFFIC_RED_DURATION_MS defines the red phase length.
#define VIBE_LED_TRAFFIC_RED_DURATION_MS 5000
// VIBE_LED_TRAFFIC_GREEN_DURATION_MS defines the green phase length.
#define VIBE_LED_TRAFFIC_GREEN_DURATION_MS 5000
// VIBE_LED_TRAFFIC_YELLOW_DURATION_MS defines the yellow phase length.
#define VIBE_LED_TRAFFIC_YELLOW_DURATION_MS 2000

vibe_led_state_t vibe_led_state_for_status(
    const vibe_status_packet_t *packet,
    int64_t now_ms,
    const vibe_led_policy_t *policy
);
bool vibe_led_state_any_on(vibe_led_state_t state);
vibe_led_state_t vibe_led_state_apply_slow_blink(vibe_led_state_t active, int64_t now_ms);
// vibe_led_state_for_traffic_cycle returns the green-yellow-red-yellow phase for monotonic uptime.
vibe_led_state_t vibe_led_state_for_traffic_cycle(int64_t uptime_ms);
// vibe_led_state_for_output gives Agent blinking priority, then falls back to the traffic cycle.
vibe_led_state_t vibe_led_state_for_output(
    const vibe_status_packet_t *packet,
    int64_t status_now_ms,
    int64_t uptime_ms,
    int64_t traffic_cycle_started_at_ms,
    const vibe_led_policy_t *policy
);

#ifdef __cplusplus
}
#endif
