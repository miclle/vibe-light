#include "vibe_status.h"
#include "vibe_cjk_font.h"
#include "vibe_display_model.h"
#include "vibe_health.h"
#include "vibe_reference_maze.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const uint8_t cjk_test_font_bin_start[] __asm__("_binary_vibe_cjk_font_bin_start") = {
    'V', 'C', 'J', 'K',
    1, 0,
    18, 0,
    18, 0,
    90, 0,
    0, 0,
};
const uint8_t cjk_test_font_bin_end[] __asm__("_binary_vibe_cjk_font_bin_end") = {0};

static bool parse(const char *json, vibe_status_packet_t *packet)
{
    return vibe_status_parse_json((const uint8_t *)json, strlen(json), packet);
}

static bool frame_matches_reference_pellet(const vibe_display_animation_frame_t *frame);
static int find_pellet_at_frame(const vibe_display_animation_frame_t *frame);
static int visible_pellet_count_at_tick(int tick, int actor_count);
static bool reference_maze_color_intersects_rect(uint16_t color, int x, int y, int w, int h);
static bool reference_maze_long_color_intersects_rect(uint16_t color, int min_length, int x, int y, int w, int h);
static int reference_maze_min_long_color_y(uint16_t color, int min_length);

static void test_v1_status_packet(void)
{
    vibe_status_packet_t packet;
    vibe_status_default(&packet);

    assert(parse("{\"detail\":\"running\",\"source\":\"codex\",\"state\":\"busy\",\"ts\":1780300800000,\"v\":1}", &packet));
    assert(packet.version == 1);
    assert(strcmp(packet.source, "codex") == 0);
    assert(packet.state == VIBE_DISPLAY_BUSY);
    assert(strcmp(packet.state_text, "busy") == 0);
    assert(strcmp(packet.detail, "running") == 0);
    assert(packet.timestamp_ms == 1780300800000LL);
    assert(packet.active_count == 0);
    assert(packet.task_count == 0);
}

static void test_v2_task_list_packet(void)
{
    const char *json =
        "{"
        "\"activeCount\":3,"
        "\"detail\":\"2 running / 1 waiting\","
        "\"errorCount\":1,"
        "\"source\":\"codex\","
        "\"state\":\"waiting\","
        "\"tasks\":["
        "{\"detail\":\"approve command\",\"source\":\"codex\",\"state\":\"waiting\",\"title\":\"vibe-light\",\"updatedAt\":1780300732000},"
        "{\"detail\":\"render preview\",\"source\":\"claude\",\"state\":\"busy\",\"title\":\"slideo\"},"
        "{\"detail\":\"failed build\",\"source\":\"codex\",\"state\":\"error\",\"title\":\"firmware\"},"
        "{\"source\":\"codex\",\"state\":\"success\",\"title\":\"extra-1\"},"
        "{\"source\":\"codex\",\"state\":\"idle\",\"title\":\"extra-2\"},"
        "{\"source\":\"codex\",\"state\":\"busy\",\"title\":\"extra-3\"}"
        "],"
        "\"ts\":1780300800000,"
        "\"v\":2,"
        "\"waitingCount\":1"
        "}";

    vibe_status_packet_t packet;
    vibe_status_default(&packet);

    assert(parse(json, &packet));
    assert(packet.version == 2);
    assert(packet.state == VIBE_DISPLAY_WAITING);
    assert(packet.active_count == 3);
    assert(packet.waiting_count == 1);
    assert(packet.error_count == 1);
    assert(packet.task_count == VIBE_STATUS_MAX_TASKS);
    assert(strcmp(packet.tasks[0].title, "vibe-light") == 0);
    assert(packet.tasks[0].state == VIBE_DISPLAY_WAITING);
    assert(packet.tasks[0].updated_at_ms == 1780300732000LL);
    assert(strcmp(packet.tasks[1].source, "claude") == 0);
    assert(packet.tasks[1].state == VIBE_DISPLAY_BUSY);
    assert(packet.tasks[2].state == VIBE_DISPLAY_ERROR);
    assert(strcmp(packet.tasks[4].title, "extra-2") == 0);
}

static void test_v2_usage_packet(void)
{
    const char *json =
        "{"
        "\"activeCount\":1,"
        "\"source\":\"codex\","
        "\"state\":\"busy\","
        "\"tasks\":["
        "{\"contextUsedPercent\":90,\"contextUsedTokens\":4200,\"contextWindowTokens\":12000,"
        "\"source\":\"codex\",\"state\":\"busy\",\"title\":\"vibe-light\"}"
        "],"
        "\"usage\":{\"codex5hRemainingPercent\":88,\"codex7dRemainingPercent\":60},"
        "\"v\":2"
        "}";

    vibe_status_packet_t packet;
    vibe_display_usage_summary_t usage;
    vibe_display_task_row_t row;
    vibe_status_default(&packet);

    assert(parse(json, &packet));
    assert(packet.codex_5h_remaining_percent == 88);
    assert(packet.codex_7d_remaining_percent == 60);
    assert(packet.tasks[0].context_used_percent == 90);
    assert(packet.tasks[0].context_used_tokens == 4200);
    assert(packet.tasks[0].context_window_tokens == 12000);

    vibe_display_format_usage_summary(&packet, &usage);
    assert(strcmp(usage.five_hour, "5H 88%") == 0);
    assert(strcmp(usage.weekly, "7D 60%") == 0);

    vibe_display_format_task_row(&packet.tasks[0], 0, &row);
    assert(strcmp(row.trailing, "CTX 4.2K/12K") == 0);
}

static void test_v2_usage_packet_formats_low_remaining_reset_hint(void)
{
    const char *json =
        "{"
        "\"source\":\"codex\","
        "\"state\":\"busy\","
        "\"ts\":1780300800000,"
        "\"usage\":{\"codex5hRemainingPercent\":15,\"codex5hResetAt\":1780303500000,\"codex7dRemainingPercent\":60},"
        "\"v\":2"
        "}";

    vibe_status_packet_t packet;
    vibe_display_usage_summary_t usage;
    vibe_status_default(&packet);

    assert(parse(json, &packet));
    assert(packet.codex_5h_remaining_percent == 15);
    assert(packet.codex_5h_reset_at_ms == 1780303500000LL);

    vibe_display_format_usage_summary(&packet, &usage);
    assert(strcmp(usage.five_hour, "5H 15%") == 0);
    assert(strcmp(usage.weekly, "7D 60%") == 0);
    assert(strcmp(usage.reset_hint, "5H RESET 45m") == 0);
}

static void test_v2_usage_packet_accepts_legacy_context_remaining(void)
{
    const char *json =
        "{"
        "\"activeCount\":1,"
        "\"source\":\"codex\","
        "\"state\":\"busy\","
        "\"tasks\":["
        "{\"contextRemainingPercent\":75,\"source\":\"codex\",\"state\":\"busy\",\"title\":\"vibe-light\"}"
        "],"
        "\"v\":2"
        "}";

    vibe_status_packet_t packet;
    vibe_display_task_row_t row;
    vibe_status_default(&packet);

    assert(parse(json, &packet));
    assert(packet.tasks[0].context_used_percent == 25);

    vibe_display_format_task_row(&packet.tasks[0], 0, &row);
    assert(strcmp(row.trailing, "CTX 25%") == 0);
}

