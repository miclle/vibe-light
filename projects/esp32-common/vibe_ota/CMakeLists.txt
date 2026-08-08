idf_component_register(
    SRCS
        "vibe_ota_protocol.c"
        "vibe_ota_service.c"
    INCLUDE_DIRS "."
    REQUIRES
        app_update
        esp_timer
        json
        mbedtls
)
