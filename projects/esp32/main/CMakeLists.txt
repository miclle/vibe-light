idf_component_register(
    SRCS
        "main.c"
        "lcd/io_additions/esp_io_expander.c"
        "lcd/io_additions/esp_lcd_panel_io_3wire_spi.c"
        "lcd/st7701/esp_lcd_st7701.c"
        "lcd/st7701/esp_lcd_st7701_rgb.c"
        "vibe_ble.c"
        "vibe_cjk_font.c"
        "vibe_display.c"
        "vibe_display_draw.c"
        "vibe_display_model.c"
        "vibe_display_maze_data.c"
        "vibe_display_maze_text.c"
        "vibe_display_score.c"
        "vibe_display_text.c"
        "vibe_health.c"
        "vibe_status.c"
    INCLUDE_DIRS
        "."
        "lcd/io_additions"
        "lcd/st7701"
    REQUIRES
        bt
        driver
        esp_lcd
        esp_timer
        json
        nvs_flash
)

set(VIBE_CJK_FONT_PYTHON_CANDIDATES
    "$ENV{VIBE_CJK_FONT_PYTHON}"
    "$ENV{HOME}/.platformio/penv/bin/python3"
    "$ENV{HOME}/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
    "/opt/homebrew/bin/python3"
    "/usr/local/bin/python3"
    "/usr/bin/python3"
)
set(VIBE_CJK_FONT_PYTHON "")
foreach(candidate ${VIBE_CJK_FONT_PYTHON_CANDIDATES})
    if(NOT VIBE_CJK_FONT_PYTHON AND EXISTS "${candidate}")
        execute_process(
            COMMAND "${candidate}" -c "import PIL"
            RESULT_VARIABLE candidate_result
            OUTPUT_QUIET
            ERROR_QUIET
        )
        if(candidate_result EQUAL 0)
            set(VIBE_CJK_FONT_PYTHON "${candidate}")
        endif()
    endif()
endforeach()
if(NOT VIBE_CJK_FONT_PYTHON)
    message(FATAL_ERROR "python3 with Pillow is required to generate the CJK font asset. Set VIBE_CJK_FONT_PYTHON to a suitable interpreter.")
endif()
set(VIBE_CJK_FONT_BIN "${CMAKE_CURRENT_BINARY_DIR}/vibe_cjk_font.bin")
add_custom_command(
    OUTPUT "${VIBE_CJK_FONT_BIN}"
    COMMAND
        "${VIBE_CJK_FONT_PYTHON}" "${CMAKE_CURRENT_LIST_DIR}/../tools/generate_cjk_font.py"
        "${VIBE_CJK_FONT_BIN}"
    DEPENDS "${CMAKE_CURRENT_LIST_DIR}/../tools/generate_cjk_font.py"
    VERBATIM
)
add_custom_target(vibe_cjk_font_asset DEPENDS "${VIBE_CJK_FONT_BIN}")
add_dependencies(${COMPONENT_LIB} vibe_cjk_font_asset)
target_add_binary_data(${COMPONENT_LIB} "${VIBE_CJK_FONT_BIN}" BINARY)
