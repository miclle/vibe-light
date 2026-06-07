idf_component_register(
    SRCS
        "main.c"
        "vibe_ble.c"
        "vibe_display.c"
        "vibe_status.c"
    INCLUDE_DIRS "."
    REQUIRES
        bt
        esp_timer
        json
        nvs_flash
)
