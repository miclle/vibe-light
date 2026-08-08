#include "vibe_ota_protocol.h"

#include <ctype.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "cJSON.h"

static bool parse_u32(const cJSON *object, const char *name, bool allow_zero, uint32_t *value);
static bool copy_string_field(const cJSON *object, const char *name, char *destination, size_t destination_size);
static bool copy_sha256_field(const cJSON *object, const char *name, char *destination);
static uint32_t decode_little_endian_u32(const uint8_t *bytes);
static int append_json_string(char *destination, size_t destination_size, const char *value);

vibe_ota_protocol_result_t vibe_ota_parse_begin(const char *json,
                                                size_t json_len,
                                                vibe_ota_begin_request_t *request)
{
    if (json == NULL || request == NULL) {
        return VIBE_OTA_PROTOCOL_INVALID_ARGUMENT;
    }
    if (json_len == 0 || json_len > VIBE_OTA_CONTROL_JSON_MAX) {
        return VIBE_OTA_PROTOCOL_INVALID_LENGTH;
    }

    cJSON *root = cJSON_ParseWithLength(json, json_len);
    if (root == NULL || !cJSON_IsObject(root)) {
        cJSON_Delete(root);
        return VIBE_OTA_PROTOCOL_INVALID_JSON;
    }

    vibe_ota_begin_request_t parsed = {0};
    cJSON *version = cJSON_GetObjectItemCaseSensitive(root, "v");
    if (!cJSON_IsNumber(version) || version->valuedouble != VIBE_OTA_PROTOCOL_VERSION) {
        cJSON_Delete(root);
        return VIBE_OTA_PROTOCOL_UNSUPPORTED_VERSION;
    }
    parsed.protocol_version = VIBE_OTA_PROTOCOL_VERSION;

    cJSON *operation = cJSON_GetObjectItemCaseSensitive(root, "op");
    if (!cJSON_IsString(operation) || strcmp(operation->valuestring, "begin") != 0) {
        cJSON_Delete(root);
        return VIBE_OTA_PROTOCOL_INVALID_OPERATION;
    }

    if (!parse_u32(root, "sessionId", false, &parsed.session_id) ||
        !parse_u32(root, "imageSize", false, &parsed.image_size)) {
        cJSON_Delete(root);
        return VIBE_OTA_PROTOCOL_INVALID_SIZE;
    }
    if (!copy_string_field(root, "projectName", parsed.project_name, sizeof(parsed.project_name)) ||
        !copy_string_field(root, "appVersion", parsed.app_version, sizeof(parsed.app_version)) ||
        !copy_sha256_field(root, "sha256", parsed.sha256_hex)) {
        cJSON_Delete(root);
        return VIBE_OTA_PROTOCOL_INVALID_FIELD;
    }

    cJSON_Delete(root);
    *request = parsed;
    return VIBE_OTA_PROTOCOL_OK;
}

vibe_ota_protocol_result_t vibe_ota_parse_command(const char *json,
                                                  size_t json_len,
                                                  vibe_ota_command_t *command)
{
    if (json == NULL || command == NULL) {
        return VIBE_OTA_PROTOCOL_INVALID_ARGUMENT;
    }
    if (json_len == 0 || json_len > VIBE_OTA_CONTROL_JSON_MAX) {
        return VIBE_OTA_PROTOCOL_INVALID_LENGTH;
    }

    cJSON *root = cJSON_ParseWithLength(json, json_len);
    if (root == NULL || !cJSON_IsObject(root)) {
        cJSON_Delete(root);
        return VIBE_OTA_PROTOCOL_INVALID_JSON;
    }

    cJSON *version = cJSON_GetObjectItemCaseSensitive(root, "v");
    if (!cJSON_IsNumber(version) || version->valuedouble != VIBE_OTA_PROTOCOL_VERSION) {
        cJSON_Delete(root);
        return VIBE_OTA_PROTOCOL_UNSUPPORTED_VERSION;
    }

    vibe_ota_command_t parsed = {0};
    cJSON *operation = cJSON_GetObjectItemCaseSensitive(root, "op");
    if (!cJSON_IsString(operation)) {
        cJSON_Delete(root);
        return VIBE_OTA_PROTOCOL_INVALID_OPERATION;
    }
    if (strcmp(operation->valuestring, "finish") == 0) {
        parsed.operation = VIBE_OTA_OPERATION_FINISH;
    } else if (strcmp(operation->valuestring, "abort") == 0) {
        parsed.operation = VIBE_OTA_OPERATION_ABORT;
    } else {
        cJSON_Delete(root);
        return VIBE_OTA_PROTOCOL_INVALID_OPERATION;
    }
    if (!parse_u32(root, "sessionId", false, &parsed.session_id)) {
        cJSON_Delete(root);
        return VIBE_OTA_PROTOCOL_INVALID_FIELD;
    }

    cJSON_Delete(root);
    *command = parsed;
    return VIBE_OTA_PROTOCOL_OK;
}

