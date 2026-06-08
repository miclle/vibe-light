#include "vibe_status.h"
#include "vibe_display_model.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
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

static void test_display_model_animates_busy_edge_path(void)
{
    vibe_display_animation_frame_t frame0;
    vibe_display_animation_frame_t frame1;
    vibe_display_animation_frame_t wrapped;

    assert(vibe_display_animation_enabled(VIBE_DISPLAY_BUSY));
    assert(!vibe_display_animation_enabled(VIBE_DISPLAY_WAITING));
    assert(!vibe_display_animation_enabled(VIBE_DISPLAY_IDLE));

    vibe_display_animation_frame(0, 1, &frame0);
    vibe_display_animation_frame(1, 1, &frame1);
    vibe_display_animation_frame(VIBE_DISPLAY_ANIMATION_PATH_STEPS, 1, &wrapped);

    assert(frame0.x == wrapped.x);
    assert(frame0.y == wrapped.y);
    assert(frame0.mouth_open);
    assert(!frame1.mouth_open);
    assert(frame0.x != frame1.x || frame0.y != frame1.y);
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

static void test_display_model_hides_timestamp_footer(void)
{
    vibe_status_packet_t packet;
    char footer[32];

    vibe_status_default(&packet);
    packet.timestamp_ms = 1780874713000LL;
    vibe_display_footer_text(&packet, footer, sizeof(footer));

    assert(strcmp(footer, "") == 0);
}

int main(void)
{
    test_v1_status_packet();
    test_v2_task_list_packet();
    test_unknown_states_fall_back_to_idle();
    test_invalid_packets_are_rejected_without_mutation();
    test_display_model_detects_duplicate_packets();
    test_display_model_formats_task_rows();
    test_display_model_animates_busy_edge_path();
    test_display_model_animation_speed_scales_with_active_tasks();
    test_display_model_actor_shape_faces_travel_direction();
    test_display_model_hides_timestamp_footer();

    puts("vibe_status_parser_test: ok");
    return 0;
}
