#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "vibe_led_model.h"
#include "vibe_led_output.h"
#include "vibe_status.h"

_Static_assert(VIBE_LED_RED_GPIO == 4, "red GPIO contract");
_Static_assert(VIBE_LED_YELLOW_GPIO == 5, "yellow GPIO contract");
_Static_assert(VIBE_LED_GREEN_GPIO == 6, "green GPIO contract");

static const vibe_led_policy_t POLICY = {
    .codex_7d_red_threshold_percent = 10,
    .success_hold_ms = 60000,
};

static vibe_status_packet_t packet_with_state(vibe_display_state_t state)
{
    vibe_status_packet_t packet;
    vibe_status_default(&packet);
    packet.state = state;
    packet.timestamp_ms = 1780300800000;
    return packet;
}

static void test_red_alerts_turn_on_red(void)
{
    vibe_status_packet_t packet = packet_with_state(VIBE_DISPLAY_WAITING);
    packet.alert_flags = VIBE_STATUS_ALERT_CODEX_7D_LOW;
    packet.waiting_count = 1;

    vibe_led_state_t state = vibe_led_state_for_status(&packet, packet.timestamp_ms, &POLICY);
    assert(state.red_on);
    assert(state.green_on);
    assert(!state.yellow_on);
}

static void test_errors_and_low_raw_quota_are_red(void)
{
    vibe_status_packet_t error = packet_with_state(VIBE_DISPLAY_IDLE);
    error.error_count = 1;
    assert(vibe_led_state_for_status(&error, error.timestamp_ms, &POLICY).red_on);

    vibe_status_packet_t low_quota = packet_with_state(VIBE_DISPLAY_IDLE);
    low_quota.codex_7d_remaining_percent = 10;
    assert(vibe_led_state_for_status(&low_quota, low_quota.timestamp_ms, &POLICY).red_on);

    low_quota.codex_7d_remaining_percent = 11;
    assert(!vibe_led_state_for_status(&low_quota, low_quota.timestamp_ms, &POLICY).red_on);
}

static void test_v2_alerts_are_authoritative_for_quota_threshold(void)
{
    const char *authoritative_json =
        "{\"alerts\":[],\"state\":\"idle\",\"usage\":{\"codex7dRemainingPercent\":8},\"v\":2}";
    vibe_status_packet_t packet;
    assert(vibe_status_parse_json(
        (const uint8_t *)authoritative_json,
        strlen(authoritative_json),
        &packet
    ));

    assert(!vibe_led_state_for_status(&packet, packet.timestamp_ms, &POLICY).red_on);

    const char *legacy_json =
        "{\"state\":\"idle\",\"usage\":{\"codex7dRemainingPercent\":8},\"v\":2}";
    assert(vibe_status_parse_json((const uint8_t *)legacy_json, strlen(legacy_json), &packet));
    assert(vibe_led_state_for_status(&packet, packet.timestamp_ms, &POLICY).red_on);
}

static void test_waiting_and_busy_turn_on_green_and_yellow(void)
{
    vibe_status_packet_t packet = packet_with_state(VIBE_DISPLAY_WAITING);
    packet.active_count = 2;
    packet.waiting_count = 1;
    packet.task_count = 2;
    packet.tasks[0].state = VIBE_DISPLAY_WAITING;
    packet.tasks[1].state = VIBE_DISPLAY_BUSY;

    vibe_led_state_t state = vibe_led_state_for_status(&packet, packet.timestamp_ms, &POLICY);
    assert(!state.red_on);
    assert(state.yellow_on);
    assert(state.green_on);
}

static void test_busy_is_yellow(void)
{
    vibe_status_packet_t packet = packet_with_state(VIBE_DISPLAY_BUSY);
    packet.active_count = 1;

    vibe_led_state_t state = vibe_led_state_for_status(&packet, packet.timestamp_ms, &POLICY);
    assert(!state.red_on);
    assert(state.yellow_on);
    assert(!state.green_on);
}

static void test_recent_success_expires_after_hold_window(void)
{
    vibe_status_packet_t packet = packet_with_state(VIBE_DISPLAY_IDLE);
    packet.task_count = 1;
    packet.tasks[0].state = VIBE_DISPLAY_SUCCESS;
    packet.tasks[0].updated_at_ms = packet.timestamp_ms - 30000;

    assert(vibe_led_state_for_status(&packet, packet.timestamp_ms, &POLICY).green_on);
    assert(!vibe_led_state_for_status(&packet, packet.timestamp_ms + 31000, &POLICY).green_on);
}