vibe_ota_protocol_result_t vibe_ota_parse_data_frame(const uint8_t *data,
                                                     size_t data_len,
                                                     vibe_ota_data_frame_t *frame)
{
    if (data == NULL || frame == NULL) {
        return VIBE_OTA_PROTOCOL_INVALID_ARGUMENT;
    }
    if (data_len <= VIBE_OTA_DATA_HEADER_SIZE || data_len > VIBE_OTA_DATA_FRAME_MAX) {
        return VIBE_OTA_PROTOCOL_INVALID_LENGTH;
    }

    vibe_ota_data_frame_t parsed = {
        .session_id = decode_little_endian_u32(data),
        .offset = decode_little_endian_u32(data + 4),
        .payload = data + VIBE_OTA_DATA_HEADER_SIZE,
        .payload_len = data_len - VIBE_OTA_DATA_HEADER_SIZE,
    };
    *frame = parsed;
    return VIBE_OTA_PROTOCOL_OK;
}

int vibe_ota_format_status_json(char *json,
                                size_t json_size,
                                const vibe_ota_status_snapshot_t *snapshot)
{
    if (json == NULL || json_size == 0 || snapshot == NULL) {
        return -1;
    }

    int written = snprintf(json,
                           json_size,
                           "{\"v\":1,\"state\":\"%s\",\"sessionId\":%" PRIu32
                           ",\"committedOffset\":%" PRIu32 ",\"imageSize\":%" PRIu32
                           ",\"credits\":%u",
                           vibe_ota_state_to_string(snapshot->state),
                           snapshot->session_id,
                           snapshot->committed_offset,
                           snapshot->image_size,
                           snapshot->credits);
    if (written < 0 || (size_t)written >= json_size) {
        return -1;
    }

    if (snapshot->state == VIBE_OTA_STATE_ERROR &&
        snapshot->error_code != NULL && snapshot->error_code[0] != '\0') {
        int tail = snprintf(json + written, json_size - (size_t)written, ",\"errorCode\":\"");
        if (tail < 0 || (size_t)tail >= json_size - (size_t)written) {
            return -1;
        }
        written += tail;

        int escaped = append_json_string(json + written, json_size - (size_t)written, snapshot->error_code);
        if (escaped < 0) {
            return -1;
        }
        written += escaped;

        tail = snprintf(json + written, json_size - (size_t)written, "\",\"message\":\"");
        if (tail < 0 || (size_t)tail >= json_size - (size_t)written) {
            return -1;
        }
        written += tail;

        escaped = append_json_string(json + written,
                                     json_size - (size_t)written,
                                     snapshot->message == NULL ? "" : snapshot->message);
        if (escaped < 0) {
            return -1;
        }
        written += escaped;

        tail = snprintf(json + written, json_size - (size_t)written, "\"");
        if (tail < 0 || (size_t)tail >= json_size - (size_t)written) {
            return -1;
        }
        written += tail;
    }

    int tail = snprintf(json + written, json_size - (size_t)written, "}");
    if (tail < 0 || (size_t)tail >= json_size - (size_t)written) {
        return -1;
    }
    written += tail;
    return written;
}

