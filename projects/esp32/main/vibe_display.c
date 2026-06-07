#include "vibe_display.h"

#include "esp_log.h"

static const char *TAG = "vibe_display";

void vibe_display_init(void)
{
    ESP_LOGI(TAG, "display placeholder initialized");
    ESP_LOGI(TAG, "next step: wire Waveshare LCD/LVGL init from the official ESP32-S3-LCD-3.16 example");
}

void vibe_display_show_status(const vibe_status_packet_t *packet)
{
    if (packet == NULL) {
        return;
    }

    ESP_LOGI(
        TAG,
        "Vibe Light | source=%s state=%s detail=%s ts=%lld",
        packet->source,
        vibe_display_state_to_string(packet->state),
        packet->detail,
        (long long)packet->timestamp_ms
    );
}

void vibe_display_show_error(const char *message)
{
    ESP_LOGW(TAG, "display error: %s", message == NULL ? "unknown error" : message);
}
