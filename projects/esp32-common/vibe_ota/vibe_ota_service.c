#include "vibe_ota_service.h"

#include <stdio.h>
#include <string.h>

#include "esp_app_desc.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "mbedtls/sha256.h"

#include "vibe_ota_protocol.h"

#define VIBE_OTA_QUEUE_DEPTH 4
#define VIBE_OTA_DISCONNECT_GRACE_US (60LL * 1000LL * 1000LL)
#define VIBE_OTA_WORKER_STACK_SIZE 8192

typedef enum {
    VIBE_OTA_MESSAGE_CONTROL,
    VIBE_OTA_MESSAGE_DATA,
} vibe_ota_message_type_t;

typedef struct {
    vibe_ota_message_type_t type;
    size_t length;
    uint8_t bytes[VIBE_OTA_DATA_FRAME_MAX];
} vibe_ota_message_t;

typedef struct {
    QueueHandle_t queue;
    TaskHandle_t worker;
    vibe_ota_session_t session;
    const esp_partition_t *partition;
    esp_ota_handle_t ota_handle;
    bool ota_open;
    bool sha_open;
    bool connected;
    int64_t disconnected_at_us;
    mbedtls_sha256_context sha256;
    char expected_project_name[VIBE_OTA_PROJECT_NAME_MAX + 1];
    char error_code[32];
    char error_message[80];
    vibe_ota_status_changed_fn status_changed;
    void *status_context;
} vibe_ota_service_state_t;

static const char *TAG = "vibe_ota";
static vibe_ota_service_state_t service;
static portMUX_TYPE service_lock = portMUX_INITIALIZER_UNLOCKED;

static void worker_task(void *context);
static void handle_control(const uint8_t *data, size_t data_len);
static void handle_begin(const vibe_ota_begin_request_t *request);
static void handle_command(const vibe_ota_command_t *command);
static void handle_data(const uint8_t *data, size_t data_len);
static void close_active_ota(void);
static void set_error(const char *code, const char *message);
static void publish_status(void);
static bool session_is_active_locked(void);
static bool requests_match(const vibe_ota_begin_request_t *left,
                           const vibe_ota_begin_request_t *right);
static void digest_to_hex(const unsigned char digest[32], char output[65]);

