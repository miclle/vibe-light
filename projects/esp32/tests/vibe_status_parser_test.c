#include "vibe_status.h"
#include "vibe_display_model.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool parse(const char *json, vibe_status_packet_t *packet)
{
    return vibe_status_parse_json((const uint8_t *)json, strlen(json), packet);
}

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
    vibe_display_animation_frame(VIBE_DISPLAY_ANIMATION_PATH_STEPS, 1, &wrapped);

    assert(frame0.x == wrapped.x);
    assert(frame0.y == wrapped.y);
    assert(frame0.x >= left && frame0.x <= right);
    assert(frame0.y >= top && frame0.y <= bottom);
    assert(frame0.x >= 150 && frame0.x <= 210);
    assert(frame0.y == VIBE_DISPLAY_MAZE_STAGE_Y + 238);
    assert(frame0.direction == VIBE_DISPLAY_DIRECTION_RIGHT);
    assert(frame0.mouth_open);
    assert(!frame1.mouth_open);
    assert(frame0.x != frame1.x || frame0.y != frame1.y);
}

static void test_display_model_animates_through_maze_turns(void)
{
    vibe_display_animation_frame_t frame;
    const int maze_x = VIBE_DISPLAY_MAZE_STAGE_X;
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;
    const int left = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_PATH_INSET;
    const int right = VIBE_DISPLAY_MAZE_STAGE_X + VIBE_DISPLAY_MAZE_STAGE_W - VIBE_DISPLAY_MAZE_PATH_INSET;
    const int top = VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_BORDER_GAP;
    const int bottom = VIBE_DISPLAY_MAZE_STAGE_Y + VIBE_DISPLAY_MAZE_FRAME_H - VIBE_DISPLAY_MAZE_BORDER_GAP;
    bool saw_right = false;
    bool saw_left = false;
    bool saw_down = false;
    bool saw_up = false;

    for (int tick = 0; tick < VIBE_DISPLAY_ANIMATION_PATH_STEPS; tick++) {
        vibe_display_animation_actor_frame(tick, 0, 1, 1, &frame);
        saw_right = saw_right || frame.direction == VIBE_DISPLAY_DIRECTION_RIGHT;
        saw_left = saw_left || frame.direction == VIBE_DISPLAY_DIRECTION_LEFT;
        saw_down = saw_down || frame.direction == VIBE_DISPLAY_DIRECTION_DOWN;
        saw_up = saw_up || frame.direction == VIBE_DISPLAY_DIRECTION_UP;

        assert(frame.x >= left && frame.x <= right);
        assert(frame.y >= top && frame.y <= bottom);

        bool inside_left_g_wall = frame.x >= maze_x + 48 && frame.x <= maze_x + 78 &&
                                  frame.y >= maze_y + 28 && frame.y <= maze_y + 58;
        bool inside_left_box = frame.x >= maze_x + 80 && frame.x <= maze_x + 110 &&
                               frame.y >= maze_y + 28 && frame.y <= maze_y + 58;
        bool inside_yellow_box = frame.x >= maze_x + 122 && frame.x <= maze_x + 150 &&
                                 frame.y >= maze_y + 30 && frame.y <= maze_y + 54;
        bool inside_center_box = frame.x >= maze_x + 158 && frame.x <= maze_x + 194 &&
                                 frame.y >= maze_y + 30 && frame.y <= maze_y + 50;
        bool inside_green_gate = frame.x >= maze_x + 200 && frame.x <= maze_x + 216 &&
                                 frame.y >= maze_y + 18 && frame.y <= maze_y + 58;
        bool inside_right_box = frame.x >= maze_x + 222 && frame.x <= maze_x + 253 &&
                                frame.y >= maze_y + 28 && frame.y <= maze_y + 58;
        bool inside_bottom_center_gate = frame.x >= maze_x + 148 && frame.x <= maze_x + 170 &&
                                         frame.y >= maze_y + 88 && frame.y <= maze_y + 94;

        assert(!inside_left_g_wall);
        assert(!inside_left_box);
        assert(!inside_yellow_box);
        assert(!inside_center_box);
        assert(!inside_green_gate);
        assert(!inside_right_box);
        assert(!inside_bottom_center_gate);
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
    assert(VIBE_DISPLAY_MAZE_PELLET_COUNT == 102);

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
    const int maze_x = VIBE_DISPLAY_MAZE_STAGE_X;
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;

    assert(VIBE_DISPLAY_MAZE_POWER_PELLET_RADIUS == 3);

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        if (vibe_display_maze_is_power_pellet(i, VIBE_DISPLAY_MAZE_PELLET_COUNT)) {
            power_count++;
        }
    }

    assert(power_count == 4);
    assert(vibe_display_maze_is_power_pellet(0, VIBE_DISPLAY_MAZE_PELLET_COUNT));
    assert(vibe_display_maze_is_power_pellet(21, VIBE_DISPLAY_MAZE_PELLET_COUNT));
    assert(vibe_display_maze_is_power_pellet(56, VIBE_DISPLAY_MAZE_PELLET_COUNT));
    assert(vibe_display_maze_is_power_pellet(77, VIBE_DISPLAY_MAZE_PELLET_COUNT));
    assert(!vibe_display_maze_is_power_pellet(1, VIBE_DISPLAY_MAZE_PELLET_COUNT));

    vibe_display_maze_pellet_position(0, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);
    assert(dot.x == maze_x + 78 && dot.y == maze_y + 62);
    vibe_display_maze_pellet_position(21, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);
    assert(dot.x == maze_x + 252 && dot.y == maze_y + 62);
    vibe_display_maze_pellet_position(56, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);
    assert(dot.x == maze_x + 78 && dot.y == maze_y + 238);
    vibe_display_maze_pellet_position(77, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);
    assert(dot.x == maze_x + 252 && dot.y == maze_y + 238);
}

