#include "vibe_status.h"

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

int main(void)
{
    test_v1_status_packet();
    test_v2_task_list_packet();
    test_unknown_states_fall_back_to_idle();
    test_invalid_packets_are_rejected_without_mutation();

    puts("vibe_status_parser_test: ok");
    return 0;
}