static void test_health_payload_reports_backlight_and_last_parse_error(void)
{
    char payload[256];
    vibe_health_snapshot_t snapshot = {
        .animation_tick = 42,
        .backlight_on = true,
        .connected = true,
        .device = "VibeLight-S3",
        .free_heap_bytes = 4218880,
        .last_parse_error = "invalid JSON",
        .last_state = "busy",
        .min_free_heap_bytes = 3981312,
        .uptime_ms = 12000,
    };

    int written = vibe_health_format_json(payload, sizeof(payload), &snapshot);

    assert(written > 0);
    assert(strstr(payload, "\"backlightOn\":true") != NULL);
    assert(strstr(payload, "\"lastParseError\":\"invalid JSON\"") != NULL);
    assert(strstr(payload, "\"lastState\":\"busy\"") != NULL);

    snapshot.last_parse_error = "";
    written = vibe_health_format_json(payload, sizeof(payload), &snapshot);

    assert(written > 0);
    assert(strstr(payload, "lastParseError") == NULL);
}

static void test_unknown_states_fall_back_to_idle(void)
{
    const char *json =
        "{"
        "\"source\":\"codex\","
        "\"state\":\"surprised\","
        "\"tasks\":[{\"source\":\"codex\",\"state\":\"confused\",\"title\":\"odd\"}],"
        "\"ts\":1780300800000,"
        "\"v\":2"
        "}";

    vibe_status_packet_t packet;
    vibe_status_default(&packet);

    assert(parse(json, &packet));
    assert(packet.state == VIBE_DISPLAY_IDLE);
    assert(strcmp(packet.state_text, "idle") == 0);
    assert(packet.task_count == 1);
    assert(packet.tasks[0].state == VIBE_DISPLAY_IDLE);
    assert(strcmp(packet.tasks[0].state_text, "idle") == 0);
}

static void test_utf8_decoder_reads_chinese_codepoints(void)
{
    const char *text = "你来验证下";
    const char *cursor = text;
    uint32_t codepoint = 0;

    assert(vibe_utf8_decode_next(&cursor, &codepoint) == 3);
    assert(codepoint == 0x4F60);
    assert(vibe_utf8_decode_next(&cursor, &codepoint) == 3);
    assert(codepoint == 0x6765);
    assert(vibe_utf8_decode_next(&cursor, &codepoint) == 3);
    assert(codepoint == 0x9A8C);
}

static void test_utf8_decoder_handles_truncated_sequences(void)
{
    const char truncated_two_byte[] = {(char)0xC2, '\0'};
    const char truncated_three_byte[] = {(char)0xE4, (char)0xBD, '\0'};
    const char truncated_four_byte[] = {(char)0xF0, (char)0x9F, (char)0x98, '\0'};
    const char *cursor = truncated_two_byte;
    uint32_t codepoint = 0;

    assert(vibe_utf8_decode_next(&cursor, &codepoint) == 1);
    assert(codepoint == '?');
    assert(*cursor == '\0');

    cursor = truncated_three_byte;
    assert(vibe_utf8_decode_next(&cursor, &codepoint) == 1);
    assert(codepoint == '?');
    assert((unsigned char)*cursor == 0xBD);

    cursor = truncated_four_byte;
    assert(vibe_utf8_decode_next(&cursor, &codepoint) == 1);
    assert(codepoint == '?');
    assert((unsigned char)*cursor == 0x9F);
}

static void test_invalid_packets_are_rejected_without_mutation(void)
{
    vibe_status_packet_t packet;
    vibe_status_default(&packet);
    strcpy(packet.source, "sentinel");
    packet.state = VIBE_DISPLAY_ERROR;

    assert(!parse("{\"source\":\"codex\",\"v\":2}", &packet));
    assert(strcmp(packet.source, "sentinel") == 0);
    assert(packet.state == VIBE_DISPLAY_ERROR);

    assert(!parse("{not-json", &packet));
    assert(strcmp(packet.source, "sentinel") == 0);
    assert(packet.state == VIBE_DISPLAY_ERROR);
}

static void test_display_model_detects_duplicate_packets(void)
{
    const char *json =
        "{"
        "\"activeCount\":3,"
        "\"detail\":\"2 running / 1 waiting\","
        "\"source\":\"codex\","
        "\"state\":\"waiting\","
        "\"tasks\":["
        "{\"detail\":\"needs confirm\",\"source\":\"codex\",\"state\":\"waiting\",\"title\":\"approval\"},"
        "{\"detail\":\"sync BLE\",\"source\":\"codex\",\"state\":\"busy\",\"title\":\"desktop\"}"
        "],"
        "\"ts\":1780300800000,"
        "\"v\":2,"
        "\"waitingCount\":1"
        "}";

    vibe_status_packet_t packet;
    vibe_status_default(&packet);
    assert(parse(json, &packet));

    vibe_display_signature_t signature;
    vibe_display_signature_reset(&signature);
    assert(vibe_display_should_render(&signature, &packet));
    assert(!vibe_display_should_render(&signature, &packet));

    packet.waiting_count = 2;
    assert(vibe_display_should_render(&signature, &packet));

    packet.timestamp_ms += 60000;
    assert(vibe_display_should_render(&signature, &packet));
}

static void test_display_model_formats_task_rows(void)
{
    vibe_status_task_t task = {
        .title = "approval",
        .source = "codex",
        .state = VIBE_DISPLAY_WAITING,
        .state_text = "waiting",
        .detail = "needs confirm",
    };
    vibe_display_task_row_t row;

    vibe_display_format_task_row(&task, 0, &row);

    assert(strcmp(row.badge, "WAIT") == 0);
    assert(strcmp(row.title, "approval") == 0);
    assert(strcmp(row.subtitle, "codex / needs confirm") == 0);
}

static void test_display_model_formats_empty_state_with_last_result(void)
{
    vibe_status_packet_t packet;
    vibe_display_empty_state_t empty;
    vibe_status_default(&packet);
    packet.state = VIBE_DISPLAY_IDLE;
    snprintf(packet.detail, sizeof(packet.detail), "%s", "LAST OK VIBE-LIGHT");

    vibe_display_format_empty_state(&packet, &empty);

    assert(strcmp(empty.label, "NO ACTIVE TASKS") == 0);
    assert(strcmp(empty.detail, "LAST OK VIBE-LIGHT") == 0);
    assert(empty.detail_scale == 2);
    assert(empty.detail_max_width <= 288);
    assert(empty.quiet_header);
}

static void test_display_model_formats_running_task_duration(void)
{
    vibe_status_task_t task = {
        .title = "desktop",
        .source = "codex",
        .state = VIBE_DISPLAY_BUSY,
        .state_text = "busy",
        .detail = "make quick",
        .context_used_percent = 90,
        .updated_at_ms = 1780300608000LL,
    };
    vibe_display_task_row_t row;

    vibe_display_format_task_row_at(&task, 1780300800000LL, 0, &row);

    assert(strcmp(row.trailing, "RUN 03:12") == 0);
}

