#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_CJK_FONT_WIDTH 18
#define VIBE_CJK_FONT_HEIGHT 18
#define VIBE_CJK_FONT_BYTES_PER_ROW ((VIBE_CJK_FONT_WIDTH + 3) / 4)
#define VIBE_CJK_FONT_BYTES_PER_GLYPH (VIBE_CJK_FONT_BYTES_PER_ROW * VIBE_CJK_FONT_HEIGHT)

bool vibe_cjk_font_lookup(uint32_t codepoint, const uint8_t **glyph);
int vibe_utf8_decode_next(const char **text, uint32_t *codepoint);

#ifdef __cplusplus
}
#endif
