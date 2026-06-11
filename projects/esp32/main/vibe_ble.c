#include "vibe_ble.h"

#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "esp_err.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "host/ble_hs.h"
#include "host/ble_uuid.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "vibe_display.h"
#include "vibe_health.h"
#include "vibe_status.h"

static const char *TAG = "vibe_ble";
static const char *DEVICE_NAME = "VibeLight-S3";

static const ble_uuid128_t VIBE_SERVICE_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x01, 0x00, 0x8f, 0x7d);
static const ble_uuid128_t VIBE_STATUS_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x02, 0x00, 0x8f, 0x7d);
static const ble_uuid128_t VIBE_HEALTH_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x03, 0x00, 0x8f, 0x7d);

static uint16_t current_connection_handle = BLE_HS_CONN_HANDLE_NONE;
static uint8_t own_address_type;
static vibe_status_packet_t current_status;
static char last_parse_error[64];

static void advertise(void);
static void remember_parse_error(const char *message);
static void show_connection_status(bool connected);

static int handle_status_write(uint16_t conn_handle, uint16_t attr_handle, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    uint16_t length = OS_MBUF_PKTLEN(ctxt->om);
    if (length >= 1024) {
        ESP_LOGW(TAG, "status packet too large: %u bytes", length);
        remember_parse_error("packet too large");
        vibe_display_show_error("packet too large");
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }

    uint8_t *buffer = malloc(length + 1);
    if (buffer == NULL) {
        ESP_LOGW(TAG, "failed to allocate status packet buffer: %u bytes", length + 1);
        remember_parse_error("no memory");
        vibe_display_show_error("no memory");
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }

    int rc = ble_hs_mbuf_to_flat(ctxt->om, buffer, length, &length);
    if (rc != 0) {
        ESP_LOGW(TAG, "failed to read status packet: %d", rc);
        remember_parse_error("read failed");
        vibe_display_show_error("read failed");
        free(buffer);
        return BLE_ATT_ERR_UNLIKELY;
    }
    buffer[length] = '\0';

    if (!vibe_status_parse_json(buffer, length, &current_status)) {
        ESP_LOGW(TAG, "invalid status packet: %s", (char *)buffer);
        remember_parse_error("invalid JSON");
        vibe_display_show_error("invalid JSON");
        free(buffer);
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }

    ESP_LOGI(TAG, "status write accepted: %s", (char *)buffer);
    free(buffer);
    vibe_display_show_status(&current_status);
    return 0;
}

static int handle_health_read(uint16_t conn_handle, uint16_t attr_handle, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    char payload[320];
    vibe_health_snapshot_t snapshot = {
        .animation_tick = vibe_display_animation_tick(),
        .backlight_on = vibe_display_backlight_on(),
        .connected = current_connection_handle != BLE_HS_CONN_HANDLE_NONE,
        .device = DEVICE_NAME,
        .free_heap_bytes = (unsigned)esp_get_free_heap_size(),
        .last_parse_error = last_parse_error,
        .last_state = vibe_display_state_to_string(current_status.state),
        .min_free_heap_bytes = (unsigned)esp_get_minimum_free_heap_size(),
        .uptime_ms = esp_timer_get_time() / 1000,
    };
    int written = vibe_health_format_json(payload, sizeof(payload), &snapshot);
    if (written < 0) {
        ESP_LOGW(TAG, "failed to format health packet");
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }

    int rc = os_mbuf_append(ctxt->om, payload, strlen(payload));
    return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static void remember_parse_error(const char *message)
{
    snprintf(last_parse_error, sizeof(last_parse_error), "%s", message == NULL ? "unknown" : message);
}

static const struct ble_gatt_svc_def gatt_services[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &VIBE_SERVICE_UUID.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = &VIBE_STATUS_UUID.u,
                .access_cb = handle_status_write,
                .flags = BLE_GATT_CHR_F_WRITE,
            },
            {
                .uuid = &VIBE_HEALTH_UUID.u,
                .access_cb = handle_health_read,
                .flags = BLE_GATT_CHR_F_READ,
            },
            {0},
        },
    },
    {0},
};

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;

    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            current_connection_handle = event->connect.conn_handle;
            ESP_LOGI(TAG, "central connected");
            show_connection_status(true);
        } else {
            ESP_LOGW(TAG, "connect failed: %d", event->connect.status);
            advertise();
        }
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "central disconnected: %d", event->disconnect.reason);
        current_connection_handle = BLE_HS_CONN_HANDLE_NONE;
        show_connection_status(false);
        advertise();
        return 0;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        advertise();
        return 0;
    default:
        return 0;
    }
}

static void show_connection_status(bool connected)
{
    vibe_status_default(&current_status);
    current_status.version = 2;
    snprintf(current_status.source, sizeof(current_status.source), "%s", "other");
    current_status.state = connected ? VIBE_DISPLAY_IDLE : VIBE_DISPLAY_OFFLINE;
    snprintf(current_status.state_text, sizeof(current_status.state_text), "%s", connected ? "idle" : "offline");
    snprintf(current_status.detail, sizeof(current_status.detail), "%s", connected ? "desktop connected" : "desktop disconnected");
    current_status.timestamp_ms = 0;

    vibe_display_show_status(&current_status);
}

static void advertise(void)
{
    struct ble_hs_adv_fields fields;
    memset(&fields, 0, sizeof(fields));

    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = &VIBE_SERVICE_UUID;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;

    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to set advertisement fields: %d", rc);
        return;
    }

    struct ble_hs_adv_fields response_fields;
    memset(&response_fields, 0, sizeof(response_fields));
    response_fields.name = (const uint8_t *)DEVICE_NAME;
    response_fields.name_len = strlen(DEVICE_NAME);
    response_fields.name_is_complete = 1;

    rc = ble_gap_adv_rsp_set_fields(&response_fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to set scan response fields: %d", rc);
        return;
    }

    struct ble_gap_adv_params params;
    memset(&params, 0, sizeof(params));
    params.conn_mode = BLE_GAP_CONN_MODE_UND;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;

    rc = ble_gap_adv_start(own_address_type, NULL, BLE_HS_FOREVER, &params, gap_event, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to start advertising: %d", rc);
        return;
    }

    ESP_LOGI(TAG, "advertising as %s", DEVICE_NAME);
}

static void on_sync(void)
{
    int rc = ble_hs_id_infer_auto(0, &own_address_type);
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to infer BLE address type: %d", rc);
        return;
    }

    advertise();
}

static void host_task(void *param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

void vibe_ble_start(void)
{
    vibe_status_default(&current_status);

    ESP_ERROR_CHECK(nimble_port_init());
    ble_svc_gap_init();
    ble_svc_gatt_init();

    int rc = ble_svc_gap_device_name_set(DEVICE_NAME);
    assert(rc == 0);

    rc = ble_gatts_count_cfg(gatt_services);
    assert(rc == 0);

    rc = ble_gatts_add_svcs(gatt_services);
    assert(rc == 0);

    ble_hs_cfg.sync_cb = on_sync;

    nimble_port_freertos_init(host_task);
}
