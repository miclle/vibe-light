#include "vibe_led_model.h"

#include <stdbool.h>

static bool packet_has_task_state(const vibe_status_packet_t *packet, vibe_display_state_t state)
{
    for (int index = 0; index < packet->task_count; index++) {
        if (packet->tasks[index].state == state) {
            return true;
        }
    }
    return false;
}

static bool packet_has_recent_success(
    const vibe_status_packet_t *packet,
    int64_t now_ms,
    int64_t success_hold_ms
)
{
    for (int index = 0; index < packet->task_count; index++) {
        const vibe_status_task_t *task = &packet->tasks[index];
        if (task->state != VIBE_DISPLAY_SUCCESS || task->updated_at_ms <= 0) {
            continue;
        }
        int64_t age_ms = now_ms - task->updated_at_ms;
        if (age_ms >= 0 && age_ms <= success_hold_ms) {
            return true;
        }
    }
    return false;
}

vibe_led_state_t vibe_led_state_for_status(
    const vibe_status_packet_t *packet,
    int64_t now_ms,
    const vibe_led_policy_t *policy
)
{
    vibe_led_state_t output = {0};
    if (packet == NULL || policy == NULL) {
        return output;
    }

    int threshold = policy->codex_7d_red_threshold_percent;
    if (threshold < 0) {
        threshold = 0;
    } else if (threshold > 100) {
        threshold = 100;
    }

    bool has_alert = (packet->alert_flags & (VIBE_STATUS_ALERT_TASK_ERROR | VIBE_STATUS_ALERT_CODEX_7D_LOW)) != 0;
    bool low_quota = !packet->alerts_present &&
                     packet->codex_7d_remaining_percent >= 0 &&
                     packet->codex_7d_remaining_percent <= threshold;
    bool has_error = packet->state == VIBE_DISPLAY_ERROR ||
                     packet->error_count > 0 ||
                     packet_has_task_state(packet, VIBE_DISPLAY_ERROR);
    output.red_on = has_alert || low_quota || has_error;

    bool has_waiting = (packet->alert_flags & VIBE_STATUS_ALERT_TASK_WAITING) != 0 ||
                       packet->state == VIBE_DISPLAY_WAITING ||
                       packet->waiting_count > 0 ||
                       packet_has_task_state(packet, VIBE_DISPLAY_WAITING);
    bool has_success = (packet->alert_flags & VIBE_STATUS_ALERT_TASK_SUCCESS) != 0 ||
                       packet->state == VIBE_DISPLAY_SUCCESS ||
                       packet_has_recent_success(packet, now_ms, policy->success_hold_ms);
    output.green_on = has_waiting || has_success;

    bool has_busy = (packet->alert_flags & VIBE_STATUS_ALERT_TASK_BUSY) != 0 ||
                    packet->state == VIBE_DISPLAY_BUSY ||
                    packet->active_count - packet->waiting_count > 0 ||
                    packet_has_task_state(packet, VIBE_DISPLAY_BUSY);
    output.yellow_on = has_busy;

    return output;
}

bool vibe_led_state_any_on(vibe_led_state_t state)
{
    return state.red_on || state.yellow_on || state.green_on;
}

vibe_led_state_t vibe_led_state_apply_slow_blink(vibe_led_state_t active, int64_t now_ms)
{
    if (now_ms < 0 || (now_ms / VIBE_LED_SLOW_BLINK_HALF_PERIOD_MS) % 2 != 0) {
        return (vibe_led_state_t){0};
    }
    return active;
}
