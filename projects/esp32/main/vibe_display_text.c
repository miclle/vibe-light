#include "vibe_display_text.h"

#include <ctype.h>
#include <stdbool.h>
#include <stddef.h>

#include "vibe_cjk_font.h"
#include "vibe_display_draw.h"

static int text_screen_width;

static void draw_char(int x, int y, char c, int scale, uint16_t color);
static void draw_char_xy(int x, int y, char c, int scale_x, int scale_y, uint16_t color);
static void draw_cjk_char(int x, int y, const uint8_t *glyph, uint16_t color);
static void draw_missing_cjk_char(int x, int y, uint16_t color);
static int text_codepoint_width(uint32_t codepoint, int scale);
static uint8_t glyph_row(char c, int row);

void vibe_display_text_bind(int screen_width)
{
    text_screen_width = screen_width;
}

void vibe_display_text_draw(int x, int y, const char *text, int scale, uint16_t color)
{
    if (text == NULL) {
        return;
    }

    int cursor = x;
    const char *p = text;
    while (*p != '\0' && cursor < text_screen_width - 8) {
        uint32_t codepoint = 0;
        vibe_utf8_decode_next(&p, &codepoint);
        if (codepoint == '\n') {
            y += 8 * scale;
            cursor = x;
            continue;
        }
        if (codepoint < 0x80) {
            draw_char(cursor, y, (char)codepoint, scale, color);
            cursor += 6 * scale;
            continue;
        }

        const uint8_t *glyph = NULL;
        if (vibe_cjk_font_lookup(codepoint, &glyph)) {
            draw_cjk_char(cursor, y, glyph, color);
        } else {
            draw_missing_cjk_char(cursor, y, color);
        }
        cursor += VIBE_CJK_FONT_WIDTH + 1;
    }
}

void vibe_display_text_draw_ellipsis(int x, int y, const char *text, int scale, uint16_t color, int max_width)
{
    if (text == NULL || max_width <= 0) {
        return;
    }

    const int end_x = x + max_width;
    const int ellipsis_width = 3 * text_codepoint_width('.', scale);
    int cursor = x;
    const char *p = text;

    while (*p != '\0' && cursor < end_x) {
        const char *next = p;
        uint32_t codepoint = 0;
        vibe_utf8_decode_next(&next, &codepoint);

        if (codepoint == '\n') {
            return;
        }

        int codepoint_width = text_codepoint_width(codepoint, scale);
        bool has_more = *next != '\0';
        if ((has_more && cursor + codepoint_width + ellipsis_width > end_x) ||
            (!has_more && cursor + codepoint_width > end_x)) {
            if (cursor + ellipsis_width <= end_x) {
                draw_char(cursor, y + 2, '.', scale, color);
                draw_char(cursor + text_codepoint_width('.', scale), y + 2, '.', scale, color);
                draw_char(cursor + text_codepoint_width('.', scale) * 2, y + 2, '.', scale, color);
            }
            return;
        }

        if (codepoint < 0x80) {
            draw_char(cursor, y + 2, (char)codepoint, scale, color);
        } else {
            const uint8_t *glyph = NULL;
            if (vibe_cjk_font_lookup(codepoint, &glyph)) {
                draw_cjk_char(cursor, y, glyph, color);
            } else {
                draw_missing_cjk_char(cursor, y, color);
            }
        }

        cursor += codepoint_width;
        p = next;
    }
}

int vibe_display_text_width(const char *text, int scale)
{
    if (text == NULL) {
        return 0;
    }

    int width = 0;
    const char *p = text;
    while (*p != '\0') {
        uint32_t codepoint = 0;
        vibe_utf8_decode_next(&p, &codepoint);
        if (codepoint == '\n') {
            break;
        }
        width += text_codepoint_width(codepoint, scale);
    }
    return width;
}

static int text_codepoint_width(uint32_t codepoint, int scale)
{
    return codepoint < 0x80 ? 6 * scale : VIBE_CJK_FONT_WIDTH + 1;
}

static void draw_char(int x, int y, char c, int scale, uint16_t color)
{
    draw_char_xy(x, y, c, scale, scale, color);
}

static void draw_char_xy(int x, int y, char c, int scale_x, int scale_y, uint16_t color)
{
    c = (char)toupper((unsigned char)c);
    for (int row = 0; row < 7; row++) {
        uint8_t bits = glyph_row(c, row);
        for (int col = 0; col < 5; col++) {
            if (bits & (1 << (4 - col))) {
                vibe_display_draw_fill_rect(x + col * scale_x, y + row * scale_y, scale_x, scale_y, color);
            }
        }
    }
}

