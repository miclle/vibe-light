#include "vibe_status.h"

#include <string.h>
#include <stdio.h>

#include "cJSON.h"

static void copy_text(char *target, size_t target_size, const char *source)
{
    if (target == NULL || target_size == 0 || source == NULL) {
        return;
    }

    snprintf(target, target_size, "%s", source);
}

static void copy_json_string(cJSON *root, const char *key, char *target, size_t target_size)
{
    cJSON *value = cJSON_GetObjectItemCaseSensitive(root, key);
    if (!cJSON_IsString(value) || value->valuestring == NULL || target_size == 0) {
        return;
    }

    copy_text(target, target_size, value->valuestring);
}

void vibe_status_default(vibe_status_packet_t *packet)
{
    if (packet == NULL) {
        return;
    }

    packet->version = 1;
    copy_text(packet->source, sizeof(packet->source), "manual");
    packet->state = VIBE_DISPLAY_OFFLINE;
    copy_text(packet->state_text, sizeof(packet->state_text), "offline");
    copy_text(packet->detail, sizeof(packet->detail), "waiting for desktop app");
    packet->timestamp_ms = 0;
}

bool vibe_status_parse_json(const uint8_t *data, size_t length, vibe_status_packet_t *packet)
{
    if (data == NULL || length == 0 || packet == NULL) {
        return false;
    }

    cJSON *root = cJSON_ParseWithLength((const char *)data, length);
    if (root == NULL) {
        return false;
    }

    vibe_status_packet_t parsed;
    vibe_status_default(&parsed);

    cJSON *version = cJSON_GetObjectItemCaseSensitive(root, "v");
    if (cJSON_IsNumber(version)) {
        parsed.version = version->valueint;
    }

    copy_json_string(root, "source", parsed.source, sizeof(parsed.source));
    copy_json_string(root, "detail", parsed.detail, sizeof(parsed.detail));

    cJSON *timestamp = cJSON_GetObjectItemCaseSensitive(root, "ts");
    if (cJSON_IsNumber(timestamp)) {
        parsed.timestamp_ms = (int64_t)timestamp->valuedouble;
    }

    cJSON *state = cJSON_GetObjectItemCaseSensitive(root, "state");
    if (!cJSON_IsString(state) || state->valuestring == NULL) {
        cJSON_Delete(root);
        return false;
    }

    bool known = false;
    parsed.state = vibe_display_state_from_string(state->valuestring, &known);
    copy_text(parsed.state_text, sizeof(parsed.state_text), state->valuestring);
    if (!known) {
        parsed.state = VIBE_DISPLAY_IDLE;
        copy_text(parsed.state_text, sizeof(parsed.state_text), "idle");
    }

    *packet = parsed;
    cJSON_Delete(root);
    return true;
}

const char *vibe_display_state_to_string(vibe_display_state_t state)
{
    switch (state) {
    case VIBE_DISPLAY_IDLE:
        return "idle";
    case VIBE_DISPLAY_BUSY:
        return "busy";
    case VIBE_DISPLAY_WAITING:
        return "waiting";
    case VIBE_DISPLAY_SUCCESS:
        return "success";
    case VIBE_DISPLAY_ERROR:
        return "error";
    case VIBE_DISPLAY_OFFLINE:
        return "offline";
    default:
        return "idle";
    }
}

const char *vibe_display_state_to_title(vibe_display_state_t state)
{
    switch (state) {
    case VIBE_DISPLAY_IDLE:
        return "Idle";
    case VIBE_DISPLAY_BUSY:
        return "Busy";
    case VIBE_DISPLAY_WAITING:
        return "Waiting";
    case VIBE_DISPLAY_SUCCESS:
        return "Success";
    case VIBE_DISPLAY_ERROR:
        return "Error";
    case VIBE_DISPLAY_OFFLINE:
        return "Offline";
    default:
        return "Idle";
    }
}

vibe_display_state_t vibe_display_state_from_string(const char *value, bool *known)
{
    if (known != NULL) {
        *known = true;
    }

    if (value == NULL) {
        if (known != NULL) {
            *known = false;
        }
        return VIBE_DISPLAY_IDLE;
    }

    if (strcmp(value, "idle") == 0) {
        return VIBE_DISPLAY_IDLE;
    }
    if (strcmp(value, "busy") == 0) {
        return VIBE_DISPLAY_BUSY;
    }
    if (strcmp(value, "waiting") == 0) {
        return VIBE_DISPLAY_WAITING;
    }
    if (strcmp(value, "success") == 0) {
        return VIBE_DISPLAY_SUCCESS;
    }
    if (strcmp(value, "error") == 0) {
        return VIBE_DISPLAY_ERROR;
    }
    if (strcmp(value, "offline") == 0) {
        return VIBE_DISPLAY_OFFLINE;
    }

    if (known != NULL) {
        *known = false;
    }
    return VIBE_DISPLAY_IDLE;
}