static void test_display_model_rotates_running_task_context_usage(void)
{
    vibe_status_task_t task = {
        .title = "desktop",
        .source = "codex",
        .state = VIBE_DISPLAY_BUSY,
        .state_text = "busy",
        .detail = "make quick",
        .context_used_percent = 74,
        .updated_at_ms = 1780300608000LL,
    };
    vibe_display_task_row_t row;

    vibe_display_format_task_row_at_phase(&task, 1780300800000LL, 0, 0, &row);
    assert(strcmp(row.trailing, "RUN 03:12") == 0);

    vibe_display_format_task_row_at_phase(&task, 1780300800000LL, 0, 36, &row);
    assert(strcmp(row.trailing, "CTX 74%") == 0);
}

static void test_display_model_prioritizes_high_context_usage(void)
{
    vibe_status_task_t task = {
        .title = "desktop",
        .source = "codex",
        .state = VIBE_DISPLAY_BUSY,
        .state_text = "busy",
        .detail = "make quick",
        .context_used_percent = 90,
        .updated_at_ms = 1780300608000LL,
    };
    vibe_display_task_row_t row;

    vibe_display_format_task_row_at_phase(&task, 1780300800000LL, 0, 0, &row);
    assert(strcmp(row.trailing, "RUN 03:12") == 0);

    vibe_display_format_task_row_at_phase(&task, 1780300800000LL, 0, 12, &row);
    assert(strcmp(row.trailing, "CTX 90%") == 0);
}

static void test_display_model_formats_waiting_task_duration(void)
{
    vibe_status_task_t task = {
        .title = "approval",
        .source = "codex",
        .state = VIBE_DISPLAY_WAITING,
        .state_text = "waiting",
        .detail = "APPROVE Bash",
        .context_used_percent = 74,
        .updated_at_ms = 1780300732000LL,
    };
    vibe_display_task_row_t row;

    vibe_display_format_task_row_at(&task, 1780300800000LL, 0, &row);

    assert(strcmp(row.trailing, "WAIT 01:08") == 0);
}

static void test_display_model_formats_recent_task_freshness(void)
{
    vibe_status_task_t task = {
        .title = "firmware",
        .source = "codex",
        .state = VIBE_DISPLAY_ERROR,
        .state_text = "error",
        .detail = "failed build",
        .context_used_percent = 61,
        .updated_at_ms = 1780300680000LL,
    };
    vibe_display_task_row_t row;

    vibe_display_format_task_row_at(&task, 1780300800000LL, 0, &row);

    assert(strcmp(row.trailing, "2m ago") == 0);
}

static void test_display_model_shows_detail_for_every_task_with_detail(void)
{
    vibe_status_task_t busy_task = {
        .title = "desktop",
        .source = "codex",
        .state = VIBE_DISPLAY_BUSY,
        .state_text = "busy",
        .detail = "sync BLE",
    };
    vibe_status_task_t quiet_task = {
        .title = "docs",
        .source = "codex",
        .state = VIBE_DISPLAY_BUSY,
        .state_text = "busy",
        .detail = "",
    };

    assert(vibe_display_should_render_task_detail(&busy_task));
    assert(!vibe_display_should_render_task_detail(&quiet_task));
    assert(!vibe_display_should_render_task_detail(NULL));
}

static void test_display_model_formats_compact_count_summary(void)
{
    vibe_status_packet_t packet;
    vibe_display_count_summary_t summary;

    vibe_status_default(&packet);
    packet.active_count = 12;
    packet.waiting_count = 3;
    packet.error_count = 0;

    vibe_display_format_count_summary(&packet, &summary);

    assert(strcmp(summary.active, "A12") == 0);
    assert(strcmp(summary.waiting, "W3") == 0);
    assert(strcmp(summary.error, "E0") == 0);
    assert(strlen(summary.active) < VIBE_DISPLAY_COUNT_TEXT_MAX);
    assert(strlen(summary.waiting) < VIBE_DISPLAY_COUNT_TEXT_MAX);
    assert(strlen(summary.error) < VIBE_DISPLAY_COUNT_TEXT_MAX);
}

static void test_display_model_formats_maze_count_text(void)
{
    vibe_status_packet_t packet;
    vibe_display_maze_count_text_t text;

    vibe_status_default(&packet);
    packet.active_count = 12;
    packet.waiting_count = 3;
    packet.error_count = 0;

    vibe_display_format_maze_count_text(&packet, &text);

    assert(strcmp(text.active, "ACTIVE 12") == 0);
    assert(strcmp(text.waiting, "WAIT 3") == 0);
    assert(strcmp(text.error, "ERR 0") == 0);
    assert(strlen(text.active) < sizeof(text.active));
    assert(strlen(text.waiting) < sizeof(text.waiting));
    assert(strlen(text.error) < sizeof(text.error));
}

static void test_display_model_formats_live_maze_score(void)
{
    char score[VIBE_DISPLAY_MAZE_SCORE_TEXT_MAX];
    const int single_actor_start_score = vibe_display_maze_score(0, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS);
    const int single_actor_later_score = vibe_display_maze_score(44 * VIBE_DISPLAY_ANIMATION_SUBSTEPS, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS);
    const int multi_actor_score = vibe_display_maze_score(44 * VIBE_DISPLAY_ANIMATION_SUBSTEPS, 5, 5, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS);
    const int score_after_visual_reset = vibe_display_maze_score(730, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS);

    assert(single_actor_start_score == 10);
    assert(single_actor_later_score > single_actor_start_score);
    assert(multi_actor_score > single_actor_later_score);
    assert(score_after_visual_reset == 2300);

    vibe_display_format_maze_score_text(single_actor_later_score, score, sizeof(score));

    assert(strcmp(score, "000530") == 0);
    assert(strlen(score) < VIBE_DISPLAY_MAZE_SCORE_TEXT_MAX);
}

static void test_display_model_tracks_maze_high_score(void)
{
    vibe_display_maze_high_score_t high_score;
    char text[VIBE_DISPLAY_MAZE_SCORE_TEXT_MAX];

    vibe_display_maze_high_score_init(&high_score, 1200);

    assert(high_score.value == 1200);
    assert(!high_score.dirty);
    assert(!vibe_display_maze_high_score_update(&high_score, 530));
    assert(high_score.value == 1200);
    assert(!high_score.dirty);
    assert(vibe_display_maze_high_score_update(&high_score, 2300));
    assert(high_score.value == 2300);
    assert(high_score.dirty);

    vibe_display_format_maze_score_text(high_score.value, text, sizeof(text));

    assert(strcmp(text, "002300") == 0);

    vibe_display_format_maze_score_text(1000000, text, sizeof(text));

    assert(strcmp(text, "999999") == 0);
}

static void test_display_model_formats_live_maze_level(void)
{
    char text[VIBE_DISPLAY_MAZE_LEVEL_TEXT_MAX];

    assert(vibe_display_maze_level(0, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS) == 1);
    assert(vibe_display_maze_level(729, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS) == 1);
    assert(vibe_display_maze_level(730, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS) == 2);
    assert(vibe_display_maze_level(376, 2, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS) == 2);

    vibe_display_format_maze_level_text(2, text, sizeof(text));

    assert(strcmp(text, "2") == 0);

    vibe_display_format_maze_level_text(1000, text, sizeof(text));

    assert(strcmp(text, "99") == 0);
}

