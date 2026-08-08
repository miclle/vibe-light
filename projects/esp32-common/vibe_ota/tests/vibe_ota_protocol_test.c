#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "vibe_ota_protocol.h"

static const char *VALID_SHA256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

static void test_parses_valid_begin_request(void)
{
    char json[320];
    snprintf(json,
             sizeof(json),
             "{\"v\":1,\"op\":\"begin\",\"sessionId\":287454020,\"imageSize\":556640,"
             "\"projectName\":\"vibe_light_led\",\"appVersion\":\"v0.1.3-1-g1234567\",\"sha256\":\"%s\"}",
             VALID_SHA256);

    vibe_ota_begin_request_t request = {0};
    assert(vibe_ota_parse_begin(json, strlen(json), &request) == VIBE_OTA_PROTOCOL_OK);
    assert(request.protocol_version == 1);
    assert(request.session_id == 0x11223344);
    assert(request.image_size == 556640);
    assert(strcmp(request.project_name, "vibe_light_led") == 0);
    assert(strcmp(request.app_version, "v0.1.3-1-g1234567") == 0);
    assert(strcmp(request.sha256_hex, VALID_SHA256) == 0);
}

static void test_rejects_invalid_begin_without_mutating_output(void)
{
    const char *invalid_requests[] = {
        "{\"v\":1,\"op\":\"begin\",\"sessionId\":1,\"imageSize\":0,\"projectName\":\"vibe_light_led\",\"appVersion\":\"v1\",\"sha256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}",
        "{\"v\":1,\"op\":\"begin\",\"sessionId\":1,\"imageSize\":4294967296,\"projectName\":\"vibe_light_led\",\"appVersion\":\"v1\",\"sha256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}",
        "{\"v\":1,\"op\":\"begin\",\"sessionId\":1,\"imageSize\":12,\"projectName\":\"\",\"appVersion\":\"v1\",\"sha256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}",
        "{\"v\":1,\"op\":\"begin\",\"sessionId\":1,\"imageSize\":12,\"projectName\":\"vibe_light_led\",\"appVersion\":\"v1\",\"sha256\":\"not-a-sha\"}",
        "{\"v\":1,\"op\":\"begin\",\"sessionId\":1,\"projectName\":\"vibe_light_led\",\"appVersion\":\"v1\",\"sha256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}",
    };

    for (size_t index = 0; index < sizeof(invalid_requests) / sizeof(invalid_requests[0]); index++) {
        vibe_ota_begin_request_t request;
        memset(&request, 0xA5, sizeof(request));
        vibe_ota_begin_request_t before = request;

        assert(vibe_ota_parse_begin(invalid_requests[index], strlen(invalid_requests[index]), &request) != VIBE_OTA_PROTOCOL_OK);
        assert(memcmp(&request, &before, sizeof(request)) == 0);
    }
}

static void test_parses_finish_and_abort_commands(void)
{
    vibe_ota_command_t command = {0};
    const char *finish = "{\"v\":1,\"op\":\"finish\",\"sessionId\":287454020}";
    assert(vibe_ota_parse_command(finish, strlen(finish), &command) == VIBE_OTA_PROTOCOL_OK);
    assert(command.operation == VIBE_OTA_OPERATION_FINISH);
    assert(command.session_id == 0x11223344);

    const char *abort = "{\"v\":1,\"op\":\"abort\",\"sessionId\":287454020}";
    assert(vibe_ota_parse_command(abort, strlen(abort), &command) == VIBE_OTA_PROTOCOL_OK);
    assert(command.operation == VIBE_OTA_OPERATION_ABORT);
    assert(command.session_id == 0x11223344);
}

static void test_parses_little_endian_data_frame(void)
{
    const uint8_t bytes[] = {
        0x44, 0x33, 0x22, 0x11,
        0x00, 0x10, 0x00, 0x00,
        0xDE, 0xAD, 0xBE, 0xEF,
    };
    vibe_ota_data_frame_t frame = {0};

    assert(vibe_ota_parse_data_frame(bytes, sizeof(bytes), &frame) == VIBE_OTA_PROTOCOL_OK);
    assert(frame.session_id == 0x11223344);
    assert(frame.offset == 0x1000);
    assert(frame.payload_len == 4);
    assert(memcmp(frame.payload, &bytes[8], 4) == 0);
}

static void test_rejects_invalid_data_frame_without_mutating_output(void)
{
    uint8_t short_frame[7] = {0};
    uint8_t oversized_frame[VIBE_OTA_DATA_FRAME_MAX + 1] = {0};
    vibe_ota_data_frame_t parsed;
    memset(&parsed, 0xA5, sizeof(parsed));
    vibe_ota_data_frame_t before = parsed;

    assert(vibe_ota_parse_data_frame(short_frame, sizeof(short_frame), &parsed) == VIBE_OTA_PROTOCOL_INVALID_LENGTH);
    assert(memcmp(&parsed, &before, sizeof(parsed)) == 0);
    assert(vibe_ota_parse_data_frame(oversized_frame, sizeof(oversized_frame), &parsed) == VIBE_OTA_PROTOCOL_INVALID_LENGTH);
    assert(memcmp(&parsed, &before, sizeof(parsed)) == 0);
}