esp_err_t vibe_ota_service_init(const char *expected_project_name,
                                vibe_ota_status_changed_fn status_changed,
                                void *status_context)
{
    if (expected_project_name == NULL || expected_project_name[0] == '\0' ||
        strlen(expected_project_name) > VIBE_OTA_PROJECT_NAME_MAX) {
        return ESP_ERR_INVALID_ARG;
    }
    if (service.queue != NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    memset(&service, 0, sizeof(service));
    snprintf(service.expected_project_name,
             sizeof(service.expected_project_name),
             "%s",
             expected_project_name);
    service.status_changed = status_changed;
    service.status_context = status_context;
    service.session.state = VIBE_OTA_STATE_IDLE;
    service.queue = xQueueCreate(VIBE_OTA_QUEUE_DEPTH, sizeof(vibe_ota_message_t));
    if (service.queue == NULL) {
        memset(&service, 0, sizeof(service));
        return ESP_ERR_NO_MEM;
    }
    if (xTaskCreate(worker_task,
                    "vibe_ota_worker",
                    VIBE_OTA_WORKER_STACK_SIZE,
                    NULL,
                    5,
                    &service.worker) != pdPASS) {
        vQueueDelete(service.queue);
        memset(&service, 0, sizeof(service));
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

bool vibe_ota_service_enqueue_control(const uint8_t *data, size_t data_len)
{
    if (service.queue == NULL || data == NULL || data_len == 0 ||
        data_len > VIBE_OTA_CONTROL_JSON_MAX) {
        return false;
    }
    vibe_ota_message_t message = {
        .type = VIBE_OTA_MESSAGE_CONTROL,
        .length = data_len,
    };
    memcpy(message.bytes, data, data_len);
    return xQueueSend(service.queue, &message, 0) == pdTRUE;
}

bool vibe_ota_service_enqueue_data(const uint8_t *data, size_t data_len)
{
    if (service.queue == NULL) {
        return false;
    }

    vibe_ota_data_frame_t frame;
    if (vibe_ota_parse_data_frame(data, data_len, &frame) != VIBE_OTA_PROTOCOL_OK) {
        return false;
    }

    vibe_ota_message_t message = {
        .type = VIBE_OTA_MESSAGE_DATA,
        .length = data_len,
    };
    memcpy(message.bytes, data, data_len);

    portENTER_CRITICAL(&service_lock);
    vibe_ota_session_t previous = service.session;
    bool accepted = uxQueueSpacesAvailable(service.queue) > 0 &&
                    vibe_ota_session_accept(&service.session,
                                            frame.session_id,
                                            frame.offset,
                                            frame.payload_len) == VIBE_OTA_PROTOCOL_OK &&
                    xQueueSend(service.queue, &message, 0) == pdTRUE;
    if (!accepted) {
        service.session = previous;
    }
    portEXIT_CRITICAL(&service_lock);
    return accepted;
}

bool vibe_ota_service_format_status(char *json, size_t json_size)
{
    if (json == NULL || json_size == 0 || service.queue == NULL) {
        return false;
    }
    char error_code[sizeof(service.error_code)];
    char error_message[sizeof(service.error_message)];
    portENTER_CRITICAL(&service_lock);
    memcpy(error_code, service.error_code, sizeof(error_code));
    memcpy(error_message, service.error_message, sizeof(error_message));
    vibe_ota_status_snapshot_t snapshot = {
        .state = service.session.state,
        .session_id = service.session.request.session_id,
        .committed_offset = service.session.committed_offset,
        .image_size = service.session.request.image_size,
        .credits = uxQueueSpacesAvailable(service.queue),
        .error_code = error_code,
        .message = error_message,
    };
    portEXIT_CRITICAL(&service_lock);
    int written = vibe_ota_format_status_json(json, json_size, &snapshot);
    return written >= 0;
}

void vibe_ota_service_on_connected(void)
{
    if (service.queue == NULL) {
        return;
    }
    portENTER_CRITICAL(&service_lock);
    service.connected = true;
    service.disconnected_at_us = 0;
    portEXIT_CRITICAL(&service_lock);
    publish_status();
}

void vibe_ota_service_on_disconnected(void)
{
    if (service.queue == NULL) {
        return;
    }
    portENTER_CRITICAL(&service_lock);
    service.connected = false;
    if (session_is_active_locked()) {
        service.disconnected_at_us = esp_timer_get_time();
    }
    portEXIT_CRITICAL(&service_lock);
}

bool vibe_ota_service_is_active(void)
{
    if (service.queue == NULL) {
        return false;
    }
    portENTER_CRITICAL(&service_lock);
    bool active = session_is_active_locked();
    portEXIT_CRITICAL(&service_lock);
    return active;
}

static void worker_task(void *context)
{
    (void)context;
    vibe_ota_message_t message;
    while (true) {
        if (xQueueReceive(service.queue, &message, pdMS_TO_TICKS(500)) == pdTRUE) {
            if (message.type == VIBE_OTA_MESSAGE_CONTROL) {
                handle_control(message.bytes, message.length);
            } else {
                handle_data(message.bytes, message.length);
            }
        }

        portENTER_CRITICAL(&service_lock);
        bool expired = !service.connected && service.disconnected_at_us > 0 &&
                       session_is_active_locked() &&
                       esp_timer_get_time() - service.disconnected_at_us >=
                           VIBE_OTA_DISCONNECT_GRACE_US;
        portEXIT_CRITICAL(&service_lock);
        if (expired) {
            close_active_ota();
            portENTER_CRITICAL(&service_lock);
            vibe_ota_session_abort(&service.session);
            service.error_code[0] = '\0';
            service.error_message[0] = '\0';
            service.disconnected_at_us = 0;
            portEXIT_CRITICAL(&service_lock);
            publish_status();
        }
    }
}

static void handle_control(const uint8_t *data, size_t data_len)
{
    vibe_ota_begin_request_t begin;
    if (vibe_ota_parse_begin((const char *)data, data_len, &begin) == VIBE_OTA_PROTOCOL_OK) {
        handle_begin(&begin);
        return;
    }

    vibe_ota_command_t command;
    if (vibe_ota_parse_command((const char *)data, data_len, &command) == VIBE_OTA_PROTOCOL_OK) {
        handle_command(&command);
        return;
    }
    if (vibe_ota_service_is_active()) {
        ESP_LOGW(TAG, "ignored invalid control message during active OTA session");
        publish_status();
        return;
    }
    set_error("INVALID_CONTROL", "Invalid OTA control message");
}

static void handle_begin(const vibe_ota_begin_request_t *request)
{
    portENTER_CRITICAL(&service_lock);
    bool active = session_is_active_locked();
    bool same_request = active && requests_match(&service.session.request, request);
    portEXIT_CRITICAL(&service_lock);
    if (same_request) {
        publish_status();
        return;
    }
    if (active) {
        ESP_LOGW(TAG, "ignored begin for a different session while OTA is active");
        publish_status();
        return;
    }
    if (strcmp(request->project_name, service.expected_project_name) != 0) {
        set_error("WRONG_TARGET", "Firmware project does not match this device");
        return;
    }

    const esp_partition_t *partition = esp_ota_get_next_update_partition(NULL);
    if (partition == NULL || request->image_size > partition->size) {
        set_error("NO_OTA_SLOT", "No OTA slot can hold this firmware");
        return;
    }

    esp_ota_handle_t handle;
    esp_err_t err = esp_ota_begin(partition, request->image_size, &handle);
    if (err != ESP_OK) {
        set_error("OTA_BEGIN_FAILED", esp_err_to_name(err));
        return;
    }

    mbedtls_sha256_init(&service.sha256);
    if (mbedtls_sha256_starts(&service.sha256, 0) != 0) {
        esp_ota_abort(handle);
        mbedtls_sha256_free(&service.sha256);
        set_error("SHA_INIT_FAILED", "Could not initialize SHA-256");
        return;
    }

    portENTER_CRITICAL(&service_lock);
    vibe_ota_protocol_result_t result =
        vibe_ota_session_begin(&service.session, request, partition->size);
    if (result == VIBE_OTA_PROTOCOL_OK) {
        service.partition = partition;
        service.ota_handle = handle;
        service.ota_open = true;
        service.sha_open = true;
        service.error_code[0] = '\0';
        service.error_message[0] = '\0';
    }
    portEXIT_CRITICAL(&service_lock);
    if (result != VIBE_OTA_PROTOCOL_OK) {
        esp_ota_abort(handle);
        mbedtls_sha256_free(&service.sha256);
        set_error("INVALID_BEGIN", "Invalid OTA image size or metadata");
        return;
    }
    ESP_LOGI(TAG, "OTA session %u ready for %u bytes", request->session_id, request->image_size);
    publish_status();
}

static void handle_command(const vibe_ota_command_t *command)
{
    portENTER_CRITICAL(&service_lock);
    bool matches = session_is_active_locked() &&
                   command->session_id == service.session.request.session_id;
    bool can_finish = matches && vibe_ota_session_can_finish(&service.session);
    if (can_finish) {
        service.session.state = VIBE_OTA_STATE_VERIFYING;
    }
    portEXIT_CRITICAL(&service_lock);

    if (!matches) {
        if (vibe_ota_service_is_active()) {
            ESP_LOGW(TAG, "ignored command for a different OTA session");
            publish_status();
        } else {
            set_error("SESSION_MISMATCH", "OTA session does not match");
        }
        return;
    }
    if (command->operation == VIBE_OTA_OPERATION_ABORT) {
        close_active_ota();
        portENTER_CRITICAL(&service_lock);
        vibe_ota_session_abort(&service.session);
        service.error_code[0] = '\0';
        service.error_message[0] = '\0';
        portEXIT_CRITICAL(&service_lock);
        publish_status();
        return;
    }
    if (!can_finish) {
        ESP_LOGW(TAG, "ignored finish before all firmware bytes were committed");
        publish_status();
        return;
    }

    publish_status();
    unsigned char digest[32];
    char digest_hex[65];
    if (mbedtls_sha256_finish(&service.sha256, digest) != 0) {
        set_error("SHA_FINISH_FAILED", "Could not finish SHA-256");
        return;
    }
    mbedtls_sha256_free(&service.sha256);
    service.sha_open = false;
    digest_to_hex(digest, digest_hex);

    if (strcmp(digest_hex, service.session.request.sha256_hex) != 0) {
        set_error("SHA_MISMATCH", "Firmware SHA-256 does not match manifest");
        return;
    }
    esp_err_t err = esp_ota_end(service.ota_handle);
    service.ota_open = false;
    if (err != ESP_OK) {
        set_error("IMAGE_REJECTED", esp_err_to_name(err));
        return;
    }

    esp_app_desc_t description;
    err = esp_ota_get_partition_description(service.partition, &description);
    if (err != ESP_OK || strcmp(description.project_name, service.expected_project_name) != 0 ||
        strcmp(description.version, service.session.request.app_version) != 0) {
        set_error("IMAGE_IDENTITY_MISMATCH", "Firmware identity does not match manifest");
        return;
    }
    err = esp_ota_set_boot_partition(service.partition);
    if (err != ESP_OK) {
        set_error("SET_BOOT_FAILED", esp_err_to_name(err));
        return;
    }

    portENTER_CRITICAL(&service_lock);
    service.session.state = VIBE_OTA_STATE_REBOOTING;
    portEXIT_CRITICAL(&service_lock);
    ESP_LOGI(TAG, "OTA verified; rebooting into version %s", description.version);
    publish_status();
    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
}

static void handle_data(const uint8_t *data, size_t data_len)
{
    vibe_ota_data_frame_t frame;
    if (vibe_ota_parse_data_frame(data, data_len, &frame) != VIBE_OTA_PROTOCOL_OK) {
        set_error("INVALID_DATA", "Invalid OTA data frame");
        return;
    }

    portENTER_CRITICAL(&service_lock);
    bool writable = service.ota_open && service.sha_open &&
                    service.session.state == VIBE_OTA_STATE_RECEIVING &&
                    frame.session_id == service.session.request.session_id &&
                    frame.offset == service.session.committed_offset;
    portEXIT_CRITICAL(&service_lock);
    if (!writable) {
        ESP_LOGW(TAG, "ignored stale OTA data frame after session state changed");
        publish_status();
        return;
    }

    esp_err_t err = esp_ota_write(service.ota_handle, frame.payload, frame.payload_len);
    if (err != ESP_OK || mbedtls_sha256_update(&service.sha256, frame.payload, frame.payload_len) != 0) {
        set_error("FLASH_WRITE_FAILED", err == ESP_OK ? "SHA-256 update failed" : esp_err_to_name(err));
        return;
    }

    portENTER_CRITICAL(&service_lock);
    vibe_ota_protocol_result_t result =
        vibe_ota_session_commit(&service.session, frame.offset, frame.payload_len);
    portEXIT_CRITICAL(&service_lock);
    if (result != VIBE_OTA_PROTOCOL_OK) {
        set_error("COMMIT_FAILED", "OTA committed offset became inconsistent");
        return;
    }
    publish_status();
}

static void close_active_ota(void)
{
    if (service.ota_open) {
        esp_ota_abort(service.ota_handle);
        service.ota_open = false;
    }
    if (service.sha_open) {
        mbedtls_sha256_free(&service.sha256);
        service.sha_open = false;
    }
}

static void set_error(const char *code, const char *message)
{
    close_active_ota();
    portENTER_CRITICAL(&service_lock);
    service.session.state = VIBE_OTA_STATE_ERROR;
    snprintf(service.error_code, sizeof(service.error_code), "%s", code);
    snprintf(service.error_message, sizeof(service.error_message), "%s", message);
    portEXIT_CRITICAL(&service_lock);
    ESP_LOGE(TAG, "%s: %s", code, message);
    publish_status();
}

static void publish_status(void)
{
    if (service.status_changed != NULL) {
        service.status_changed(service.status_context);
    }
}

static bool session_is_active_locked(void)
{
    return service.session.state == VIBE_OTA_STATE_READY ||
           service.session.state == VIBE_OTA_STATE_RECEIVING ||
           service.session.state == VIBE_OTA_STATE_VERIFYING ||
           service.session.state == VIBE_OTA_STATE_REBOOTING;
}

static bool requests_match(const vibe_ota_begin_request_t *left,
                           const vibe_ota_begin_request_t *right)
{
    return left->session_id == right->session_id &&
           left->image_size == right->image_size &&
           strcmp(left->project_name, right->project_name) == 0 &&
           strcmp(left->app_version, right->app_version) == 0 &&
           strcmp(left->sha256_hex, right->sha256_hex) == 0;
}

static void digest_to_hex(const unsigned char digest[32], char output[65])
{
    static const char HEX[] = "0123456789abcdef";
    for (size_t index = 0; index < 32; index++) {
        output[index * 2] = HEX[digest[index] >> 4];
        output[index * 2 + 1] = HEX[digest[index] & 0x0f];
    }
    output[64] = '\0';
}