static void test_display_model_preserves_animation_tick_while_busy(void)
{
    assert(vibe_display_should_preserve_animation_tick(VIBE_DISPLAY_BUSY, VIBE_DISPLAY_BUSY, true));
    assert(vibe_display_should_preserve_animation_tick(VIBE_DISPLAY_WAITING, VIBE_DISPLAY_WAITING, true));
    assert(!vibe_display_should_preserve_animation_tick(VIBE_DISPLAY_IDLE, VIBE_DISPLAY_BUSY, false));
    assert(!vibe_display_should_preserve_animation_tick(VIBE_DISPLAY_BUSY, VIBE_DISPLAY_BUSY, false));
    assert(!vibe_display_should_preserve_animation_tick(VIBE_DISPLAY_BUSY, VIBE_DISPLAY_WAITING, true));
}

static void test_display_model_top_overlays_do_not_erase_maze_lines(void)
{
    const int score_y = VIBE_DISPLAY_MAZE_SCORE_CLEAR_Y;
    const int score_h = VIBE_DISPLAY_MAZE_SCORE_CLEAR_H;
    const int score_w = VIBE_DISPLAY_MAZE_SCORE_RIGHT_X - VIBE_DISPLAY_MAZE_SCORE_LEFT_X + 1;
    const int high_score_w = VIBE_DISPLAY_MAZE_HIGH_SCORE_RIGHT_X - VIBE_DISPLAY_MAZE_HIGH_SCORE_LEFT_X + 1;
    const int level_w = VIBE_DISPLAY_MAZE_LEVEL_RIGHT_X - VIBE_DISPLAY_MAZE_LEVEL_LEFT_X + 1;

    assert(!reference_maze_color_intersects_rect(0x047f,
                                                 VIBE_DISPLAY_MAZE_SCORE_LEFT_X,
                                                 score_y,
                                                 score_w,
                                                 score_h));
    assert(!reference_maze_color_intersects_rect(0x047f,
                                                 VIBE_DISPLAY_MAZE_HIGH_SCORE_LEFT_X,
                                                 score_y,
                                                 high_score_w,
                                                 score_h));
    assert(!reference_maze_long_color_intersects_rect(0x047f,
                                                      200,
                                                      VIBE_DISPLAY_MAZE_LEVEL_LEFT_X,
                                                      VIBE_DISPLAY_MAZE_LEVEL_CLEAR_Y,
                                                      level_w,
                                                      VIBE_DISPLAY_MAZE_LEVEL_CLEAR_H));
}

static void test_display_model_score_value_keeps_gap_above_maze_top_line(void)
{
    const int top_maze_line_y = reference_maze_min_long_color_y(0x047f, 200);

    assert(top_maze_line_y > 0);
    assert(VIBE_DISPLAY_MAZE_SCORE_VALUE_Y + VIBE_DISPLAY_MAZE_SCORE_VALUE_H + 2 <= top_maze_line_y);
    assert(VIBE_DISPLAY_MAZE_SCORE_CLEAR_Y + VIBE_DISPLAY_MAZE_SCORE_CLEAR_H + 2 <= top_maze_line_y);
    assert(VIBE_DISPLAY_MAZE_SCORE_LEFT_X == 16);
}

static void test_display_model_animates_busy_center_stage(void)
{
    vibe_display_animation_frame_t frame0;
    vibe_display_animation_frame_t frame1;
    vibe_display_animation_frame_t wrapped;
    const int left = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_PATH_INSET;
    const int right = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_STAGE_W - VIBE_DISPLAY_MAZE_PATH_INSET;
    const int top = VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_BORDER_GAP;
    const int bottom = VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_FRAME_H - VIBE_DISPLAY_MAZE_BORDER_GAP;

    assert(vibe_display_animation_enabled(VIBE_DISPLAY_BUSY));
    assert(!vibe_display_animation_enabled(VIBE_DISPLAY_WAITING));
    assert(!vibe_display_animation_enabled(VIBE_DISPLAY_IDLE));
    assert(vibe_display_phase_refresh_enabled(VIBE_DISPLAY_BUSY));
    assert(vibe_display_phase_refresh_enabled(VIBE_DISPLAY_WAITING));
    assert(!vibe_display_phase_refresh_enabled(VIBE_DISPLAY_IDLE));

    vibe_display_animation_frame(0, 1, &frame0);
    vibe_display_animation_frame(1, 1, &frame1);
    vibe_display_animation_frame(VIBE_DISPLAY_ANIMATION_PATH_STEPS * VIBE_DISPLAY_ANIMATION_SUBSTEPS, 1, &wrapped);

    assert(frame0.x == wrapped.x);
    assert(frame0.y == wrapped.y);
    assert(frame0.x >= left && frame0.x <= right);
    assert(frame0.y >= top && frame0.y <= bottom);
    assert(frame0.x == 15);
    assert(frame0.y == VIBE_DISPLAY_MAZE_STAGE_Y + 43);
    assert(frame0.direction == VIBE_DISPLAY_DIRECTION_RIGHT);
    assert(frame0.mouth_open);
    assert(!frame1.mouth_open);
    assert(frame0.x != frame1.x || frame0.y != frame1.y);
}

static void test_display_model_animates_through_maze_turns(void)
{
    vibe_display_animation_frame_t frame;
    const int left = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_PATH_INSET;
    const int right = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_STAGE_W - VIBE_DISPLAY_MAZE_PATH_INSET;
    const int top = VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_BORDER_GAP;
    const int bottom = VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_FRAME_H - VIBE_DISPLAY_MAZE_BORDER_GAP;
    bool saw_right = false;
    bool saw_left = false;
    bool saw_down = false;
    bool saw_up = false;

    for (int path_tick = 0; path_tick < VIBE_DISPLAY_ANIMATION_PATH_STEPS; path_tick++) {
        vibe_display_animation_actor_frame(path_tick * VIBE_DISPLAY_ANIMATION_SUBSTEPS, 0, 1, 1, &frame);
        saw_right = saw_right || frame.direction == VIBE_DISPLAY_DIRECTION_RIGHT;
        saw_left = saw_left || frame.direction == VIBE_DISPLAY_DIRECTION_LEFT;
        saw_down = saw_down || frame.direction == VIBE_DISPLAY_DIRECTION_DOWN;
        saw_up = saw_up || frame.direction == VIBE_DISPLAY_DIRECTION_UP;

        assert(frame.x >= left && frame.x <= right);
        assert(frame.y >= top && frame.y <= bottom);
        assert(frame_matches_reference_pellet(&frame));
    }

    assert(saw_right);
    assert(saw_left);
    assert(saw_down);
    assert(saw_up);
}