const char *vibe_ota_state_to_string(vibe_ota_state_t state)
{
    switch (state) {
    case VIBE_OTA_STATE_IDLE:
        return "idle";
    case VIBE_OTA_STATE_READY:
        return "ready";
    case VIBE_OTA_STATE_RECEIVING:
        return "receiving";
    case VIBE_OTA_STATE_VERIFYING:
        return "verifying";
    case VIBE_OTA_STATE_REBOOTING:
        return "rebooting";
    case VIBE_OTA_STATE_COMPLETE:
        return "complete";
    case VIBE_OTA_STATE_ERROR:
        return "error";
    default:
        return "error";
    }
}

vibe_ota_protocol_result_t vibe_ota_session_begin(vibe_ota_session_t *session,
                                                  const vibe_ota_begin_request_t *request,
                                                  uint32_t partition_size)
{
    if (session == NULL || request == NULL) {
        return VIBE_OTA_PROTOCOL_INVALID_ARGUMENT;
    }
    if (request->protocol_version != VIBE_OTA_PROTOCOL_VERSION ||
        request->session_id == 0 ||
        request->image_size == 0 ||
        request->image_size > partition_size ||
        request->project_name[0] == '\0' ||
        request->app_version[0] == '\0' ||
        request->sha256_hex[0] == '\0') {
        return VIBE_OTA_PROTOCOL_INVALID_SIZE;
    }

    vibe_ota_session_t started = {
        .state = VIBE_OTA_STATE_READY,
        .request = *request,
        .partition_size = partition_size,
    };
    *session = started;
    return VIBE_OTA_PROTOCOL_OK;
}

vibe_ota_protocol_result_t vibe_ota_session_accept(vibe_ota_session_t *session,
                                                   uint32_t session_id,
                                                   uint32_t offset,
                                                   size_t payload_len)
{
    if (session == NULL || payload_len == 0 || payload_len > UINT32_MAX) {
        return VIBE_OTA_PROTOCOL_INVALID_ARGUMENT;
    }
    if (session->state != VIBE_OTA_STATE_READY && session->state != VIBE_OTA_STATE_RECEIVING) {
        return VIBE_OTA_PROTOCOL_INVALID_STATE;
    }
    if (session_id != session->request.session_id) {
        return VIBE_OTA_PROTOCOL_SESSION_MISMATCH;
    }
    if (offset != session->accepted_offset) {
        return VIBE_OTA_PROTOCOL_UNEXPECTED_OFFSET;
    }
    if (payload_len > session->request.image_size - session->accepted_offset) {
        return VIBE_OTA_PROTOCOL_INVALID_SIZE;
    }

    session->accepted_offset += (uint32_t)payload_len;
    session->state = VIBE_OTA_STATE_RECEIVING;
    return VIBE_OTA_PROTOCOL_OK;
}

vibe_ota_protocol_result_t vibe_ota_session_commit(vibe_ota_session_t *session,
                                                   uint32_t offset,
                                                   size_t payload_len)
{
    if (session == NULL || payload_len == 0 || payload_len > UINT32_MAX) {
        return VIBE_OTA_PROTOCOL_INVALID_ARGUMENT;
    }
    if (session->state != VIBE_OTA_STATE_RECEIVING) {
        return VIBE_OTA_PROTOCOL_INVALID_STATE;
    }
    if (offset != session->committed_offset) {
        return VIBE_OTA_PROTOCOL_UNEXPECTED_OFFSET;
    }
    if (payload_len > session->accepted_offset - session->committed_offset) {
        return VIBE_OTA_PROTOCOL_INVALID_SIZE;
    }

    session->committed_offset += (uint32_t)payload_len;
    return VIBE_OTA_PROTOCOL_OK;
}

