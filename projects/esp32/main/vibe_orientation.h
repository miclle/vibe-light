#pragma once

#include "vibe_display_model.h"

#ifdef __cplusplus
extern "C" {
#endif

void vibe_orientation_init(void);
vibe_display_orientation_t vibe_orientation_current(void);

#ifdef __cplusplus
}
#endif