static void draw_cjk_char(int x, int y, const uint8_t *glyph, uint16_t color)
{
    if (glyph == NULL) {
        return;
    }

    for (int row = 0; row < VIBE_CJK_FONT_HEIGHT; row++) {
        for (int col = 0; col < VIBE_CJK_FONT_WIDTH; col++) {
            uint8_t packed = glyph[row * VIBE_CJK_FONT_BYTES_PER_ROW + col / 4];
            uint8_t alpha_level = (uint8_t)((packed >> (6 - (col % 4) * 2)) & 0x03);
            vibe_display_draw_blend_pixel(x + col, y + row, color, alpha_level);
        }
    }
}

static void draw_missing_cjk_char(int x, int y, uint16_t color)
{
    vibe_display_draw_fill_rect(x, y, VIBE_CJK_FONT_WIDTH, 1, color);
    vibe_display_draw_fill_rect(x, y + VIBE_CJK_FONT_HEIGHT - 1, VIBE_CJK_FONT_WIDTH, 1, color);
    vibe_display_draw_fill_rect(x, y, 1, VIBE_CJK_FONT_HEIGHT, color);
    vibe_display_draw_fill_rect(x + VIBE_CJK_FONT_WIDTH - 1, y, 1, VIBE_CJK_FONT_HEIGHT, color);
    draw_char(x + 5, y + 4, '?', 1, color);
}

static uint8_t glyph_row(char c, int row)
{
    static const uint8_t digits[10][7] = {
        {0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e},
        {0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e},
        {0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f},
        {0x1e, 0x01, 0x01, 0x0e, 0x01, 0x01, 0x1e},
        {0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02},
        {0x1f, 0x10, 0x1e, 0x01, 0x01, 0x11, 0x0e},
        {0x06, 0x08, 0x10, 0x1e, 0x11, 0x11, 0x0e},
        {0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08},
        {0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e},
        {0x0e, 0x11, 0x11, 0x0f, 0x01, 0x02, 0x0c},
    };
    static const uint8_t letters[26][7] = {
        {0x0e, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11},
        {0x1e, 0x11, 0x11, 0x1e, 0x11, 0x11, 0x1e},
        {0x0f, 0x10, 0x10, 0x10, 0x10, 0x10, 0x0f},
        {0x1e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1e},
        {0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x1f},
        {0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x10},
        {0x0f, 0x10, 0x10, 0x13, 0x11, 0x11, 0x0f},
        {0x11, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11},
        {0x0e, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0e},
        {0x01, 0x01, 0x01, 0x01, 0x11, 0x11, 0x0e},
        {0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11},
        {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1f},
        {0x11, 0x1b, 0x15, 0x15, 0x11, 0x11, 0x11},
        {0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11},
        {0x0e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e},
        {0x1e, 0x11, 0x11, 0x1e, 0x10, 0x10, 0x10},
        {0x0e, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0d},
        {0x1e, 0x11, 0x11, 0x1e, 0x14, 0x12, 0x11},
        {0x0f, 0x10, 0x10, 0x0e, 0x01, 0x01, 0x1e},
        {0x1f, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04},
        {0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e},
        {0x11, 0x11, 0x11, 0x11, 0x11, 0x0a, 0x04},
        {0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0a},
        {0x11, 0x11, 0x0a, 0x04, 0x0a, 0x11, 0x11},
        {0x11, 0x11, 0x0a, 0x04, 0x04, 0x04, 0x04},
        {0x1f, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1f},
    };

    if (row < 0 || row >= 7) {
        return 0;
    }
    if (c >= '0' && c <= '9') {
        return digits[c - '0'][row];
    }
    if (c >= 'A' && c <= 'Z') {
        return letters[c - 'A'][row];
    }

    switch (c) {
    case ' ':
        return 0x00;
    case '-':
        return row == 3 ? 0x1f : 0x00;
    case '_':
        return row == 6 ? 0x1f : 0x00;
    case '.':
        return row == 6 ? 0x04 : 0x00;
    case '%':
        switch (row) {
        case 0:
            return 0x19;
        case 1:
            return 0x1a;
        case 2:
            return 0x02;
        case 3:
            return 0x04;
        case 4:
            return 0x08;
        case 5:
            return 0x0b;
        case 6:
            return 0x13;
        default:
            return 0x00;
        }
    case ':':
        return (row == 2 || row == 4) ? 0x04 : 0x00;
    case '/':
        return (uint8_t)(0x01 << (6 - row < 5 ? 6 - row : 0));
    default:
        return row == 0 || row == 6 ? 0x1f : (row == 3 ? 0x04 : 0x00);
    }
}
