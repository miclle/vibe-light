#include "vibe_cjk_font.h"

#include <stddef.h>

extern const uint8_t _binary_vibe_cjk_font_bin_start[] __asm__("_binary_vibe_cjk_font_bin_start");
extern const uint8_t _binary_vibe_cjk_font_bin_end[] __asm__("_binary_vibe_cjk_font_bin_end");

static uint16_t read_u16(const uint8_t *data)
{
    return (uint16_t)(data[0] | (data[1] << 8));
}

static bool font_header_valid(const uint8_t *start, const uint8_t *end)
{
    size_t size = (size_t)(end - start);
    if (size < 14) {
        return false;
    }
    if (start[0] != 'V' || start[1] != 'C' || start[2] != 'J' || start[3] != 'K') {
        return false;
    }
    return read_u16(start + 4) == 1 &&
           read_u16(start + 6) == VIBE_CJK_FONT_WIDTH &&
           read_u16(start + 8) == VIBE_CJK_FONT_HEIGHT &&
           read_u16(start + 10) == VIBE_CJK_FONT_BYTES_PER_GLYPH;
}

bool vibe_cjk_font_lookup(uint32_t codepoint, const uint8_t **glyph)
{
    const uint8_t *start = _binary_vibe_cjk_font_bin_start;
    const uint8_t *end = _binary_vibe_cjk_font_bin_end;
    if (glyph != NULL) {
        *glyph = NULL;
    }
    if (glyph == NULL || start == NULL || end == NULL || !font_header_valid(start, end) || codepoint > 0xFFFF) {
        return false;
    }

    uint16_t count = read_u16(start + 12);
    const uint8_t *table = start + 14;
    const uint8_t *glyphs = table + (size_t)count * 2;
    if (glyphs + (size_t)count * VIBE_CJK_FONT_BYTES_PER_GLYPH > end) {
        return false;
    }

    int left = 0;
    int right = (int)count - 1;
    while (left <= right) {
        int middle = left + (right - left) / 2;
        uint16_t value = read_u16(table + (size_t)middle * 2);
        if (value == codepoint) {
            *glyph = glyphs + (size_t)middle * VIBE_CJK_FONT_BYTES_PER_GLYPH;
            return true;
        }
        if (value < codepoint) {
            left = middle + 1;
        } else {
            right = middle - 1;
        }
    }
    return false;
}

int vibe_utf8_decode_next(const char **text, uint32_t *codepoint)
{
    if (text == NULL || *text == NULL || **text == '\0' || codepoint == NULL) {
        return 0;
    }

    const unsigned char *p = (const unsigned char *)*text;
    if (p[0] < 0x80) {
        *codepoint = p[0];
        *text += 1;
        return 1;
    }
    if ((p[0] & 0xE0) == 0xC0 && p[1] != '\0' && (p[1] & 0xC0) == 0x80) {
        *codepoint = ((uint32_t)(p[0] & 0x1F) << 6) | (uint32_t)(p[1] & 0x3F);
        *text += 2;
        return 2;
    }
    if ((p[0] & 0xF0) == 0xE0 &&
        p[1] != '\0' &&
        p[2] != '\0' &&
        (p[1] & 0xC0) == 0x80 &&
        (p[2] & 0xC0) == 0x80) {
        *codepoint = ((uint32_t)(p[0] & 0x0F) << 12) |
                     ((uint32_t)(p[1] & 0x3F) << 6) |
                     (uint32_t)(p[2] & 0x3F);
        *text += 3;
        return 3;
    }
    if ((p[0] & 0xF8) == 0xF0 &&
        p[1] != '\0' &&
        p[2] != '\0' &&
        p[3] != '\0' &&
        (p[1] & 0xC0) == 0x80 &&
        (p[2] & 0xC0) == 0x80 &&
        (p[3] & 0xC0) == 0x80) {
        *codepoint = ((uint32_t)(p[0] & 0x07) << 18) |
                     ((uint32_t)(p[1] & 0x3F) << 12) |
                     ((uint32_t)(p[2] & 0x3F) << 6) |
                     (uint32_t)(p[3] & 0x3F);
        *text += 4;
        return 4;
    }

    *codepoint = '?';
    *text += 1;
    return 1;
}
