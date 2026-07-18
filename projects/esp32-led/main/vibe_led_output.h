#pragma once

#include "vibe_led_model.h"

#ifdef CONFIG_VIBE_LED_RED_GPIO
#define VIBE_LED_RED_GPIO CONFIG_VIBE_LED_RED_GPIO
#else
#define VIBE_LED_RED_GPIO 4
#endif

#ifdef CONFIG_VIBE_LED_YELLOW_GPIO
#define VIBE_LED_YELLOW_GPIO CONFIG_VIBE_LED_YELLOW_GPIO
#else
#define VIBE_LED_YELLOW_GPIO 5
#endif

#ifdef CONFIG_VIBE_LED_GREEN_GPIO
#define VIBE_LED_GREEN_GPIO CONFIG_VIBE_LED_GREEN_GPIO
#else
#define VIBE_LED_GREEN_GPIO 6
#endif

#ifdef __cplusplus
extern "C" {
#endif

void vibe_led_output_init(void);
void vibe_led_output_set(vibe_led_state_t state);
void vibe_led_output_self_test(void);
vibe_led_state_t vibe_led_output_current(void);

#ifdef __cplusplus
}
#endif
