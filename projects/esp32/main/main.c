#include "esp_err.h"
#include "esp_log.h"
#include "nvs_flash.h"

#include "vibe_ble.h"
#include "vibe_display.h"
#include "vibe_status.h"

static const char *TAG = "vibe_light";

void app_main(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_LOGI(TAG, "starting Vibe Light firmware");
    vibe_display_init();

    vibe_status_packet_t initial_status;
    vibe_status_default(&initial_status);
    vibe_display_show_status(&initial_status);

    vibe_ble_start();
}