static void test_display_model_places_pellets_on_maze_centerline(void)
{
    vibe_display_animation_frame_t pellet0;
    vibe_display_animation_frame_t pellet1;
    vibe_display_animation_frame_t wrapped;
    const int left = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_PATH_INSET;
    const int right = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_STAGE_W - VIBE_DISPLAY_MAZE_PATH_INSET;
    const int top = VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_BORDER_GAP;
    const int bottom = VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_FRAME_H - VIBE_DISPLAY_MAZE_BORDER_GAP;

    assert(VIBE_DISPLAY_MAZE_WALL_THICKNESS == 1);
    assert(VIBE_DISPLAY_MAZE_PELLET_COUNT == 213);

    vibe_display_maze_pellet_position(0, VIBE_DISPLAY_MAZE_PELLET_COUNT, &pellet0);
    vibe_display_maze_pellet_position(1, VIBE_DISPLAY_MAZE_PELLET_COUNT, &pellet1);
    vibe_display_maze_pellet_position(VIBE_DISPLAY_MAZE_PELLET_COUNT, VIBE_DISPLAY_MAZE_PELLET_COUNT, &wrapped);

    assert(pellet0.x >= left && pellet0.x <= right);
    assert(pellet0.y >= top && pellet0.y <= bottom);
    assert(pellet0.x == wrapped.x);
    assert(pellet0.y == wrapped.y);
    assert(pellet0.y == pellet1.y || pellet0.x == pellet1.x);
    assert(pellet0.x != pellet1.x || pellet0.y != pellet1.y);
}

static void test_display_model_marks_reference_style_power_pellets(void)
{
    int power_count = 0;
    vibe_display_animation_frame_t dot;

    assert(VIBE_DISPLAY_MAZE_POWER_PELLET_RADIUS == 3);

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        if (vibe_display_maze_is_power_pellet(i, VIBE_DISPLAY_MAZE_PELLET_COUNT)) {
            power_count++;
        }
    }

    assert(power_count == 4);
    assert(vibe_display_maze_is_power_pellet(30, VIBE_DISPLAY_MAZE_PELLET_COUNT));
    assert(vibe_display_maze_is_power_pellet(31, VIBE_DISPLAY_MAZE_PELLET_COUNT));
    assert(vibe_display_maze_is_power_pellet(149, VIBE_DISPLAY_MAZE_PELLET_COUNT));
    assert(vibe_display_maze_is_power_pellet(150, VIBE_DISPLAY_MAZE_PELLET_COUNT));
    assert(!vibe_display_maze_is_power_pellet(1, VIBE_DISPLAY_MAZE_PELLET_COUNT));

    vibe_display_maze_pellet_position(30, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);
    assert(dot.x == 16 && dot.y == VIBE_DISPLAY_MAZE_STAGE_Y + 56);
    vibe_display_maze_pellet_position(31, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);
    assert(dot.x == 304 && dot.y == VIBE_DISPLAY_MAZE_STAGE_Y + 56);
    vibe_display_maze_pellet_position(149, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);
    assert(dot.x == 16 && dot.y == VIBE_DISPLAY_MAZE_STAGE_Y + 219);
    vibe_display_maze_pellet_position(150, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);
    assert(dot.x == 304 && dot.y == VIBE_DISPLAY_MAZE_STAGE_Y + 219);
}

static void test_display_model_spaces_pellets_evenly_by_lane(void)
{
    vibe_display_animation_frame_t dot;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);
        assert(dot.x >= 15 && dot.x <= 304);
        assert(dot.y >= VIBE_DISPLAY_MAZE_STAGE_Y + 43);
        assert(dot.y <= VIBE_DISPLAY_MAZE_STAGE_Y + 268);
    }
}

static void test_display_model_scales_maze_to_screen_edges(void)
{
    assert(VIBE_DISPLAY_MAZE_REFERENCE_MIN_X == 15);
    assert(VIBE_DISPLAY_MAZE_REFERENCE_MAX_X == 303);
    assert(vibe_display_maze_display_x(VIBE_DISPLAY_MAZE_REFERENCE_MIN_X) == 0);
    assert(vibe_display_maze_display_x(VIBE_DISPLAY_MAZE_REFERENCE_MAX_X) == VIBE_DISPLAY_MAZE_STAGE_W - 1);
    assert(vibe_display_maze_display_run_width(VIBE_DISPLAY_MAZE_REFERENCE_MIN_X, 289) == VIBE_DISPLAY_MAZE_STAGE_W);
}

static bool frame_matches_reference_pellet(const vibe_display_animation_frame_t *frame)
{
    return find_pellet_at_frame(frame) >= 0;
}

static int find_pellet_at_frame(const vibe_display_animation_frame_t *frame)
{
    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);
        if (frame->x == dot.x && frame->y == dot.y) {
            return i;
        }
    }
    return -1;
}

static int visible_pellet_count_at_tick(int tick, int actor_count)
{
    int count = 0;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        if (vibe_display_maze_pellet_visible(i, tick, actor_count, actor_count, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS)) {
            count++;
        }
    }

    return count;
}

static bool reference_maze_color_intersects_rect(uint16_t color, int x, int y, int w, int h)
{
    for (int i = 0; i < VIBE_REFERENCE_MAZE_RUN_COUNT; i++) {
        const vibe_reference_maze_run_t *run = &VIBE_REFERENCE_MAZE_RUNS[i];
        bool y_intersects = (int)run->y >= y && (int)run->y < y + h;
        bool x_intersects = (int)run->x < x + w && (int)run->x + (int)run->length > x;
        if (run->color == color && y_intersects && x_intersects) {
            return true;
        }
    }

    return false;
}

static bool reference_maze_long_color_intersects_rect(uint16_t color, int min_length, int x, int y, int w, int h)
{
    for (int i = 0; i < VIBE_REFERENCE_MAZE_RUN_COUNT; i++) {
        const vibe_reference_maze_run_t *run = &VIBE_REFERENCE_MAZE_RUNS[i];
        bool y_intersects = (int)run->y >= y && (int)run->y < y + h;
        bool x_intersects = (int)run->x < x + w && (int)run->x + (int)run->length > x;
        if (run->color == color && (int)run->length >= min_length && y_intersects && x_intersects) {
            return true;
        }
    }

    return false;
}

static int reference_maze_min_long_color_y(uint16_t color, int min_length)
{
    int min_y = 10000;

    for (int i = 0; i < VIBE_REFERENCE_MAZE_RUN_COUNT; i++) {
        const vibe_reference_maze_run_t *run = &VIBE_REFERENCE_MAZE_RUNS[i];
        if (run->color == color && (int)run->length >= min_length && (int)run->y < min_y) {
            min_y = (int)run->y;
        }
    }

    return min_y == 10000 ? -1 : min_y;
}

static void test_display_model_animates_only_on_reference_pellets(void)
{
    const int active_counts[] = {1, 2, 5};

    for (size_t active_index = 0; active_index < sizeof(active_counts) / sizeof(active_counts[0]); active_index++) {
        int active_count = active_counts[active_index];
        vibe_display_animation_frame_t previous;
        vibe_display_animation_actor_frame(0, 0, 1, active_count, &previous);
        assert(frame_matches_reference_pellet(&previous));

        for (int path_tick = 1; path_tick < VIBE_DISPLAY_ANIMATION_PATH_STEPS; path_tick++) {
            vibe_display_animation_frame_t current;
            vibe_display_animation_actor_frame(path_tick * VIBE_DISPLAY_ANIMATION_SUBSTEPS, 0, 1, active_count, &current);
            assert(frame_matches_reference_pellet(&current));
            assert(abs(current.x - previous.x) <= 2 || abs(current.y - previous.y) <= 2);
            assert(abs(current.x - previous.x) <= 50);
            assert(abs(current.y - previous.y) <= 45);
            previous = current;
        }
    }
}

