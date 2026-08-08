#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_OTA_STATUS_JSON_MAX 256

typedef void (*vibe_ota_status_changed_fn)(void *context);

esp_err_t vibe_ota_service_init(const char *expected_project_name,
                                vibe_ota_status_changed_fn status_changed,
                                void *status_context);
bool vibe_ota_service_enqueue_control(const uint8_t *data, size_t data_len);
bool vibe_ota_service_enqueue_data(const uint8_t *data, size_t data_len);
bool vibe_ota_service_format_status(char *json, size_t json_size);
void vibe_ota_service_on_connected(void);
void vibe_ota_service_on_disconnected(void);
bool vibe_ota_service_is_active(void);

#ifdef __cplusplus
}
#endif
