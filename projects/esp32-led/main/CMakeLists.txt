idf_component_register(
    SRCS
        "main.c"
        "vibe_ble.c"
        "vibe_led_model.c"
        "vibe_led_output.c"
    INCLUDE_DIRS "."
    REQUIRES
        bt
        driver
        esp_timer
        nvs_flash
        vibe_protocol
)