static void test_recent_success_and_busy_turn_on_green_and_yellow(void)
{
    vibe_status_packet_t packet = packet_with_state(VIBE_DISPLAY_BUSY);
    packet.active_count = 1;
    packet.task_count = 2;
    packet.tasks[0].state = VIBE_DISPLAY_BUSY;
    packet.tasks[0].updated_at_ms = packet.timestamp_ms;
    packet.tasks[1].state = VIBE_DISPLAY_SUCCESS;
    packet.tasks[1].updated_at_ms = packet.timestamp_ms;

    vibe_led_state_t state = vibe_led_state_for_status(&packet, packet.timestamp_ms, &POLICY);
    assert(!state.red_on);
    assert(state.yellow_on);
    assert(state.green_on);
}

static void test_error_busy_and_success_turn_on_all_three_leds(void)
{
    vibe_status_packet_t packet = packet_with_state(VIBE_DISPLAY_ERROR);
    packet.active_count = 2;
    packet.error_count = 1;
    packet.task_count = 3;
    packet.tasks[0].state = VIBE_DISPLAY_ERROR;
    packet.tasks[1].state = VIBE_DISPLAY_BUSY;
    packet.tasks[2].state = VIBE_DISPLAY_SUCCESS;
    packet.tasks[2].updated_at_ms = packet.timestamp_ms;

    vibe_led_state_t state = vibe_led_state_for_status(&packet, packet.timestamp_ms, &POLICY);
    assert(state.red_on);
    assert(state.yellow_on);
    assert(state.green_on);
}

static void test_compact_alert_signals_keep_busy_waiting_and_success_independent(void)
{
    vibe_status_packet_t packet = packet_with_state(VIBE_DISPLAY_IDLE);
    packet.alert_flags = VIBE_STATUS_ALERT_TASK_BUSY |
                         VIBE_STATUS_ALERT_TASK_WAITING |
                         VIBE_STATUS_ALERT_TASK_SUCCESS;
    packet.alerts_present = true;

    vibe_led_state_t state = vibe_led_state_for_status(&packet, packet.timestamp_ms, &POLICY);
    assert(!state.red_on);
    assert(state.yellow_on);
    assert(state.green_on);
}

static void test_idle_and_unknown_quota_are_off(void)
{
    vibe_status_packet_t packet = packet_with_state(VIBE_DISPLAY_IDLE);
    packet.codex_7d_remaining_percent = -1;

    vibe_led_state_t state = vibe_led_state_for_status(&packet, packet.timestamp_ms, &POLICY);
    assert(!state.red_on);
    assert(!state.yellow_on);
    assert(!state.green_on);
}

static void test_active_leds_blink_on_for_500ms_then_off_for_500ms(void)
{
    vibe_led_state_t active = {
        .red_on = true,
        .yellow_on = true,
        .green_on = true,
    };

    vibe_led_state_t on_start = vibe_led_state_apply_slow_blink(active, 0);
    vibe_led_state_t on_end = vibe_led_state_apply_slow_blink(active, 499);
    vibe_led_state_t off_start = vibe_led_state_apply_slow_blink(active, 500);
    vibe_led_state_t off_end = vibe_led_state_apply_slow_blink(active, 999);
    vibe_led_state_t next_on = vibe_led_state_apply_slow_blink(active, 1000);

    assert(on_start.red_on && on_start.yellow_on && on_start.green_on);
    assert(on_end.red_on && on_end.yellow_on && on_end.green_on);
    assert(!off_start.red_on && !off_start.yellow_on && !off_start.green_on);
    assert(!off_end.red_on && !off_end.yellow_on && !off_end.green_on);
    assert(next_on.red_on && next_on.yellow_on && next_on.green_on);
}

int main(void)
{
    test_red_alerts_turn_on_red();
    test_errors_and_low_raw_quota_are_red();
    test_v2_alerts_are_authoritative_for_quota_threshold();
    test_waiting_and_busy_turn_on_green_and_yellow();
    test_busy_is_yellow();
    test_recent_success_expires_after_hold_window();
    test_recent_success_and_busy_turn_on_green_and_yellow();
    test_error_busy_and_success_turn_on_all_three_leds();
    test_compact_alert_signals_keep_busy_waiting_and_success_independent();
    test_idle_and_unknown_quota_are_off();
    test_active_leds_blink_on_for_500ms_then_off_for_500ms();
    puts("vibe_led_model_test: ok");
    return 0;
}
