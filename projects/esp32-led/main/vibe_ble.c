#include "vibe_ble.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "esp_app_desc.h"
#include "esp_ota_ops.h"
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
#include "vibe_ota_protocol.h"
#include "vibe_ota_service.h"
#include "vibe_status.h"

static const char *TAG = "vibe_led_ble";
static const char *DEVICE_NAME = "VibeLight-LED";

static const ble_uuid128_t VIBE_SERVICE_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x01, 0x00, 0x8f, 0x7d);
static const ble_uuid128_t VIBE_STATUS_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x02, 0x00, 0x8f, 0x7d);
static const ble_uuid128_t VIBE_HEALTH_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x03, 0x00, 0x8f, 0x7d);
static const ble_uuid128_t VIBE_OTA_SERVICE_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x01, 0x01, 0x8f, 0x7d);
static const ble_uuid128_t VIBE_OTA_CONTROL_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x02, 0x01, 0x8f, 0x7d);
static const ble_uuid128_t VIBE_OTA_DATA_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x03, 0x01, 0x8f, 0x7d);
static const ble_uuid128_t VIBE_OTA_STATUS_UUID =
    BLE_UUID128_INIT(0x00, 0x10, 0x7f, 0x2c, 0x4c, 0x8b, 0x8a, 0x9e, 0x0b, 0x4f, 0x9a, 0x7b, 0x04, 0x01, 0x8f, 0x7d);

static uint16_t current_connection_handle = BLE_HS_CONN_HANDLE_NONE;
static uint16_t ota_status_value_handle;
static uint8_t own_address_type;
static vibe_status_packet_t current_status;
static int64_t received_at_uptime_ms;
static int64_t traffic_cycle_started_at_uptime_ms;
static char last_parse_error[64];
static portMUX_TYPE status_lock = portMUX_INITIALIZER_UNLOCKED;
static bool running_image_validated;

static const vibe_led_policy_t POLICY = {
    .codex_7d_red_threshold_percent = CONFIG_VIBE_LED_CODEX_7D_RED_THRESHOLD_PERCENT,
    .success_hold_ms = CONFIG_VIBE_LED_SUCCESS_HOLD_SECONDS * 1000LL,
};

static bool advertise(void);
static void apply_current_status(void);

static const char *rollback_state_name(const esp_partition_t *partition)
{
    esp_ota_img_states_t state;
    if (partition == NULL || esp_ota_get_state_partition(partition, &state) != ESP_OK) {
        return "unknown";
    }
    switch (state) {
    case ESP_OTA_IMG_NEW:
        return "new";
    case ESP_OTA_IMG_PENDING_VERIFY:
        return "pendingVerify";
    case ESP_OTA_IMG_VALID:
        return "valid";
    case ESP_OTA_IMG_INVALID:
        return "invalid";
    case ESP_OTA_IMG_ABORTED:
        return "aborted";
    case ESP_OTA_IMG_UNDEFINED:
    default:
        return "undefined";
    }
}

static void validate_running_image_after_ble_ready(void)
{
    if (running_image_validated) {
        return;
    }
    const esp_partition_t *partition = esp_ota_get_running_partition();
    esp_ota_img_states_t state;
    if (partition != NULL && esp_ota_get_state_partition(partition, &state) == ESP_OK &&
        state == ESP_OTA_IMG_PENDING_VERIFY) {
        esp_err_t err = esp_ota_mark_app_valid_cancel_rollback();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "failed to validate OTA image: %s", esp_err_to_name(err));
            return;
        }
        ESP_LOGI(TAG, "OTA image marked valid after BLE became ready");
    }
    running_image_validated = true;
}

