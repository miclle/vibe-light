#include "vibe_led_output.h"

#include "driver/gpio.h"
#include "esp_check.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "vibe_led_output";
static vibe_led_state_t current_state;

static bool states_equal(vibe_led_state_t left, vibe_led_state_t right)
{
    return left.red_on == right.red_on &&
           left.yellow_on == right.yellow_on &&
           left.green_on == right.green_on;
}

void vibe_led_output_init(void)
{
    gpio_config_t config = {
        .pin_bit_mask = (1ULL << VIBE_LED_RED_GPIO) |
                        (1ULL << VIBE_LED_YELLOW_GPIO) |
                        (1ULL << VIBE_LED_GREEN_GPIO),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_ENABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&config));
    vibe_led_output_set((vibe_led_state_t){0});
}

void vibe_led_output_set(vibe_led_state_t state)
{
    ESP_ERROR_CHECK(gpio_set_level(VIBE_LED_RED_GPIO, state.red_on));
    ESP_ERROR_CHECK(gpio_set_level(VIBE_LED_YELLOW_GPIO, state.yellow_on));
    ESP_ERROR_CHECK(gpio_set_level(VIBE_LED_GREEN_GPIO, state.green_on));

    if (!states_equal(state, current_state)) {
        current_state = state;
        ESP_LOGI(
            TAG,
            "indicator red=%d yellow=%d green=%d",
            state.red_on,
            state.yellow_on,
            state.green_on
        );
    }
}

void vibe_led_output_self_test(void)
{
    const vibe_led_state_t sequence[] = {
        {.red_on = true},
        {.yellow_on = true},
        {.green_on = true},
    };
    for (size_t index = 0; index < sizeof(sequence) / sizeof(sequence[0]); index++) {
        vibe_led_output_set(sequence[index]);
        vTaskDelay(pdMS_TO_TICKS(300));
    }
    vibe_led_output_set((vibe_led_state_t){0});
}

vibe_led_state_t vibe_led_output_current(void)
{
    return current_state;
}
