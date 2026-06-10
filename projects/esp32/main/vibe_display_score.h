#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void vibe_display_score_init(void);
int vibe_display_score_value(void);
bool vibe_display_score_update(int score);
void vibe_display_score_flush(void);

#ifdef __cplusplus
}
#endif
