#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_OTA_PROTOCOL_VERSION 1
#define VIBE_OTA_CONTROL_JSON_MAX 512
#define VIBE_OTA_SHA256_HEX_LENGTH 64
#define VIBE_OTA_PROJECT_NAME_MAX 32
#define VIBE_OTA_VERSION_MAX 32
#define VIBE_OTA_DATA_HEADER_SIZE 8
#define VIBE_OTA_DATA_FRAME_MAX 512
#define VIBE_OTA_DATA_PAYLOAD_MAX (VIBE_OTA_DATA_FRAME_MAX - VIBE_OTA_DATA_HEADER_SIZE)

typedef enum {
    VIBE_OTA_PROTOCOL_OK = 0,
    VIBE_OTA_PROTOCOL_INVALID_ARGUMENT,
    VIBE_OTA_PROTOCOL_INVALID_LENGTH,
    VIBE_OTA_PROTOCOL_INVALID_JSON,
    VIBE_OTA_PROTOCOL_UNSUPPORTED_VERSION,
    VIBE_OTA_PROTOCOL_INVALID_OPERATION,
    VIBE_OTA_PROTOCOL_INVALID_FIELD,
    VIBE_OTA_PROTOCOL_INVALID_SIZE,
    VIBE_OTA_PROTOCOL_SESSION_MISMATCH,
    VIBE_OTA_PROTOCOL_UNEXPECTED_OFFSET,
    VIBE_OTA_PROTOCOL_INVALID_STATE,
} vibe_ota_protocol_result_t;

typedef enum {
    VIBE_OTA_OPERATION_FINISH,
    VIBE_OTA_OPERATION_ABORT,
} vibe_ota_operation_t;

typedef struct {
    int protocol_version;
    uint32_t session_id;
    uint32_t image_size;
    char project_name[VIBE_OTA_PROJECT_NAME_MAX + 1];
    char app_version[VIBE_OTA_VERSION_MAX + 1];
    char sha256_hex[VIBE_OTA_SHA256_HEX_LENGTH + 1];
} vibe_ota_begin_request_t;

typedef struct {
    vibe_ota_operation_t operation;
    uint32_t session_id;
} vibe_ota_command_t;

typedef struct {
    uint32_t session_id;
    uint32_t offset;
    const uint8_t *payload;
    size_t payload_len;
} vibe_ota_data_frame_t;

typedef enum {
    VIBE_OTA_STATE_IDLE,
    VIBE_OTA_STATE_READY,
    VIBE_OTA_STATE_RECEIVING,
    VIBE_OTA_STATE_VERIFYING,
    VIBE_OTA_STATE_REBOOTING,
    VIBE_OTA_STATE_COMPLETE,
    VIBE_OTA_STATE_ERROR,
} vibe_ota_state_t;

typedef struct {
    vibe_ota_state_t state;
    uint32_t session_id;
    uint32_t committed_offset;
    uint32_t image_size;
    unsigned credits;
    const char *error_code;
    const char *message;
} vibe_ota_status_snapshot_t;

typedef struct {
    vibe_ota_state_t state;
    vibe_ota_begin_request_t request;
    uint32_t partition_size;
    uint32_t accepted_offset;
    uint32_t committed_offset;
} vibe_ota_session_t;

vibe_ota_protocol_result_t vibe_ota_parse_begin(const char *json,
                                                size_t json_len,
                                                vibe_ota_begin_request_t *request);
vibe_ota_protocol_result_t vibe_ota_parse_command(const char *json,
                                                  size_t json_len,
                                                  vibe_ota_command_t *command);
vibe_ota_protocol_result_t vibe_ota_parse_data_frame(const uint8_t *data,
                                                     size_t data_len,
                                                     vibe_ota_data_frame_t *frame);
int vibe_ota_format_status_json(char *json,
                                size_t json_size,
                                const vibe_ota_status_snapshot_t *snapshot);
const char *vibe_ota_state_to_string(vibe_ota_state_t state);
vibe_ota_protocol_result_t vibe_ota_session_begin(vibe_ota_session_t *session,
                                                  const vibe_ota_begin_request_t *request,
                                                  uint32_t partition_size);
vibe_ota_protocol_result_t vibe_ota_session_accept(vibe_ota_session_t *session,
                                                   uint32_t session_id,
                                                   uint32_t offset,
                                                   size_t payload_len);
vibe_ota_protocol_result_t vibe_ota_session_commit(vibe_ota_session_t *session,
                                                   uint32_t offset,
                                                   size_t payload_len);
uint32_t vibe_ota_session_accepted_offset(const vibe_ota_session_t *session);
uint32_t vibe_ota_session_resume_offset(const vibe_ota_session_t *session);
bool vibe_ota_session_can_finish(const vibe_ota_session_t *session);
void vibe_ota_session_abort(vibe_ota_session_t *session);

#ifdef __cplusplus
}
#endif