static void test_formats_receiving_status(void)
{
    vibe_ota_status_snapshot_t snapshot = {
        .state = VIBE_OTA_STATE_RECEIVING,
        .session_id = 0x11223344,
        .committed_offset = 4096,
        .image_size = 556640,
        .credits = 4,
    };
    char json[256];

    int written = vibe_ota_format_status_json(json, sizeof(json), &snapshot);
    assert(written > 0);
    assert(strcmp(json,
                  "{\"v\":1,\"state\":\"receiving\",\"sessionId\":287454020,\"committedOffset\":4096,\"imageSize\":556640,\"credits\":4}") == 0);
}

static void test_formats_error_status_with_machine_code(void)
{
    vibe_ota_status_snapshot_t snapshot = {
        .state = VIBE_OTA_STATE_ERROR,
        .session_id = 0x11223344,
        .committed_offset = 4096,
        .image_size = 556640,
        .credits = 0,
        .error_code = "sha_mismatch",
        .message = "image hash mismatch",
    };
    char json[256];

    int written = vibe_ota_format_status_json(json, sizeof(json), &snapshot);
    assert(written > 0);
    assert(strcmp(json,
                  "{\"v\":1,\"state\":\"error\",\"sessionId\":287454020,\"committedOffset\":4096,\"imageSize\":556640,\"credits\":0,\"errorCode\":\"sha_mismatch\",\"message\":\"image hash mismatch\"}") == 0);
}

static vibe_ota_begin_request_t make_begin_request(uint32_t image_size)
{
    vibe_ota_begin_request_t request = {
        .protocol_version = VIBE_OTA_PROTOCOL_VERSION,
        .session_id = 0x11223344,
        .image_size = image_size,
    };
    snprintf(request.project_name, sizeof(request.project_name), "%s", "vibe_light_led");
    snprintf(request.app_version, sizeof(request.app_version), "%s", "v0.1.3-1-g1234567");
    snprintf(request.sha256_hex, sizeof(request.sha256_hex), "%s", VALID_SHA256);
    return request;
}

static void test_session_separates_accepted_and_committed_offsets(void)
{
    vibe_ota_session_t session = {0};
    vibe_ota_begin_request_t request = make_begin_request(1000);

    assert(vibe_ota_session_begin(&session, &request, 0x400000) == VIBE_OTA_PROTOCOL_OK);
    assert(vibe_ota_session_accept(&session, request.session_id, 0, 500) == VIBE_OTA_PROTOCOL_OK);
    assert(vibe_ota_session_accepted_offset(&session) == 500);
    assert(vibe_ota_session_resume_offset(&session) == 0);

    assert(vibe_ota_session_accept(&session, request.session_id, 1000, 100) == VIBE_OTA_PROTOCOL_UNEXPECTED_OFFSET);
    assert(vibe_ota_session_accept(&session, request.session_id + 1, 500, 100) == VIBE_OTA_PROTOCOL_SESSION_MISMATCH);
    assert(vibe_ota_session_accepted_offset(&session) == 500);
    assert(vibe_ota_session_resume_offset(&session) == 0);

    assert(vibe_ota_session_commit(&session, 0, 500) == VIBE_OTA_PROTOCOL_OK);
    assert(vibe_ota_session_resume_offset(&session) == 500);
    assert(!vibe_ota_session_can_finish(&session));

    assert(vibe_ota_session_accept(&session, request.session_id, 500, 500) == VIBE_OTA_PROTOCOL_OK);
    assert(vibe_ota_session_commit(&session, 500, 500) == VIBE_OTA_PROTOCOL_OK);
    assert(vibe_ota_session_can_finish(&session));
}

static void test_session_rejects_oversized_image_and_invalid_commit(void)
{
    vibe_ota_session_t session;
    memset(&session, 0xA5, sizeof(session));
    vibe_ota_session_t before = session;
    vibe_ota_begin_request_t oversized = make_begin_request(0x400001);

    assert(vibe_ota_session_begin(&session, &oversized, 0x400000) == VIBE_OTA_PROTOCOL_INVALID_SIZE);
    assert(memcmp(&session, &before, sizeof(session)) == 0);

    memset(&session, 0, sizeof(session));
    vibe_ota_begin_request_t request = make_begin_request(1000);
    assert(vibe_ota_session_begin(&session, &request, 0x400000) == VIBE_OTA_PROTOCOL_OK);
    assert(vibe_ota_session_accept(&session, request.session_id, 0, 500) == VIBE_OTA_PROTOCOL_OK);
    assert(vibe_ota_session_commit(&session, 1, 499) == VIBE_OTA_PROTOCOL_UNEXPECTED_OFFSET);
    assert(vibe_ota_session_resume_offset(&session) == 0);
}

static void test_session_abort_returns_to_idle(void)
{
    vibe_ota_session_t session = {0};
    vibe_ota_begin_request_t request = make_begin_request(1000);
    assert(vibe_ota_session_begin(&session, &request, 0x400000) == VIBE_OTA_PROTOCOL_OK);
    vibe_ota_session_abort(&session);
    assert(session.state == VIBE_OTA_STATE_IDLE);
    assert(vibe_ota_session_resume_offset(&session) == 0);
    assert(vibe_ota_session_accepted_offset(&session) == 0);
}

int main(void)
{
    test_parses_valid_begin_request();
    test_rejects_invalid_begin_without_mutating_output();
    test_parses_finish_and_abort_commands();
    test_parses_little_endian_data_frame();
    test_rejects_invalid_data_frame_without_mutating_output();
    test_formats_receiving_status();
    test_formats_error_status_with_machine_code();
    test_session_separates_accepted_and_committed_offsets();
    test_session_rejects_oversized_image_and_invalid_commit();
    test_session_abort_returns_to_idle();
    puts("vibe_ota_protocol_test: ok");
    return 0;
}