static void test_display_model_smooths_between_pellet_nodes(void)
{
    vibe_display_animation_frame_t start;
    vibe_display_animation_frame_t halfway;
    vibe_display_animation_frame_t next;

    assert(VIBE_DISPLAY_ANIMATION_SUBSTEPS == 2);
    vibe_display_animation_actor_frame(0, 0, 1, 1, &start);
    vibe_display_animation_actor_frame(1, 0, 1, 1, &halfway);
    vibe_display_animation_actor_frame(VIBE_DISPLAY_ANIMATION_SUBSTEPS, 0, 1, 1, &next);

    assert(frame_matches_reference_pellet(&start));
    assert(!frame_matches_reference_pellet(&halfway));
    assert(frame_matches_reference_pellet(&next));
    assert(halfway.y == start.y);
    assert(halfway.x > start.x && halfway.x < next.x);
    assert(halfway.direction == VIBE_DISPLAY_DIRECTION_RIGHT);
}

static void test_display_model_resets_pellets_after_full_path_cycle(void)
{
    vibe_display_animation_frame_t frame;
    const int eaten_tick = 43 * VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    int reset_tick = -1;
    vibe_display_animation_actor_frame(eaten_tick, 0, 1, 1, &frame);
    int pellet_index = find_pellet_at_frame(&frame);
    int next_pellet_index;

    assert(VIBE_DISPLAY_ANIMATION_PERIOD_MS == 240);
    assert(VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS == 850);
    assert(pellet_index >= 0);
    vibe_display_animation_actor_frame(eaten_tick + 1, 0, 1, 1, &frame);
    assert(!frame_matches_reference_pellet(&frame));
    vibe_display_animation_actor_frame(eaten_tick + VIBE_DISPLAY_ANIMATION_SUBSTEPS, 0, 1, 1, &frame);
    next_pellet_index = find_pellet_at_frame(&frame);
    assert(next_pellet_index >= 0);
    assert(!vibe_display_maze_pellet_visible(next_pellet_index, eaten_tick + 1, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS));
    assert(!vibe_display_maze_pellet_visible(next_pellet_index, eaten_tick + VIBE_DISPLAY_ANIMATION_SUBSTEPS, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS));
    assert(!vibe_display_maze_pellet_visible(pellet_index, eaten_tick, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS));

    for (int tick = 0; tick < VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS; tick++) {
        if (visible_pellet_count_at_tick(tick, 1) == 0) {
            reset_tick = tick + 1;
            break;
        }
    }

    assert(reset_tick > eaten_tick);
    assert(vibe_display_maze_pellet_visible(pellet_index, reset_tick + eaten_tick - 2, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS));
    assert(!vibe_display_maze_pellet_visible(pellet_index, reset_tick + eaten_tick - 1, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS));
}

static void test_display_model_starts_multi_actor_round_with_visible_pellets(void)
{
    int visible_count = visible_pellet_count_at_tick(0, VIBE_STATUS_MAX_TASKS);

    assert(visible_count >= VIBE_DISPLAY_MAZE_PELLET_COUNT - VIBE_STATUS_MAX_TASKS);
}

static void test_display_model_eats_pellets_crossed_between_path_nodes(void)
{
    const int tick_crossing_top_lane = 15 * VIBE_DISPLAY_ANIMATION_SUBSTEPS + 1;

    assert(!vibe_display_maze_pellet_visible(1, 1, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS));
    assert(!vibe_display_maze_pellet_visible(48, tick_crossing_top_lane, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS));
    assert(!vibe_display_maze_pellet_visible(47, tick_crossing_top_lane, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS));
    assert(!vibe_display_maze_pellet_visible(46, tick_crossing_top_lane, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS));
    assert(vibe_display_maze_pellet_visible(45, tick_crossing_top_lane, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS));
}

static void test_display_model_resets_multi_actor_round_when_all_pellets_are_eaten(void)
{
    int all_eaten_tick = -1;

    for (int tick = 0; tick < VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS; tick++) {
        if (visible_pellet_count_at_tick(tick, VIBE_STATUS_MAX_TASKS) == 0) {
            all_eaten_tick = tick;
            break;
        }
    }

    assert(all_eaten_tick > 0);
    assert(visible_pellet_count_at_tick(all_eaten_tick + 1, VIBE_STATUS_MAX_TASKS) >=
           VIBE_DISPLAY_MAZE_PELLET_COUNT - VIBE_STATUS_MAX_TASKS);
}

static void test_display_model_uses_expected_reset_ticks_per_actor_count(void)
{
    const int expected_reset_ticks[] = {0, 730, 376, 275, 198, 164};

    for (int actor_count = 1; actor_count <= VIBE_STATUS_MAX_TASKS; actor_count++) {
        int all_eaten_tick = -1;

        for (int tick = 0; tick < VIBE_DISPLAY_MAZE_PELLET_RESET_TICKS; tick++) {
            if (visible_pellet_count_at_tick(tick, actor_count) == 0) {
                all_eaten_tick = tick;
                break;
            }
        }

        assert(all_eaten_tick + 1 == expected_reset_ticks[actor_count]);
        assert(visible_pellet_count_at_tick(expected_reset_ticks[actor_count], actor_count) >=
               VIBE_DISPLAY_MAZE_PELLET_COUNT - actor_count);
    }
}

static void test_display_model_leaves_bottom_gate_clear_of_pellets(void)
{
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        bool near_ghost_house_gate = dot.x >= 148 && dot.x <= 172 &&
                                     dot.y >= maze_y + 126 && dot.y <= maze_y + 145;
        bool near_bottom_label_panel = dot.y >= maze_y + 278;
        assert(!near_ghost_house_gate);
        assert(!near_bottom_label_panel);
    }
}

static void test_display_model_keeps_pellets_outside_reference_wall_cores(void)
{
    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t current;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &current);
        for (int j = i + 1; j < VIBE_DISPLAY_MAZE_PELLET_COUNT; j++) {
            vibe_display_animation_frame_t other;
            vibe_display_maze_pellet_position(j, VIBE_DISPLAY_MAZE_PELLET_COUNT, &other);
            assert(current.x != other.x || current.y != other.y);
        }
    }
}

static void test_display_model_places_pellets_on_reference_side_corridors(void)
{
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;
    int top_row_count = 0;
    int upper_row_count = 0;
    int mid_row_count = 0;
    int bottom_row_count = 0;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        if (dot.y == maze_y + 43) {
            top_row_count++;
        }
        if (dot.y == maze_y + 71) {
            upper_row_count++;
        }
        if (dot.y == maze_y + 196) {
            mid_row_count++;
        }
        if (dot.y == maze_y + 250) {
            bottom_row_count++;
        }
    }

    assert(top_row_count == 26);
    assert(upper_row_count == 28);
    assert(mid_row_count == 23);
    assert(bottom_row_count == 22);
}

static void test_display_model_places_pellets_on_reference_vertical_corridors(void)
{
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;
    int left_column_count = 0;
    int left_inner_column_count = 0;
    int right_inner_column_count = 0;
    int right_column_count = 0;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        if (dot.x == 77 && dot.y >= maze_y + 43 && dot.y <= maze_y + 250) {
            left_column_count++;
        }
        if (dot.x == 109 && dot.y >= maze_y + 80 && dot.y <= maze_y + 250) {
            left_inner_column_count++;
        }
        if (dot.x == 211 && dot.y >= maze_y + 80 && dot.y <= maze_y + 250) {
            right_inner_column_count++;
        }
        if (dot.x == 243 && dot.y >= maze_y + 43 && dot.y <= maze_y + 250) {
            right_column_count++;
        }
    }

    assert(left_column_count == 23);
    assert(left_inner_column_count == 8);
    assert(right_inner_column_count == 4);
    assert(right_column_count == 22);
}

