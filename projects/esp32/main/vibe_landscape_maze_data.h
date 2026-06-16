#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_LANDSCAPE_MAZE_BITMAP_W 512
#define VIBE_LANDSCAPE_MAZE_BITMAP_H 200
#define VIBE_LANDSCAPE_MAZE_PALETTE_COUNT 7

typedef struct {
    uint16_t x;
    uint16_t length;
    uint8_t y;
    uint8_t color_index;
} vibe_landscape_maze_run_t;

extern const uint16_t VIBE_LANDSCAPE_MAZE_PALETTE[];
extern const vibe_landscape_maze_run_t VIBE_LANDSCAPE_MAZE_RUNS[];
extern const int VIBE_LANDSCAPE_MAZE_RUN_COUNT;

#ifdef __cplusplus
}
#endif
