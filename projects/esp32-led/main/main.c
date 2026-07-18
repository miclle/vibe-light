#include "esp_log.h"
#include "nvs_flash.h"

#include "vibe_ble.h"
#include "vibe_led_output.h"

static const char *TAG = "vibe_light_led";

void app_main(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_LOGI(TAG, "starting Vibe Light DevKit LED firmware");
    vibe_led_output_init();
#if CONFIG_VIBE_LED_STARTUP_SELF_TEST
    vibe_led_output_self_test();
#endif
    vibe_ble_start();
}
