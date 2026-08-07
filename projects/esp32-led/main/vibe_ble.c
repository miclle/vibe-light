#include "vibe_ble.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "host/ble_hs.h"
#include "host/ble_uuid.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "vibe_health.h"
#include "vibe_led_model.h"
#include "vibe_led_output.h"
#include "vibe_status.h"

static const char *TAG = "vibe_led_ble";
static const char *DEVICE_NAME = "VibeLight-LED";

static const ble_uuid128_t VIBE_SERVICE_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x01, 0x00, 0x8f, 0x7d);
static const ble_uuid128_t VIBE_STATUS_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x02, 0x00, 0x8f, 0x7d);
static const ble_uuid128_t VIBE_HEALTH_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x03, 0x00, 0x8f, 0x7d);

static uint16_t current_connection_handle = BLE_HS_CONN_HANDLE_NONE;
static uint8_t own_address_type;
static vibe_status_packet_t current_status;
static int64_t received_at_uptime_ms;
static int64_t traffic_cycle_started_at_uptime_ms;
static char last_parse_error[64];
static portMUX_TYPE status_lock = portMUX_INITIALIZER_UNLOCKED;

static const vibe_led_policy_t POLICY = {
    .codex_7d_red_threshold_percent = CONFIG_VIBE_LED_CODEX_7D_RED_THRESHOLD_PERCENT,
    .success_hold_ms = CONFIG_VIBE_LED_SUCCESS_HOLD_SECONDS * 1000LL,
};

static void advertise(void);
static void apply_current_status(void);

static int64_t uptime_ms(void)
{
    return esp_timer_get_time() / 1000;
}

static void remember_parse_error(const char *message)
{
    snprintf(last_parse_error, sizeof(last_parse_error), "%s", message == NULL ? "unknown" : message);
}

static void apply_current_status(void)
{
    vibe_led_state_t led_state = {0};
    int64_t current_uptime_ms = uptime_ms();

    portENTER_CRITICAL(&status_lock);
    if (current_connection_handle != BLE_HS_CONN_HANDLE_NONE) {
        int64_t now = current_status.timestamp_ms;
        if (now > 0 && received_at_uptime_ms > 0) {
            now += current_uptime_ms - received_at_uptime_ms;
        }
        led_state = vibe_led_state_for_output(
            &current_status,
            now,
            current_uptime_ms,
            traffic_cycle_started_at_uptime_ms,
            &POLICY
        );
    } else {
        led_state = vibe_led_state_for_output(
            NULL,
            0,
            current_uptime_ms,
            traffic_cycle_started_at_uptime_ms,
            &POLICY
        );
    }
    portEXIT_CRITICAL(&status_lock);

    vibe_led_output_set(led_state);
}

static void refresh_timer_callback(void *arg)
{
    (void)arg;
    apply_current_status();
}

static int handle_status_write(uint16_t conn_handle, uint16_t attr_handle, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    uint16_t length = OS_MBUF_PKTLEN(ctxt->om);
    if (length >= 1024) {
        remember_parse_error("packet too large");
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }

    uint8_t *buffer = malloc(length + 1);
    if (buffer == NULL) {
        remember_parse_error("no memory");
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }

    int rc = ble_hs_mbuf_to_flat(ctxt->om, buffer, length, &length);
    if (rc != 0) {
        remember_parse_error("read failed");
        free(buffer);
        return BLE_ATT_ERR_UNLIKELY;
    }
    buffer[length] = '\0';

    vibe_status_packet_t *parsed = malloc(sizeof(*parsed));
    if (parsed == NULL) {
        remember_parse_error("no status memory");
        free(buffer);
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    if (!vibe_status_parse_json(buffer, length, parsed)) {
        remember_parse_error("invalid JSON");
        free(parsed);
        free(buffer);
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }

    ESP_LOGI(TAG, "status write accepted: %s", (char *)buffer);
    free(buffer);

    portENTER_CRITICAL(&status_lock);
    current_status = *parsed;
    received_at_uptime_ms = uptime_ms();
    portEXIT_CRITICAL(&status_lock);
    free(parsed);
    apply_current_status();
    return 0;
}

static int handle_health_read(uint16_t conn_handle, uint16_t attr_handle, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    vibe_display_state_t state;
    bool connected;
    portENTER_CRITICAL(&status_lock);
    state = current_status.state;
    connected = current_connection_handle != BLE_HS_CONN_HANDLE_NONE;
    portEXIT_CRITICAL(&status_lock);

    char payload[320];
    vibe_health_snapshot_t snapshot = {
        .animation_tick = 0,
        .has_indicator_on = true,
        .indicator_on = vibe_led_state_any_on(vibe_led_output_current()),
        .connected = connected,
        .device = DEVICE_NAME,
        .free_heap_bytes = (unsigned)esp_get_free_heap_size(),
        .last_parse_error = last_parse_error,
        .last_state = vibe_display_state_to_string(state),
        .min_free_heap_bytes = (unsigned)esp_get_minimum_free_heap_size(),
        .uptime_ms = uptime_ms(),
    };
    if (vibe_health_format_json(payload, sizeof(payload), &snapshot) < 0) {
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    return os_mbuf_append(ctxt->om, payload, strlen(payload)) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
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
            portENTER_CRITICAL(&status_lock);
            current_connection_handle = event->connect.conn_handle;
            vibe_status_default(&current_status);
            current_status.state = VIBE_DISPLAY_IDLE;
            received_at_uptime_ms = uptime_ms();
            portEXIT_CRITICAL(&status_lock);
            apply_current_status();
        } else {
            advertise();
        }
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        portENTER_CRITICAL(&status_lock);
        current_connection_handle = BLE_HS_CONN_HANDLE_NONE;
        portEXIT_CRITICAL(&status_lock);
        apply_current_status();
        advertise();
        return 0;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        advertise();
        return 0;
    default:
        return 0;
    }
}

static void advertise(void)
{
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = &VIBE_SERVICE_UUID;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to set advertisement fields: %d", rc);
        return;
    }

    struct ble_hs_adv_fields response_fields = {0};
    response_fields.name = (const uint8_t *)DEVICE_NAME;
    response_fields.name_len = strlen(DEVICE_NAME);
    response_fields.name_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&response_fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to set scan response fields: %d", rc);
        return;
    }

    struct ble_gap_adv_params params = {0};
    params.conn_mode = BLE_GAP_CONN_MODE_UND;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    rc = ble_gap_adv_start(own_address_type, NULL, BLE_HS_FOREVER, &params, gap_event, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to start advertising: %d", rc);
    }
}

static void on_sync(void)
{
    int rc = ble_hs_id_infer_auto(0, &own_address_type);
    if (rc == 0) {
        advertise();
    } else {
        ESP_LOGE(TAG, "failed to infer BLE address type: %d", rc);
    }
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

    const esp_timer_create_args_t timer_args = {
        .callback = refresh_timer_callback,
        .name = "vibe_led_refresh",
    };
    traffic_cycle_started_at_uptime_ms = uptime_ms();
    esp_timer_handle_t timer;
    ESP_ERROR_CHECK(esp_timer_create(&timer_args, &timer));
    ESP_ERROR_CHECK(esp_timer_start_periodic(timer, VIBE_LED_SLOW_BLINK_HALF_PERIOD_MS * 1000));
    apply_current_status();

    nimble_port_freertos_init(host_task);
}