static void test_display_model_spaces_pellets_evenly_by_lane(void)
{
    vibe_display_animation_frame_t previous;
    vibe_display_animation_frame_t current;

    vibe_display_maze_pellet_position(0, VIBE_DISPLAY_MAZE_PELLET_COUNT, &previous);
    for (int i = 1; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &current);
        int distance = abs(current.x - previous.x) + abs(current.y - previous.y);

        if (current.y == previous.y || current.x == previous.x) {
            assert(distance == 0 || distance >= 6);
            assert(distance <= 140);
        } else {
            assert(distance >= 30);
        }
        previous = current;
    }
}

static void test_display_model_keeps_outer_pellet_rows_between_walls(void)
{
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;

    for (int i = 0; i < 22; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        assert(dot.y == maze_y + 62);
        assert(dot.y != maze_y + 70);
        assert(dot.y != maze_y + 100);
    }

    for (int i = 56; i < 78; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        assert(dot.y == maze_y + 238);
        assert(dot.y != maze_y + 230);
    }
}

static void test_display_model_leaves_bottom_gate_clear_of_pellets(void)
{
    const int maze_x = VIBE_DISPLAY_MAZE_STAGE_X;
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        bool near_bottom_center_gate = dot.x >= maze_x + 146 && dot.x <= maze_x + 174 &&
                                       dot.y >= maze_y + 78 && dot.y <= maze_y + 92;
        assert(!near_bottom_center_gate);
    }
}

static void test_display_model_keeps_pellets_outside_reference_wall_cores(void)
{
    const int maze_x = VIBE_DISPLAY_MAZE_STAGE_X;
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        bool inside_left_box = dot.x >= maze_x + 86 && dot.x <= maze_x + 110 &&
                               dot.y >= maze_y + 72 && dot.y <= maze_y + 98;
        bool inside_center_house = dot.x >= maze_x + 140 && dot.x <= maze_x + 192 &&
                                   dot.y >= maze_y + 172 && dot.y <= maze_y + 194;
        bool inside_right_box = dot.x >= maze_x + 222 && dot.x <= maze_x + 248 &&
                                dot.y >= maze_y + 72 && dot.y <= maze_y + 98;

        assert(!inside_left_box);
        assert(!inside_center_house);
        assert(!inside_right_box);
    }
}

static void test_display_model_places_pellets_on_reference_side_corridors(void)
{
    const int maze_x = VIBE_DISPLAY_MAZE_STAGE_X;
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;
    int upper_left_count = 0;
    int upper_right_count = 0;
    int middle_left_count = 0;
    int middle_right_count = 0;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        if (dot.x >= maze_x + 78 && dot.x <= maze_x + 144 && dot.y == maze_y + 104) {
            upper_left_count++;
        }
        if (dot.x >= maze_x + 176 && dot.x <= maze_x + 252 && dot.y == maze_y + 104) {
            upper_right_count++;
        }
        if (dot.x >= maze_x + 78 && dot.x <= maze_x + 132 && dot.y == maze_y + 150) {
            middle_left_count++;
        }
        if (dot.x >= maze_x + 188 && dot.x <= maze_x + 252 && dot.y == maze_y + 150) {
            middle_right_count++;
        }
    }

    assert(upper_left_count == 10);
    assert(upper_right_count == 10);
    assert(middle_left_count == 7);
    assert(middle_right_count == 7);
}