static void test_display_model_keeps_left_corridor_pellets_before_g_wall(void)
{
    int left_power_count = 0;
    int right_power_count = 0;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        if (vibe_display_maze_is_power_pellet(i, VIBE_DISPLAY_MAZE_PELLET_COUNT) && dot.x == 16) {
            left_power_count++;
        }
        if (vibe_display_maze_is_power_pellet(i, VIBE_DISPLAY_MAZE_PELLET_COUNT) && dot.x == 304) {
            right_power_count++;
        }
    }

    assert(left_power_count == 2);
    assert(right_power_count == 2);
}

static void test_display_model_keeps_maze_path_inside_flush_border(void)
{
    vibe_display_animation_frame_t frame;

    assert(VIBE_DISPLAY_MAZE_STAGE_X == 0);
    assert(VIBE_DISPLAY_MAZE_STAGE_Y == 90);
    assert(VIBE_DISPLAY_MAZE_STAGE_W == 320);
    assert(VIBE_DISPLAY_MAZE_STAGE_H == 320);
    assert(VIBE_DISPLAY_MAZE_FRAME_H == 320);
    assert(VIBE_DISPLAY_MAZE_BORDER_GAP == 8);
    assert(VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_STAGE_W == 320);

    for (int tick = 0; tick < VIBE_DISPLAY_ANIMATION_PATH_STEPS; tick++) {
        vibe_display_animation_actor_frame(tick, 0, 1, 1, &frame);

        assert(frame.x >= VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_PATH_INSET);
        assert(frame.x <= VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_STAGE_W - VIBE_DISPLAY_MAZE_PATH_INSET);
        assert(frame.y >= VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_PATH_INSET);
        assert(frame.y <= VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_FRAME_H - VIBE_DISPLAY_MAZE_PATH_INSET);
    }
}

static void test_display_model_creates_actor_per_task(void)
{
    vibe_display_animation_frame_t first;
    vibe_display_animation_frame_t second;
    vibe_display_animation_frame_t fallback;
    const int left = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_PATH_INSET;
    const int right = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_STAGE_W - VIBE_DISPLAY_MAZE_PATH_INSET;

    assert(vibe_display_animation_actor_count(0, 0) == 1);
    assert(vibe_display_animation_actor_count(0, 3) == 3);
    assert(vibe_display_animation_actor_count(2, 5) == 2);
    assert(vibe_display_animation_actor_count(9, 9) == VIBE_STATUS_MAX_TASKS);

    vibe_display_animation_actor_frame(0, 0, 2, 2, &first);
    vibe_display_animation_actor_frame(0, 1, 2, 2, &second);
    vibe_display_animation_actor_frame(0, 2, 2, 2, &fallback);

    assert(first.y != second.y);
    assert(fallback.y == second.y);
    assert(first.x >= left && first.x <= right);
    assert(second.x >= left && second.x <= right);
}

static void test_display_model_animation_step_stays_on_discrete_nodes(void)
{
    assert(vibe_display_animation_step(0) == 1);
    assert(vibe_display_animation_step(1) == 1);
    assert(vibe_display_animation_step(2) == 1);
    assert(vibe_display_animation_step(5) == 1);
}

static void test_display_model_actor_shape_faces_travel_direction(void)
{
    vibe_display_animation_frame_t right = {
        .x = 120,
        .y = 140,
        .direction = VIBE_DISPLAY_DIRECTION_RIGHT,
        .mouth_open = true,
    };
    vibe_display_animation_frame_t left = {
        .x = 120,
        .y = 140,
        .direction = VIBE_DISPLAY_DIRECTION_LEFT,
        .mouth_open = true,
    };
    vibe_display_animation_actor_t right_actor;
    vibe_display_animation_actor_t left_actor;

    vibe_display_animation_actor_shape(&right, &right_actor);
    vibe_display_animation_actor_shape(&left, &left_actor);

    assert(right_actor.mouth_tip_x > right.x);
    assert(right_actor.mouth_a_x == right.x);
    assert(right_actor.mouth_b_x == right.x);
    assert(right_actor.eye_x > right.x);
    assert(right_actor.eye_y < right.y);

    assert(left_actor.mouth_tip_x < left.x);
    assert(left_actor.mouth_a_x == left.x);
    assert(left_actor.mouth_b_x == left.x);
    assert(left_actor.eye_x < left.x);
    assert(left_actor.eye_y < left.y);
}

static void test_display_model_uses_reference_pacman_actor_style(void)
{
    assert(VIBE_DISPLAY_CODEX_ACTOR_EYE_RADIUS == 0);
    assert(VIBE_DISPLAY_CODEX_ACTOR_RADIUS == 7);
    assert(VIBE_DISPLAY_CODEX_ACTOR_RADIUS < VIBE_DISPLAY_MAZE_PATH_INSET);
    assert(VIBE_DISPLAY_MAZE_POWER_PELLET_RADIUS < VIBE_DISPLAY_CODEX_ACTOR_RADIUS);
}

static void test_display_model_animates_center_ghost_subtly(void)
{
    vibe_display_maze_ghost_frame_t open;
    vibe_display_maze_ghost_frame_t shifted;
    vibe_display_maze_ghost_frame_t blink;

    vibe_display_maze_ghost_frame(0, &open);
    vibe_display_maze_ghost_frame(1, &shifted);
    vibe_display_maze_ghost_frame(VIBE_DISPLAY_MAZE_GHOST_BLINK_TICKS - 1, &blink);

    assert(VIBE_DISPLAY_MAZE_GHOST_BLINK_TICKS == 20);
    assert(open.x == VIBE_DISPLAY_MAZE_GHOST_CENTER_X);
    assert(open.y == VIBE_DISPLAY_MAZE_GHOST_CENTER_Y);
    assert(!open.eyes_closed);
    assert(!shifted.eyes_closed);
    assert(blink.eyes_closed);
    assert(shifted.x >= VIBE_DISPLAY_MAZE_GHOST_CENTER_X - 1);
    assert(shifted.x <= VIBE_DISPLAY_MAZE_GHOST_CENTER_X + 1);
    assert(shifted.y >= VIBE_DISPLAY_MAZE_GHOST_CENTER_Y - 1);
    assert(shifted.y <= VIBE_DISPLAY_MAZE_GHOST_CENTER_Y + 1);
    assert(shifted.x != open.x || shifted.y != open.y);
}