static void ota_status_changed(void *context)
{
    (void)context;
    if (ota_status_value_handle != 0) {
        ble_gatts_chr_updated(ota_status_value_handle);
    }
}

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

    char payload[512];
    const esp_app_desc_t *app = esp_app_get_description();
    const esp_partition_t *running = esp_ota_get_running_partition();
    vibe_health_snapshot_t snapshot = {
        .animation_tick = 0,
        .has_indicator_on = true,
        .indicator_on = vibe_led_state_any_on(vibe_led_output_current()),
        .connected = connected,
        .device = DEVICE_NAME,
        .free_heap_bytes = (unsigned)esp_get_free_heap_size(),
        .firmware_version = app == NULL ? "" : app->version,
        .last_parse_error = last_parse_error,
        .last_state = vibe_display_state_to_string(state),
        .min_free_heap_bytes = (unsigned)esp_get_minimum_free_heap_size(),
        .ota_capable = true,
        .project_name = app == NULL ? "" : app->project_name,
        .rollback_state = rollback_state_name(running),
        .running_slot = running == NULL ? "" : running->label,
#ifdef CONFIG_SECURE_SIGNED_ON_UPDATE_NO_SECURE_BOOT
        .signed_updates_required = true,
#else
        .signed_updates_required = false,
#endif
        .uptime_ms = uptime_ms(),
    };
    if (vibe_health_format_json(payload, sizeof(payload), &snapshot) < 0) {
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    return os_mbuf_append(ctxt->om, payload, strlen(payload)) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int handle_ota_control_write(uint16_t conn_handle,
                                    uint16_t attr_handle,
                                    struct ble_gatt_access_ctxt *ctxt,
                                    void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    uint16_t length = OS_MBUF_PKTLEN(ctxt->om);
    if (length == 0 || length > VIBE_OTA_CONTROL_JSON_MAX) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    uint8_t buffer[VIBE_OTA_CONTROL_JSON_MAX];
    if (ble_hs_mbuf_to_flat(ctxt->om, buffer, length, &length) != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    return vibe_ota_service_enqueue_control(buffer, length) ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int handle_ota_data_write(uint16_t conn_handle,
                                 uint16_t attr_handle,
                                 struct ble_gatt_access_ctxt *ctxt,
                                 void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    uint16_t length = OS_MBUF_PKTLEN(ctxt->om);
    if (length <= VIBE_OTA_DATA_HEADER_SIZE || length > VIBE_OTA_DATA_FRAME_MAX) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    uint8_t buffer[VIBE_OTA_DATA_FRAME_MAX];
    if (ble_hs_mbuf_to_flat(ctxt->om, buffer, length, &length) != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    return vibe_ota_service_enqueue_data(buffer, length) ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int handle_ota_status_read(uint16_t conn_handle,
                                  uint16_t attr_handle,
                                  struct ble_gatt_access_ctxt *ctxt,
                                  void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    char payload[VIBE_OTA_STATUS_JSON_MAX];
    if (!vibe_ota_service_format_status(payload, sizeof(payload))) {
        return BLE_ATT_ERR_UNLIKELY;
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
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &VIBE_OTA_SERVICE_UUID.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = &VIBE_OTA_CONTROL_UUID.u,
                .access_cb = handle_ota_control_write,
                .flags = BLE_GATT_CHR_F_WRITE,
            },
            {
                .uuid = &VIBE_OTA_DATA_UUID.u,
                .access_cb = handle_ota_data_write,
                .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
            },
            {
                .uuid = &VIBE_OTA_STATUS_UUID.u,
                .access_cb = handle_ota_status_read,
                .val_handle = &ota_status_value_handle,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
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
            vibe_ota_service_on_connected();
            apply_current_status();
        } else {
            advertise();
        }
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        portENTER_CRITICAL(&status_lock);
        current_connection_handle = BLE_HS_CONN_HANDLE_NONE;
        portEXIT_CRITICAL(&status_lock);
        vibe_ota_service_on_disconnected();
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

static bool advertise(void)
{
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = &VIBE_SERVICE_UUID;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to set advertisement fields: %d", rc);
        return false;
    }

    struct ble_hs_adv_fields response_fields = {0};
    response_fields.name = (const uint8_t *)DEVICE_NAME;
    response_fields.name_len = strlen(DEVICE_NAME);
    response_fields.name_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&response_fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to set scan response fields: %d", rc);
        return false;
    }

    struct ble_gap_adv_params params = {0};
    params.conn_mode = BLE_GAP_CONN_MODE_UND;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    rc = ble_gap_adv_start(own_address_type, NULL, BLE_HS_FOREVER, &params, gap_event, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to start advertising: %d", rc);
        return false;
    }
    return true;
}

static void on_sync(void)
{
    int rc = ble_hs_id_infer_auto(0, &own_address_type);
    if (rc == 0) {
        if (advertise()) {
            validate_running_image_after_ble_ready();
        }
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
    ESP_ERROR_CHECK(vibe_ota_service_init("vibe_light_led", ota_status_changed, NULL));
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
