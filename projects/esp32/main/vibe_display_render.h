#pragma once

#include <stdint.h>

#include "vibe_display_model.h"

#ifdef __cplusplus
extern "C" {
#endif

#define RGB565_BLACK 0x0000
#define RGB565_WHITE 0xffff
#define RGB565_MUTED 0x9cd3
#define RGB565_FOOTER 0xbdf7
#define RGB565_BLUE 0x047f
#define RGB565_PURPLE 0x8010
#define RGB565_GREEN 0x05e0
#define RGB565_RED 0xf800
#define RGB565_AMBER 0xfd20
#define RGB565_CYAN 0x07ff
#define RGB565_PINK 0xf81f
#define RGB565_PANEL 0x18e3
#define RGB565_HEADER_BUSY 0x018c
#define RGB565_HEADER_WAITING 0x5200
#define RGB565_HEADER_SUCCESS 0x0180
#define RGB565_HEADER_ERROR 0x7000
#define RGB565_HEADER_OFFLINE 0x7a00
#define RGB565_MAZE 0x047f
#define RGB565_DOT 0xffe0

static inline uint16_t vibe_display_color_for_state(vibe_display_state_t state)
{
    switch (state) {
    case VIBE_DISPLAY_BUSY:
        return RGB565_BLUE;
    case VIBE_DISPLAY_WAITING:
        return RGB565_DOT;
    case VIBE_DISPLAY_SUCCESS:
        return RGB565_GREEN;
    case VIBE_DISPLAY_ERROR:
        return RGB565_RED;
    case VIBE_DISPLAY_OFFLINE:
        return RGB565_AMBER;
    case VIBE_DISPLAY_IDLE:
    default:
        return RGB565_WHITE;
    }
}

static inline uint16_t vibe_display_header_color_for_state(vibe_display_state_t state)
{
    switch (state) {
    case VIBE_DISPLAY_BUSY:
        return RGB565_HEADER_BUSY;
    case VIBE_DISPLAY_WAITING:
        return RGB565_HEADER_WAITING;
    case VIBE_DISPLAY_SUCCESS:
        return RGB565_HEADER_SUCCESS;
    case VIBE_DISPLAY_ERROR:
        return RGB565_HEADER_ERROR;
    case VIBE_DISPLAY_OFFLINE:
        return RGB565_HEADER_OFFLINE;
    case VIBE_DISPLAY_IDLE:
    default:
        return RGB565_PANEL;
    }
}

static inline uint16_t vibe_display_color_for_trailing_severity(vibe_display_trailing_severity_t severity)
{
    switch (severity) {
    case VIBE_DISPLAY_TRAILING_WARNING:
        return RGB565_AMBER;
    case VIBE_DISPLAY_TRAILING_CRITICAL:
        return RGB565_RED;
    case VIBE_DISPLAY_TRAILING_NEUTRAL:
    default:
        return RGB565_MUTED;
    }
}

#ifdef __cplusplus
}
#endif