static void test_display_model_formats_status_footer(void)
{
    vibe_status_packet_t packet;
    char footer[32];

    vibe_status_default(&packet);
    packet.version = 2;
    snprintf(packet.source, sizeof(packet.source), "%s", "codex");
    packet.state = VIBE_DISPLAY_BUSY;
    packet.active_count = 2;
    packet.waiting_count = 1;
    packet.error_count = 0;
    vibe_display_footer_text(&packet, footer, sizeof(footer));

    assert(strcmp(footer, "CODEX LIVE") == 0);

    packet.version = 1;
    vibe_display_footer_text(&packet, footer, sizeof(footer));

    assert(strcmp(footer, "CODEX LEGACY") == 0);

    packet.state = VIBE_DISPLAY_OFFLINE;
    vibe_display_footer_text(&packet, footer, sizeof(footer));

    assert(strcmp(footer, "OFFLINE") == 0);
}

static void test_display_model_keeps_task_panel_tight_to_screen_bottom(void)
{
    const int screen_h = 820;
    const int last_compact_row_y = VIBE_DISPLAY_TASK_ROW_Y + (VIBE_STATUS_MAX_TASKS - 1) * VIBE_DISPLAY_TASK_ROW_STRIDE;
    const int row_bottom = last_compact_row_y + VIBE_DISPLAY_TASK_ROW_TEXT_H;
    const int swatch_bottom = last_compact_row_y + VIBE_DISPLAY_TASK_SWATCH_Y_OFFSET + VIBE_DISPLAY_TASK_SWATCH_H;
    const int last_detail_row_y = VIBE_DISPLAY_TASK_ROW_Y + (VIBE_STATUS_MAX_TASKS - 1) * VIBE_DISPLAY_TASK_DETAIL_ROW_STRIDE;
    const int detail_bottom = last_detail_row_y + VIBE_DISPLAY_TASK_DETAIL_Y_OFFSET + VIBE_DISPLAY_TASK_DETAIL_TEXT_H;

    assert(VIBE_DISPLAY_TASK_PANEL_X == 0);
    assert(VIBE_DISPLAY_TASK_PANEL_W == 320);
    assert(VIBE_DISPLAY_TASK_PANEL_Y == VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_STAGE_H);
    assert(VIBE_DISPLAY_TASK_PANEL_Y + VIBE_DISPLAY_TASK_PANEL_H == screen_h);
    assert(VIBE_DISPLAY_TASK_ROW_Y > VIBE_DISPLAY_TASK_PANEL_Y);
    assert(row_bottom <= screen_h);
    assert(swatch_bottom <= screen_h);
    assert(detail_bottom <= screen_h);
    assert(VIBE_DISPLAY_TASK_ROW_TEXT_H >= 14);
    assert(VIBE_DISPLAY_TASK_ROW_STRIDE <= 48);
    assert(VIBE_DISPLAY_TASK_DETAIL_ROW_STRIDE <= 64);
    assert(VIBE_DISPLAY_TASK_DETAIL_Y_OFFSET > VIBE_DISPLAY_TASK_ROW_TEXT_H);
    assert(VIBE_DISPLAY_TASK_SWATCH_X > VIBE_DISPLAY_TASK_PANEL_X);
    assert(VIBE_DISPLAY_TASK_TEXT_X > VIBE_DISPLAY_TASK_SWATCH_X + VIBE_DISPLAY_TASK_SWATCH_W);
    assert(VIBE_DISPLAY_TASK_TEXT_X <= 20);
    assert(VIBE_DISPLAY_TASK_SWATCH_Y_OFFSET > 0);
    assert(VIBE_DISPLAY_TASK_SWATCH_W <= 6);
    assert(VIBE_DISPLAY_TASK_SWATCH_H <= VIBE_DISPLAY_TASK_ROW_STRIDE);
    assert(VIBE_DISPLAY_FOOTER_X == VIBE_DISPLAY_TASK_TEXT_X);
    assert(VIBE_DISPLAY_FOOTER_SCALE == 2);
    assert(VIBE_DISPLAY_FOOTER_BOTTOM_MARGIN >= 12);
    assert(VIBE_DISPLAY_FOOTER_BOTTOM_CLEAR_Y == VIBE_DISPLAY_FOOTER_Y + VIBE_DISPLAY_FOOTER_TEXT_H);
    assert(VIBE_DISPLAY_FOOTER_BOTTOM_CLEAR_Y < screen_h);
    assert(VIBE_DISPLAY_FOOTER_Y + VIBE_DISPLAY_FOOTER_TEXT_H + VIBE_DISPLAY_FOOTER_BOTTOM_MARGIN == screen_h);
}

int main(void)
{
    test_v1_status_packet();
    test_v2_task_list_packet();
    test_v2_usage_packet();
    test_v2_usage_packet_formats_low_remaining_reset_hint();
    test_v2_usage_packet_accepts_legacy_context_remaining();
    test_health_payload_reports_backlight_and_last_parse_error();
    test_unknown_states_fall_back_to_idle();
    test_utf8_decoder_reads_chinese_codepoints();
    test_utf8_decoder_handles_truncated_sequences();
    test_invalid_packets_are_rejected_without_mutation();
    test_display_model_detects_duplicate_packets();
    test_display_model_formats_task_rows();
    test_display_model_formats_empty_state_with_last_result();
    test_display_model_formats_running_task_duration();
    test_display_model_rotates_running_task_context_usage();
    test_display_model_prioritizes_high_context_usage();
    test_display_model_formats_waiting_task_duration();
    test_display_model_formats_recent_task_freshness();
    test_display_model_shows_detail_for_every_task_with_detail();
    test_display_model_formats_compact_count_summary();
    test_display_model_formats_maze_count_text();
    test_display_model_formats_live_maze_score();
    test_display_model_tracks_maze_high_score();
    test_display_model_formats_live_maze_level();
    test_display_model_preserves_animation_tick_while_busy();
    test_display_model_top_overlays_do_not_erase_maze_lines();
    test_display_model_score_value_keeps_gap_above_maze_top_line();
    test_display_model_animates_busy_center_stage();
    test_display_model_animates_through_maze_turns();
    test_display_model_places_pellets_on_maze_centerline();
    test_display_model_marks_reference_style_power_pellets();
    test_display_model_spaces_pellets_evenly_by_lane();
    test_display_model_scales_maze_to_screen_edges();
    test_display_model_animates_only_on_reference_pellets();
    test_display_model_smooths_between_pellet_nodes();
    test_display_model_resets_pellets_after_full_path_cycle();
    test_display_model_starts_multi_actor_round_with_visible_pellets();
    test_display_model_eats_pellets_crossed_between_path_nodes();
    test_display_model_resets_multi_actor_round_when_all_pellets_are_eaten();
    test_display_model_uses_expected_reset_ticks_per_actor_count();
    test_display_model_leaves_bottom_gate_clear_of_pellets();
    test_display_model_keeps_pellets_outside_reference_wall_cores();
    test_display_model_places_pellets_on_reference_side_corridors();
    test_display_model_places_pellets_on_reference_vertical_corridors();
    test_display_model_keeps_left_corridor_pellets_before_g_wall();
    test_display_model_keeps_maze_path_inside_flush_border();
    test_display_model_creates_actor_per_task();
    test_display_model_animation_step_stays_on_discrete_nodes();
    test_display_model_actor_shape_faces_travel_direction();
    test_display_model_uses_reference_pacman_actor_style();
    test_display_model_animates_center_ghost_subtly();
    test_display_model_formats_status_footer();
    test_display_model_keeps_task_panel_tight_to_screen_bottom();

    puts("vibe_status_parser_test: ok");
    return 0;
}
