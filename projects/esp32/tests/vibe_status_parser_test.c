#include "vibe_status.h"
#include "vibe_cjk_font.h"
#include "vibe_display_model.h"

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
        "{\"detail\":\"approve command\",\"source\":\"codex\",\"state\":\"waiting\",\"title\":\"vibe-light\"},"
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
    assert(strcmp(packet.tasks[1].source, "claude") == 0);
    assert(packet.tasks[1].state == VIBE_DISPLAY_BUSY);
    assert(packet.tasks[2].state == VIBE_DISPLAY_ERROR);
    assert(strcmp(packet.tasks[4].title, "extra-2") == 0);
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

static void test_display_model_delays_eaten_pellet_recovery(void)
{
    vibe_display_animation_frame_t frame;
    const int eaten_tick = 43 * VIBE_DISPLAY_ANIMATION_SUBSTEPS;
    vibe_display_animation_actor_frame(eaten_tick, 0, 1, 1, &frame);
    int pellet_index = find_pellet_at_frame(&frame);
    int next_pellet_index;

    assert(VIBE_DISPLAY_ANIMATION_PERIOD_MS == 240);
    assert(VIBE_DISPLAY_MAZE_PELLET_RECOVERY_MS == 5000);
    assert(VIBE_DISPLAY_MAZE_PELLET_RECOVERY_TICKS == 21);
    assert(pellet_index >= 0);
    vibe_display_animation_actor_frame(eaten_tick + 1, 0, 1, 1, &frame);
    assert(!frame_matches_reference_pellet(&frame));
    vibe_display_animation_actor_frame(eaten_tick + VIBE_DISPLAY_ANIMATION_SUBSTEPS, 0, 1, 1, &frame);
    next_pellet_index = find_pellet_at_frame(&frame);
    assert(next_pellet_index >= 0);
    assert(vibe_display_maze_pellet_visible(next_pellet_index, eaten_tick + 1, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RECOVERY_TICKS));
    assert(!vibe_display_maze_pellet_visible(next_pellet_index, eaten_tick + VIBE_DISPLAY_ANIMATION_SUBSTEPS, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RECOVERY_TICKS));
    assert(!vibe_display_maze_pellet_visible(pellet_index, eaten_tick, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RECOVERY_TICKS));
    assert(!vibe_display_maze_pellet_visible(pellet_index, eaten_tick + VIBE_DISPLAY_MAZE_PELLET_RECOVERY_TICKS, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RECOVERY_TICKS));
    assert(vibe_display_maze_pellet_visible(pellet_index, eaten_tick + VIBE_DISPLAY_MAZE_PELLET_RECOVERY_TICKS + 1, 1, 1, VIBE_DISPLAY_MAZE_PELLET_RECOVERY_TICKS));
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
    assert(VIBE_DISPLAY_MAZE_STAGE_Y == 82);
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

static void test_display_model_hides_timestamp_footer(void)
{
    vibe_status_packet_t packet;
    char footer[32];

    vibe_status_default(&packet);
    packet.timestamp_ms = 1780874713000LL;
    vibe_display_footer_text(&packet, footer, sizeof(footer));

    assert(strcmp(footer, "") == 0);
}

static void test_display_model_keeps_task_panel_tight_to_screen_bottom(void)
{
    const int screen_h = 820;
    const int last_compact_row_y = VIBE_DISPLAY_TASK_ROW_Y + (VIBE_STATUS_MAX_TASKS - 1) * VIBE_DISPLAY_TASK_ROW_STRIDE;
    const int row_bottom = last_compact_row_y + VIBE_DISPLAY_TASK_ROW_TEXT_H;
    const int swatch_bottom = last_compact_row_y + VIBE_DISPLAY_TASK_SWATCH_H;
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
    assert(VIBE_DISPLAY_TASK_SWATCH_W <= 4);
    assert(VIBE_DISPLAY_TASK_SWATCH_H <= VIBE_DISPLAY_TASK_ROW_STRIDE);
}

int main(void)
{
    test_v1_status_packet();
    test_v2_task_list_packet();
    test_unknown_states_fall_back_to_idle();
    test_utf8_decoder_reads_chinese_codepoints();
    test_utf8_decoder_handles_truncated_sequences();
    test_invalid_packets_are_rejected_without_mutation();
    test_display_model_detects_duplicate_packets();
    test_display_model_formats_task_rows();
    test_display_model_formats_compact_count_summary();
    test_display_model_formats_maze_count_text();
    test_display_model_animates_busy_center_stage();
    test_display_model_animates_through_maze_turns();
    test_display_model_places_pellets_on_maze_centerline();
    test_display_model_marks_reference_style_power_pellets();
    test_display_model_spaces_pellets_evenly_by_lane();
    test_display_model_scales_maze_to_screen_edges();
    test_display_model_animates_only_on_reference_pellets();
    test_display_model_smooths_between_pellet_nodes();
    test_display_model_delays_eaten_pellet_recovery();
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
    test_display_model_hides_timestamp_footer();
    test_display_model_keeps_task_panel_tight_to_screen_bottom();

    puts("vibe_status_parser_test: ok");
    return 0;
}
