idf_component_register(
    SRCS
        "vibe_health.c"
        "vibe_status.c"
    INCLUDE_DIRS "."
    REQUIRES json
)