static void test_display_model_places_pellets_on_reference_vertical_corridors(void)
{
    const int maze_x = VIBE_DISPLAY_MAZE_STAGE_X;
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;
    int outer_left_column_count = 0;
    int inner_left_column_count = 0;
    int inner_right_column_count = 0;
    int outer_right_column_count = 0;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        if (dot.x == maze_x + 82 && dot.y >= maze_y + 68 && dot.y <= maze_y + 230) {
            outer_left_column_count++;
        }
        if (dot.x == maze_x + 132 && dot.y >= maze_y + 68 && dot.y <= maze_y + 230) {
            inner_left_column_count++;
        }
        if (dot.x == maze_x + 188 && dot.y >= maze_y + 68 && dot.y <= maze_y + 230) {
            inner_right_column_count++;
        }
        if (dot.x == maze_x + 238 && dot.y >= maze_y + 68 && dot.y <= maze_y + 230) {
            outer_right_column_count++;
        }
    }

    assert(outer_left_column_count >= 6);
    assert(inner_left_column_count >= 6);
    assert(inner_right_column_count >= 6);
    assert(outer_right_column_count >= 6);
}

static void test_display_model_keeps_left_corridor_pellets_before_g_wall(void)
{
    const int maze_x = VIBE_DISPLAY_MAZE_STAGE_X;
    const int maze_y = VIBE_DISPLAY_MAZE_STAGE_Y;
    int lower_left_count = 0;
    int lower_right_count = 0;

    for (int i = 0; i < VIBE_DISPLAY_MAZE_PELLET_COUNT; i++) {
        vibe_display_animation_frame_t dot;
        vibe_display_maze_pellet_position(i, VIBE_DISPLAY_MAZE_PELLET_COUNT, &dot);

        if (dot.y == maze_y + 238 && dot.x >= maze_x + 78 && dot.x <= maze_x + 144) {
            lower_left_count++;
        }
        if (dot.y == maze_y + 238 && dot.x >= maze_x + 176 && dot.x <= maze_x + 252) {
            lower_right_count++;
        }

        bool inside_mini_logo_space = dot.x >= maze_x + 146 && dot.x <= maze_x + 174 &&
                                      dot.y >= maze_y + 232 && dot.y <= maze_y + 244;
        assert(!inside_mini_logo_space);
    }

    assert(lower_left_count == 11);
    assert(lower_right_count == 11);
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

static void test_display_model_animation_speed_scales_with_active_tasks(void)
{
    assert(vibe_display_animation_step(0) == 1);
    assert(vibe_display_animation_step(1) == 1);
    assert(vibe_display_animation_step(2) == 2);
    assert(vibe_display_animation_step(5) == 3);
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
    const int last_row_y = VIBE_DISPLAY_TASK_ROW_Y + (VIBE_STATUS_MAX_TASKS - 1) * VIBE_DISPLAY_TASK_ROW_STRIDE;
    const int row_bottom = last_row_y + VIBE_DISPLAY_TASK_ROW_TEXT_H;
    const int swatch_bottom = last_row_y + VIBE_DISPLAY_TASK_SWATCH_H;

    assert(VIBE_DISPLAY_TASK_PANEL_Y + VIBE_DISPLAY_TASK_PANEL_H == screen_h);
    assert(VIBE_DISPLAY_TASK_ROW_Y > VIBE_DISPLAY_TASK_PANEL_Y);
    assert(row_bottom <= screen_h);
    assert(swatch_bottom <= screen_h);
    assert(VIBE_DISPLAY_TASK_SWATCH_W <= 3);
    assert(VIBE_DISPLAY_TASK_SWATCH_H <= VIBE_DISPLAY_TASK_ROW_STRIDE);
}

int main(void)
{
    test_v1_status_packet();
    test_v2_task_list_packet();
    test_unknown_states_fall_back_to_idle();
    test_invalid_packets_are_rejected_without_mutation();
    test_display_model_detects_duplicate_packets();
    test_display_model_formats_task_rows();
    test_display_model_formats_compact_count_summary();
    test_display_model_animates_busy_center_stage();
    test_display_model_animates_through_maze_turns();
    test_display_model_places_pellets_on_maze_centerline();
    test_display_model_marks_reference_style_power_pellets();
    test_display_model_spaces_pellets_evenly_by_lane();
    test_display_model_keeps_outer_pellet_rows_between_walls();
    test_display_model_leaves_bottom_gate_clear_of_pellets();
    test_display_model_keeps_pellets_outside_reference_wall_cores();
    test_display_model_places_pellets_on_reference_side_corridors();
    test_display_model_places_pellets_on_reference_vertical_corridors();
    test_display_model_keeps_left_corridor_pellets_before_g_wall();
    test_display_model_keeps_maze_path_inside_flush_border();
    test_display_model_creates_actor_per_task();
    test_display_model_animation_speed_scales_with_active_tasks();
    test_display_model_actor_shape_faces_travel_direction();
    test_display_model_uses_reference_pacman_actor_style();
    test_display_model_hides_timestamp_footer();
    test_display_model_keeps_task_panel_tight_to_screen_bottom();

    puts("vibe_status_parser_test: ok");
    return 0;
}