uint32_t vibe_ota_session_accepted_offset(const vibe_ota_session_t *session)
{
    return session == NULL ? 0 : session->accepted_offset;
}

uint32_t vibe_ota_session_resume_offset(const vibe_ota_session_t *session)
{
    return session == NULL ? 0 : session->committed_offset;
}

bool vibe_ota_session_can_finish(const vibe_ota_session_t *session)
{
    return session != NULL &&
           session->state == VIBE_OTA_STATE_RECEIVING &&
           session->accepted_offset == session->request.image_size &&
           session->committed_offset == session->request.image_size;
}

void vibe_ota_session_abort(vibe_ota_session_t *session)
{
    if (session == NULL) {
        return;
    }
    memset(session, 0, sizeof(*session));
    session->state = VIBE_OTA_STATE_IDLE;
}

static bool parse_u32(const cJSON *object, const char *name, bool allow_zero, uint32_t *value)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(object, name);
    if (!cJSON_IsNumber(item) || item->valuedouble < 0 || item->valuedouble > UINT32_MAX) {
        return false;
    }

    uint32_t parsed = (uint32_t)item->valuedouble;
    if ((double)parsed != item->valuedouble || (!allow_zero && parsed == 0)) {
        return false;
    }
    *value = parsed;
    return true;
}

static bool copy_string_field(const cJSON *object, const char *name, char *destination, size_t destination_size)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(object, name);
    if (!cJSON_IsString(item) || item->valuestring[0] == '\0') {
        return false;
    }

    size_t length = strlen(item->valuestring);
    if (length >= destination_size) {
        return false;
    }
    memcpy(destination, item->valuestring, length + 1);
    return true;
}

static bool copy_sha256_field(const cJSON *object, const char *name, char *destination)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(object, name);
    if (!cJSON_IsString(item) || strlen(item->valuestring) != VIBE_OTA_SHA256_HEX_LENGTH) {
        return false;
    }

    for (size_t index = 0; index < VIBE_OTA_SHA256_HEX_LENGTH; index++) {
        unsigned char character = (unsigned char)item->valuestring[index];
        if (!isxdigit(character)) {
            return false;
        }
        destination[index] = (char)tolower(character);
    }
    destination[VIBE_OTA_SHA256_HEX_LENGTH] = '\0';
    return true;
}

static uint32_t decode_little_endian_u32(const uint8_t *bytes)
{
    return (uint32_t)bytes[0] |
           ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) |
           ((uint32_t)bytes[3] << 24);
}

static int append_json_string(char *destination, size_t destination_size, const char *value)
{
    if (destination == NULL || destination_size == 0) {
        return -1;
    }

    size_t used = 0;
    for (const unsigned char *cursor = (const unsigned char *)value; *cursor != '\0'; cursor++) {
        const char *chunk = NULL;
        char escaped[7];
        size_t chunk_length = 0;

        switch (*cursor) {
        case '\\':
            chunk = "\\\\";
            chunk_length = 2;
            break;
        case '"':
            chunk = "\\\"";
            chunk_length = 2;
            break;
        case '\n':
            chunk = "\\n";
            chunk_length = 2;
            break;
        case '\r':
            chunk = "\\r";
            chunk_length = 2;
            break;
        case '\t':
            chunk = "\\t";
            chunk_length = 2;
            break;
        default:
            if (*cursor < 0x20) {
                snprintf(escaped, sizeof(escaped), "\\u%04x", *cursor);
                chunk = escaped;
                chunk_length = 6;
            } else {
                escaped[0] = (char)*cursor;
                escaped[1] = '\0';
                chunk = escaped;
                chunk_length = 1;
            }
            break;
        }

        if (used + chunk_length >= destination_size) {
            return -1;
        }
        memcpy(destination + used, chunk, chunk_length);
        used += chunk_length;
    }
    destination[used] = '\0';
    return (int)used;
}
