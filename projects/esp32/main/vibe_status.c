#include "vibe_status.h"

#include <stdlib.h>
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

static int json_int(cJSON *root, const char *key)
{
    cJSON *value = cJSON_GetObjectItemCaseSensitive(root, key);
    return cJSON_IsNumber(value) ? value->valueint : 0;
}

static int64_t json_int64(cJSON *root, const char *key)
{
    cJSON *value = cJSON_GetObjectItemCaseSensitive(root, key);
    return cJSON_IsNumber(value) ? (int64_t)value->valuedouble : 0;
}

static int json_percent(cJSON *root, const char *key)
{
    cJSON *value = cJSON_GetObjectItemCaseSensitive(root, key);
    if (!cJSON_IsNumber(value)) {
        return -1;
    }

    if (value->valueint < 0) {
        return 0;
    }
    if (value->valueint > 100) {
        return 100;
    }
    return value->valueint;
}

static int json_non_negative_int(cJSON *root, const char *key)
{
    cJSON *value = cJSON_GetObjectItemCaseSensitive(root, key);
    if (!cJSON_IsNumber(value)) {
        return -1;
    }

    return value->valueint < 0 ? 0 : value->valueint;
}

static void parse_task(cJSON *item, vibe_status_task_t *task)
{
    if (item == NULL || task == NULL) {
        return;
    }

    copy_json_string(item, "title", task->title, sizeof(task->title));
    copy_json_string(item, "source", task->source, sizeof(task->source));
    copy_json_string(item, "detail", task->detail, sizeof(task->detail));
    task->updated_at_ms = json_int64(item, "updatedAt");
    task->context_used_percent = json_percent(item, "contextUsedPercent");
    if (task->context_used_percent < 0) {
        int context_remaining_percent = json_percent(item, "contextRemainingPercent");
        task->context_used_percent = context_remaining_percent < 0 ? -1 : 100 - context_remaining_percent;
    }

    cJSON *state = cJSON_GetObjectItemCaseSensitive(item, "state");
    task->context_used_tokens = json_non_negative_int(item, "contextUsedTokens");
    task->context_window_tokens = json_non_negative_int(item, "contextWindowTokens");
    if (cJSON_IsString(state) && state->valuestring != NULL) {
        bool known = false;
        task->state = vibe_display_state_from_string(state->valuestring, &known);
        copy_text(task->state_text, sizeof(task->state_text), known ? state->valuestring : "idle");
    }
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
    packet->active_count = 0;
    packet->waiting_count = 0;
    packet->error_count = 0;
    packet->codex_5h_remaining_percent = -1;
    packet->codex_7d_remaining_percent = -1;
    packet->task_count = 0;

    for (int i = 0; i < VIBE_STATUS_MAX_TASKS; i++) {
        copy_text(packet->tasks[i].title, sizeof(packet->tasks[i].title), "");
        copy_text(packet->tasks[i].source, sizeof(packet->tasks[i].source), "");
        packet->tasks[i].state = VIBE_DISPLAY_IDLE;
        copy_text(packet->tasks[i].state_text, sizeof(packet->tasks[i].state_text), "idle");
        copy_text(packet->tasks[i].detail, sizeof(packet->tasks[i].detail), "");
        packet->tasks[i].context_used_percent = -1;
        packet->tasks[i].context_used_tokens = -1;
        packet->tasks[i].context_window_tokens = -1;
        packet->tasks[i].updated_at_ms = 0;
    }
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

    vibe_status_packet_t *parsed = calloc(1, sizeof(vibe_status_packet_t));
    if (parsed == NULL) {
        cJSON_Delete(root);
        return false;
    }
    vibe_status_default(parsed);

    cJSON *version = cJSON_GetObjectItemCaseSensitive(root, "v");
    if (cJSON_IsNumber(version)) {
        parsed->version = version->valueint;
    }

    copy_json_string(root, "source", parsed->source, sizeof(parsed->source));
    copy_json_string(root, "detail", parsed->detail, sizeof(parsed->detail));
    parsed->active_count = json_int(root, "activeCount");
    parsed->waiting_count = json_int(root, "waitingCount");
    parsed->error_count = json_int(root, "errorCount");

    cJSON *usage = cJSON_GetObjectItemCaseSensitive(root, "usage");
    if (cJSON_IsObject(usage)) {
        parsed->codex_5h_remaining_percent = json_percent(usage, "codex5hRemainingPercent");
        parsed->codex_7d_remaining_percent = json_percent(usage, "codex7dRemainingPercent");
        parsed->codex_5h_reset_at_ms = json_int64(usage, "codex5hResetAt");
        parsed->codex_7d_reset_at_ms = json_int64(usage, "codex7dResetAt");
    }

    cJSON *timestamp = cJSON_GetObjectItemCaseSensitive(root, "ts");
    if (cJSON_IsNumber(timestamp)) {
        parsed->timestamp_ms = (int64_t)timestamp->valuedouble;
    }

    cJSON *state = cJSON_GetObjectItemCaseSensitive(root, "state");
    if (!cJSON_IsString(state) || state->valuestring == NULL) {
        free(parsed);
        cJSON_Delete(root);
        return false;
    }

    bool known = false;
    parsed->state = vibe_display_state_from_string(state->valuestring, &known);
    copy_text(parsed->state_text, sizeof(parsed->state_text), state->valuestring);
    if (!known) {
        parsed->state = VIBE_DISPLAY_IDLE;
        copy_text(parsed->state_text, sizeof(parsed->state_text), "idle");
    }

    cJSON *tasks = cJSON_GetObjectItemCaseSensitive(root, "tasks");
    if (cJSON_IsArray(tasks)) {
        cJSON *item = NULL;
        cJSON_ArrayForEach(item, tasks) {
            if (parsed->task_count >= VIBE_STATUS_MAX_TASKS) {
                break;
            }
            if (!cJSON_IsObject(item)) {
                continue;
            }

            parse_task(item, &parsed->tasks[parsed->task_count]);
            parsed->task_count++;
        }
    }

    *packet = *parsed;
    free(parsed);
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
