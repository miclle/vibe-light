#pragma once

#include <stdint.h>

#include "vibe_display_model.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int16_t x;
    int16_t y;
} vibe_display_maze_point_t;

extern const vibe_display_maze_point_t vibe_display_reference_pellets[VIBE_DISPLAY_MAZE_PELLET_COUNT];
extern const uint16_t vibe_display_reference_path[VIBE_DISPLAY_ANIMATION_PATH_STEPS];

#ifdef __cplusplus
}
#endif
