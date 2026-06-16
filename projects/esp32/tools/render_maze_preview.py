#!/usr/bin/env python3
"""Render a host-side PNG preview of the ESP32 Pac-Man maze."""

from __future__ import annotations

import argparse
import json
import re
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
REFERENCE_MAZE_HEADER = REPO_ROOT / "projects/esp32/main/vibe_reference_maze.h"
DISPLAY_MAZE_DATA_SOURCE = REPO_ROOT / "projects/esp32/main/vibe_display_maze_data.c"
DISPLAY_MODEL_HEADER = REPO_ROOT / "projects/esp32/main/vibe_display_model.h"


def display_model_define(name: str) -> int:
    text = DISPLAY_MODEL_HEADER.read_text()
    match = re.search(rf"#define\s+{name}\s+(\d+)", text)
    if match is None:
        raise ValueError(f"{name} is not defined")
    return int(match.group(1))


SCALE = 2
MAZE_PREVIEW_WIDTH = display_model_define("VIBE_DISPLAY_MAZE_STAGE_W")
MAZE_PREVIEW_HEIGHT = display_model_define("VIBE_DISPLAY_MAZE_STAGE_H")
FULL_PREVIEW_WIDTH = display_model_define("VIBE_DISPLAY_TASK_PANEL_W")
FULL_PREVIEW_HEIGHT = display_model_define("VIBE_DISPLAY_TASK_PANEL_Y") + display_model_define("VIBE_DISPLAY_TASK_PANEL_H")
HEADER_HEIGHT = 82
MAZE_STAGE_Y = display_model_define("VIBE_DISPLAY_MAZE_STAGE_Y")
TASK_PANEL_X = display_model_define("VIBE_DISPLAY_TASK_PANEL_X")
TASK_PANEL_Y = display_model_define("VIBE_DISPLAY_TASK_PANEL_Y")
TASK_PANEL_W = display_model_define("VIBE_DISPLAY_TASK_PANEL_W")
TASK_PANEL_H = display_model_define("VIBE_DISPLAY_TASK_PANEL_H")
TASK_ROW_Y = display_model_define("VIBE_DISPLAY_TASK_ROW_Y")
TASK_ROW_STRIDE = display_model_define("VIBE_DISPLAY_TASK_ROW_STRIDE")
TASK_DETAIL_ROW_STRIDE = display_model_define("VIBE_DISPLAY_TASK_DETAIL_ROW_STRIDE")
TASK_DETAIL_Y_OFFSET = display_model_define("VIBE_DISPLAY_TASK_DETAIL_Y_OFFSET")
TASK_SWATCH_X = display_model_define("VIBE_DISPLAY_TASK_SWATCH_X")
TASK_SWATCH_Y_OFFSET = display_model_define("VIBE_DISPLAY_TASK_SWATCH_Y_OFFSET")
TASK_TEXT_X = display_model_define("VIBE_DISPLAY_TASK_TEXT_X")
TASK_SWATCH_W = display_model_define("VIBE_DISPLAY_TASK_SWATCH_W")
TASK_SWATCH_H = display_model_define("VIBE_DISPLAY_TASK_SWATCH_H")
FOOTER_X = TASK_TEXT_X
CJK_FONT_WIDTH = 18
CJK_FONT_HEIGHT = 18
CJK_FONT_BYTES_PER_ROW = (CJK_FONT_WIDTH + 3) // 4
CJK_FONT_BYTES_PER_GLYPH = CJK_FONT_BYTES_PER_ROW * CJK_FONT_HEIGHT

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
PANEL = (0, 50, 60)
MUTED = (130, 230, 255)
FOOTER = (190, 190, 190)
BUSY = (0, 180, 255)
HEADER_BUSY = (0, 48, 98)
WAITING = (255, 220, 0)
ERROR = (255, 60, 60)
MAZE = (0, 70, 255)
DOT = (255, 230, 0)
RED = (255, 0, 0)
GREEN = (0, 220, 0)
PINK = (255, 0, 255)
CYAN = (0, 255, 255)

RGB565_TO_RGB = {
    0x047F: BUSY,
    0xF81F: PINK,
    0xFFFF: WHITE,
    0x05E0: GREEN,
    0xF800: RED,
    0x07FF: CYAN,
}
CJK_FONT_CACHE: dict[int, bytes] | None = None


MAZE_REFERENCE_MIN_X = display_model_define("VIBE_DISPLAY_MAZE_REFERENCE_MIN_X")
MAZE_REFERENCE_MAX_X = display_model_define("VIBE_DISPLAY_MAZE_REFERENCE_MAX_X")
MAZE_SCORE_CLEAR_Y = display_model_define("VIBE_DISPLAY_MAZE_SCORE_CLEAR_Y")
MAZE_SCORE_CLEAR_H = display_model_define("VIBE_DISPLAY_MAZE_SCORE_CLEAR_H")
MAZE_SCORE_VALUE_Y = display_model_define("VIBE_DISPLAY_MAZE_SCORE_VALUE_Y")
MAZE_SCORE_LEFT_X = display_model_define("VIBE_DISPLAY_MAZE_SCORE_LEFT_X")
MAZE_SCORE_RIGHT_X = display_model_define("VIBE_DISPLAY_MAZE_SCORE_RIGHT_X")
MAZE_HIGH_SCORE_LEFT_X = display_model_define("VIBE_DISPLAY_MAZE_HIGH_SCORE_LEFT_X")
MAZE_HIGH_SCORE_RIGHT_X = display_model_define("VIBE_DISPLAY_MAZE_HIGH_SCORE_RIGHT_X")
MAZE_LEVEL_CLEAR_Y = display_model_define("VIBE_DISPLAY_MAZE_LEVEL_CLEAR_Y")
MAZE_LEVEL_CLEAR_H = display_model_define("VIBE_DISPLAY_MAZE_LEVEL_CLEAR_H")
MAZE_LEVEL_VALUE_Y = display_model_define("VIBE_DISPLAY_MAZE_LEVEL_VALUE_Y")
MAZE_LEVEL_LEFT_X = display_model_define("VIBE_DISPLAY_MAZE_LEVEL_LEFT_X")
MAZE_LEVEL_RIGHT_X = display_model_define("VIBE_DISPLAY_MAZE_LEVEL_RIGHT_X")
MAZE_LEVEL_VALUE_X = display_model_define("VIBE_DISPLAY_MAZE_LEVEL_VALUE_X")
MAZE_GHOST_CENTER_X = display_model_define("VIBE_DISPLAY_MAZE_GHOST_CENTER_X")
MAZE_GHOST_CENTER_Y = display_model_define("VIBE_DISPLAY_MAZE_GHOST_CENTER_Y")
MAZE_GHOST_BLINK_TICKS = display_model_define("VIBE_DISPLAY_MAZE_GHOST_BLINK_TICKS")
USAGE_LINE_Y = display_model_define("VIBE_DISPLAY_USAGE_LINE_Y")
FOOTER_Y = display_model_define("VIBE_DISPLAY_FOOTER_Y")
FOOTER_SCALE = display_model_define("VIBE_DISPLAY_FOOTER_SCALE")
FIRMWARE_VERSION_RIGHT_MARGIN = display_model_define("VIBE_DISPLAY_FIRMWARE_VERSION_RIGHT_MARGIN")
FIRMWARE_VERSION_SCALE = display_model_define("VIBE_DISPLAY_FIRMWARE_VERSION_SCALE")
FOOTER_BOTTOM_CLEAR_Y = FOOTER_Y + 8 * FOOTER_SCALE


def maze_display_x(reference_x: int) -> int:
    span = MAZE_REFERENCE_MAX_X - MAZE_REFERENCE_MIN_X
    scaled = ((reference_x - MAZE_REFERENCE_MIN_X) * (MAZE_PREVIEW_WIDTH - 1)) // span
    return max(0, min(MAZE_PREVIEW_WIDTH - 1, scaled))


def maze_display_run_width(reference_x: int, reference_length: int) -> int:
    if reference_length <= 0:
        return 0
    start = maze_display_x(reference_x)
    end = maze_display_x(reference_x + reference_length - 1)
    return max(1, end - start + 1)


Image = list[list[tuple[int, int, int]]]


def image_size(image: Image) -> tuple[int, int]:
    return len(image[0]), len(image)


def put_pixel(image: Image, x: int, y: int, color: tuple[int, int, int]) -> None:
    width, height = image_size(image)
    if 0 <= x < width and 0 <= y < height:
        image[y][x] = color


def fill_rect(
    image: Image,
    x: int,
    y: int,
    w: int,
    h: int,
    color: tuple[int, int, int],
) -> None:
    width, height = image_size(image)
    for yy in range(max(0, y * SCALE), min(height, (y + h) * SCALE)):
        row = image[yy]
        for xx in range(max(0, x * SCALE), min(width, (x + w) * SCALE)):
            row[xx] = color


def fill_circle(
    image: Image,
    cx: int,
    cy: int,
    radius: int,
    color: tuple[int, int, int],
) -> None:
    for yy in range((cy - radius) * SCALE, (cy + radius + 1) * SCALE):
        for xx in range((cx - radius) * SCALE, (cx + radius + 1) * SCALE):
            dx = xx / SCALE - cx
            dy = yy / SCALE - cy
            if dx * dx + dy * dy <= radius * radius:
                put_pixel(image, xx, yy, color)


def fill_triangle(
    image: Image,
    ax: int,
    ay: int,
    bx: int,
    by: int,
    cx: int,
    cy: int,
    color: tuple[int, int, int],
) -> None:
    min_x = min(ax, bx, cx)
    max_x = max(ax, bx, cx)
    min_y = min(ay, by, cy)
    max_y = max(ay, by, cy)

    def edge(x1: int, y1: int, x2: int, y2: int, px: float, py: float) -> float:
        return (px - x1) * (y2 - y1) - (py - y1) * (x2 - x1)

    for yy in range(min_y * SCALE, (max_y + 1) * SCALE):
        for xx in range(min_x * SCALE, (max_x + 1) * SCALE):
            px = xx / SCALE
            py = yy / SCALE
            w0 = edge(bx, by, cx, cy, px, py)
            w1 = edge(cx, cy, ax, ay, px, py)
            w2 = edge(ax, ay, bx, by, px, py)
            if (w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0):
                put_pixel(image, xx, yy, color)


def draw_rects(image: Image, rects: list[tuple[int, int, int, int, tuple[int, int, int]]]) -> None:
    for rect in rects:
        fill_rect(image, *rect)


def draw_score_and_level(
    image: Image,
    y_offset: int,
    score: int = 530,
    high_score: int = 2300,
    level: int = 2,
) -> None:
    fill_rect(
        image,
        MAZE_SCORE_LEFT_X,
        y_offset + MAZE_SCORE_CLEAR_Y,
        MAZE_SCORE_RIGHT_X - MAZE_SCORE_LEFT_X + 1,
        MAZE_SCORE_CLEAR_H,
        BLACK,
    )
    fill_rect(
        image,
        MAZE_HIGH_SCORE_LEFT_X,
        y_offset + MAZE_SCORE_CLEAR_Y,
        MAZE_HIGH_SCORE_RIGHT_X - MAZE_HIGH_SCORE_LEFT_X + 1,
        MAZE_SCORE_CLEAR_H,
        BLACK,
    )
    fill_rect(
        image,
        MAZE_LEVEL_LEFT_X,
        y_offset + MAZE_LEVEL_CLEAR_Y,
        MAZE_LEVEL_RIGHT_X - MAZE_LEVEL_LEFT_X + 1,
        MAZE_LEVEL_CLEAR_H,
        BLACK,
    )
    draw_text(
        image,
        MAZE_SCORE_LEFT_X,
        y_offset + MAZE_SCORE_VALUE_Y,
        f"{max(score, 0):06d}",
        2,
        PINK,
    )
    draw_text(image, MAZE_LEVEL_LEFT_X, y_offset + MAZE_LEVEL_VALUE_Y, "LEVEL", 2, WHITE)
    draw_text(image, MAZE_LEVEL_VALUE_X, y_offset + MAZE_LEVEL_VALUE_Y, f"{max(1, min(level, 99))}", 2, BUSY)
    draw_text_centered(
        image,
        MAZE_HIGH_SCORE_LEFT_X,
        MAZE_HIGH_SCORE_RIGHT_X,
        y_offset + MAZE_SCORE_VALUE_Y,
        f"{max(score, high_score, 0):06d}",
        2,
        PINK,
    )


LETTER_GLYPHS = {
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"),
    "7": ("111", "001", "010", "010", "010"),
    "8": ("111", "101", "111", "101", "111"),
    "9": ("111", "101", "111", "001", "111"),
    "%": ("101", "001", "010", "100", "101"),
    ":": ("000", "010", "000", "010", "000"),
    ".": ("000", "000", "000", "000", "010"),
    "A": ("010", "101", "111", "101", "101"),
    "B": ("110", "101", "110", "101", "110"),
    "C": ("111", "100", "100", "100", "111"),
    "D": ("110", "101", "101", "101", "110"),
    "E": ("111", "100", "110", "100", "111"),
    "G": ("111", "100", "101", "101", "111"),
    "H": ("101", "101", "111", "101", "101"),
    "I": ("111", "010", "010", "010", "111"),
    "K": ("101", "101", "110", "101", "101"),
    "L": ("100", "100", "100", "100", "111"),
    "M": ("101", "111", "111", "101", "101"),
    "N": ("101", "111", "111", "111", "101"),
    "O": ("111", "101", "101", "101", "111"),
    "P": ("111", "101", "111", "100", "100"),
    "R": ("110", "101", "110", "101", "101"),
    "S": ("111", "100", "111", "001", "111"),
    "T": ("111", "010", "010", "010", "010"),
    "U": ("101", "101", "101", "101", "111"),
    "V": ("101", "101", "101", "101", "010"),
    "W": ("101", "101", "111", "111", "101"),
    "X": ("101", "101", "010", "101", "101"),
    "Y": ("101", "101", "010", "010", "010"),
}


def load_cjk_font() -> dict[int, bytes]:
    global CJK_FONT_CACHE
    if CJK_FONT_CACHE is not None:
        return CJK_FONT_CACHE

    font_bin = Path(tempfile.gettempdir()) / "vibe-cjk-preview-font.bin"
    generator = REPO_ROOT / "projects/esp32/tools/generate_cjk_font.py"
    if not font_bin.exists() or not cjk_font_bin_supported(font_bin):
        subprocess.run([str(generator), str(font_bin)], check=True, stdout=subprocess.DEVNULL)

    data = font_bin.read_bytes()
    magic, version, width, height, bytes_per_glyph, count = struct.unpack_from("<4sHHHHH", data)
    if magic != b"VCJK" or version != 1 or (width, height, bytes_per_glyph) != (
        CJK_FONT_WIDTH,
        CJK_FONT_HEIGHT,
        CJK_FONT_BYTES_PER_GLYPH,
    ):
        raise ValueError("unsupported CJK font asset")

    table_start = 14
    glyph_start = table_start + count * 2
    CJK_FONT_CACHE = {}
    for index in range(count):
        codepoint = struct.unpack_from("<H", data, table_start + index * 2)[0]
        offset = glyph_start + index * bytes_per_glyph
        CJK_FONT_CACHE[codepoint] = data[offset : offset + bytes_per_glyph]
    return CJK_FONT_CACHE


def cjk_font_bin_supported(path: Path) -> bool:
    try:
        data = path.read_bytes()[:14]
        magic, version, width, height, bytes_per_glyph, _ = struct.unpack_from("<4sHHHHH", data)
    except (OSError, struct.error):
        return False
    return magic == b"VCJK" and version == 1 and (width, height, bytes_per_glyph) == (
        CJK_FONT_WIDTH,
        CJK_FONT_HEIGHT,
        CJK_FONT_BYTES_PER_GLYPH,
    )


def draw_cjk_char(image: Image, x: int, y: int, char: str, color: tuple[int, int, int]) -> None:
    glyph = load_cjk_font().get(ord(char))
    if glyph is None:
        fill_rect(image, x, y, CJK_FONT_WIDTH, 1, color)
        fill_rect(image, x, y + CJK_FONT_HEIGHT - 1, CJK_FONT_WIDTH, 1, color)
        fill_rect(image, x, y, 1, CJK_FONT_HEIGHT, color)
        fill_rect(image, x + CJK_FONT_WIDTH - 1, y, 1, CJK_FONT_HEIGHT, color)
        return

    for row in range(CJK_FONT_HEIGHT):
        for col in range(CJK_FONT_WIDTH):
            packed = glyph[row * CJK_FONT_BYTES_PER_ROW + col // 4]
            alpha = (packed >> (6 - (col % 4) * 2)) & 0x03
            if alpha == 0:
                continue
            if alpha >= 3:
                pixel_color = color
            else:
                bg = image[(y + row) * SCALE][(x + col) * SCALE]
                pixel_color = tuple((color[i] * alpha + bg[i] * (3 - alpha) + 1) // 3 for i in range(3))
            fill_rect(image, x + col, y + row, 1, 1, pixel_color)


def draw_text(image: Image, x: int, y: int, text: str, scale: int, color: tuple[int, int, int]) -> None:
    cursor = x
    for char in text:
        if char == " ":
            cursor += 4 * scale
            continue
        if ord(char) >= 0x80:
            draw_cjk_char(image, cursor, y, char, color)
            cursor += CJK_FONT_WIDTH + 1
            continue
        glyph = LETTER_GLYPHS.get(char.upper())
        if glyph is None:
            cursor += 4 * scale
            continue
        for row_index, row in enumerate(glyph):
            for col_index, pixel in enumerate(row):
                if pixel == "1":
                    fill_rect(image, cursor + col_index * scale, y + row_index * scale, scale, scale, color)
        cursor += 4 * scale


def draw_ascii_char_xy(
    image: Image,
    x: int,
    y: int,
    char: str,
    scale_x: int,
    scale_y: int,
    color: tuple[int, int, int],
) -> None:
    if char == " ":
        return
    glyph = LETTER_GLYPHS.get(char.upper())
    if glyph is None:
        return
    for row_index, row in enumerate(glyph):
        for col_index, pixel in enumerate(row):
            if pixel == "1":
                fill_rect(image, x + col_index * scale_x, y + row_index * scale_y, scale_x, scale_y, color)


def text_char_width(char: str, scale: int) -> int:
    return CJK_FONT_WIDTH + 1 if ord(char) >= 0x80 else 4 * scale


def text_width(text: str, scale: int) -> int:
    return sum(text_char_width(char, scale) for char in text.split("\n", 1)[0])


def draw_text_ellipsis(
    image: Image,
    x: int,
    y: int,
    text: str,
    scale: int,
    color: tuple[int, int, int],
    max_width: int,
) -> None:
    cursor = x
    end_x = x + max_width
    ellipsis_width = text_char_width(".", scale) * 3
    for index, char in enumerate(text):
        if char == "\n":
            return
        char_width = text_char_width(char, scale)
        has_more = index < len(text) - 1
        if (has_more and cursor + char_width + ellipsis_width > end_x) or (
            not has_more and cursor + char_width > end_x
        ):
            if cursor + ellipsis_width <= end_x:
                dot_width = text_char_width(".", scale)
                draw_text(image, cursor, y + 2, ".", scale, color)
                draw_text(image, cursor + dot_width, y + 2, ".", scale, color)
                draw_text(image, cursor + dot_width * 2, y + 2, ".", scale, color)
            return
        if ord(char) >= 0x80:
            draw_text(image, cursor, y, char, scale, color)
        else:
            draw_text(image, cursor, y + 2, char, scale, color)
        cursor += char_width


def load_reference_maze_runs() -> list[tuple[int, int, int, tuple[int, int, int]]]:
    text = REFERENCE_MAZE_HEADER.read_text()
    runs = []
    for x, y, length, color in re.findall(r"\{(\d+), (\d+), (\d+), 0x([0-9a-fA-F]+)\}", text):
        rgb = RGB565_TO_RGB.get(int(color, 16), BUSY)
        runs.append((int(x), int(y), int(length), rgb))
    return runs


def load_reference_pellets() -> list[tuple[int, int]]:
    text = DISPLAY_MAZE_DATA_SOURCE.read_text()
    match = re.search(r"vibe_display_reference_pellets\[.*?\] = \{(.*?)\};", text, re.S)
    if match is None:
        return []
    return [(int(x), int(y)) for x, y in re.findall(r"\{(\d+), (\d+)\}", match.group(1))]


def draw_reference_maze(image: Image, y_offset: int) -> None:
    fill_rect(image, 0, y_offset, MAZE_PREVIEW_WIDTH, MAZE_PREVIEW_HEIGHT, BLACK)
    for x, y, length, color in load_reference_maze_runs():
        fill_rect(image, maze_display_x(x), y_offset + y, maze_display_run_width(x, length), 1, color)
    for index, (x, y) in enumerate(load_reference_pellets()):
        radius = 3 if index in (30, 31, 149, 150) else 1
        fill_circle(image, maze_display_x(x), y_offset + y, radius, DOT)
    pacman_x = maze_display_x(143)
    fill_circle(image, pacman_x, y_offset + 214, 7, DOT)
    fill_triangle(image, pacman_x + 10, y_offset + 214, pacman_x, y_offset + 209, pacman_x, y_offset + 219, BLACK)
    draw_center_ghost(image, y_offset, tick=0)
    draw_score_and_level(image, y_offset)
    draw_maze_count_boxes(image, y_offset)


def draw_center_ghost(image: Image, y_offset: int, tick: int) -> None:
    wobble_x = (0, 1, 1, 0, 0, -1, -1, 0)
    wobble_y = (0, 0, -1, -1, 0, 0, 1, 1)
    phase = tick % len(wobble_x)
    x = MAZE_GHOST_CENTER_X + wobble_x[phase]
    y = y_offset + (MAZE_GHOST_CENTER_Y - MAZE_STAGE_Y) + wobble_y[phase]
    eyes_closed = tick % MAZE_GHOST_BLINK_TICKS >= MAZE_GHOST_BLINK_TICKS - 2

    fill_rect(image, MAZE_GHOST_CENTER_X - 24, y_offset + (MAZE_GHOST_CENTER_Y - MAZE_STAGE_Y) - 20, 48, 38, BLACK)
    fill_circle(image, x - 9, y - 7, 8, RED)
    fill_circle(image, x + 9, y - 7, 8, RED)
    fill_rect(image, x - 17, y - 7, 34, 19, RED)
    fill_rect(image, x - 15, y + 10, 8, 5, RED)
    fill_rect(image, x - 4, y + 10, 8, 5, RED)
    fill_rect(image, x + 7, y + 10, 8, 5, RED)

    if eyes_closed:
        fill_rect(image, x - 10, y - 8, 6, 2, WHITE)
        fill_rect(image, x + 4, y - 8, 6, 2, WHITE)
        return

    fill_circle(image, x - 7, y - 8, 4, WHITE)
    fill_circle(image, x + 7, y - 8, 4, WHITE)
    fill_circle(image, x - 6, y - 7, 2, MAZE)
    fill_circle(image, x + 8, y - 7, 2, MAZE)


def draw_maze(image: Image, y_offset: int = 0) -> None:
    draw_reference_maze(image, y_offset)

def draw_full_screen(image: Image) -> None:
    fill_rect(image, 0, 0, 320, HEADER_HEIGHT, HEADER_BUSY)
    fill_rect(image, 0, MAZE_STAGE_Y, 320, MAZE_PREVIEW_HEIGHT, BLACK)
    fill_rect(image, TASK_PANEL_X, TASK_PANEL_Y, TASK_PANEL_W, TASK_PANEL_H, PANEL)

    draw_text_centered(image, 0, FULL_PREVIEW_WIDTH - 1, 22, "VIBE LIGHT", 3, WHITE)
    draw_text(image, 24, USAGE_LINE_Y, "CODEX: 5H 88% 7D 60%", 2, WHITE)
    draw_maze(image, MAZE_STAGE_Y)

    tasks = [
        (BUSY, "VIBE-LIGHT", "打开 .SLIDEO 文件", "RUN 03:12"),
        (WAITING, "DOCS", "等待蓝牙权限", "WAIT 01:08"),
        (ERROR, "FIRMWARE", "构建失败", "2m ago"),
        (BUSY, "FLASH", "写入固件", "RUN 00:42"),
        (WAITING, "APPROVAL", "需要确认", "WAIT 00:18"),
    ]
    y = TASK_ROW_Y
    for index, (color, title, detail, trailing) in enumerate(tasks):
        trailing_x = FULL_PREVIEW_WIDTH - 4 - text_width(trailing, 2) if trailing else FULL_PREVIEW_WIDTH
        title_max_width = trailing_x - TASK_TEXT_X - 8 if trailing else FULL_PREVIEW_WIDTH - TASK_TEXT_X - 12
        fill_rect(image, TASK_SWATCH_X, y + TASK_SWATCH_Y_OFFSET, TASK_SWATCH_W, TASK_SWATCH_H, color)
        draw_text_ellipsis(image, TASK_TEXT_X, y, title, 2, WHITE, title_max_width)
        if trailing:
            draw_text(image, trailing_x, y, trailing, 2, MUTED)
        show_detail = bool(detail)
        if show_detail:
            draw_text_ellipsis(image, TASK_TEXT_X, y + TASK_DETAIL_Y_OFFSET, detail, 2, MUTED, FULL_PREVIEW_WIDTH - TASK_TEXT_X)
            y += TASK_DETAIL_ROW_STRIDE
        else:
            y += TASK_ROW_STRIDE

    draw_text(image, FOOTER_X, FOOTER_Y, "CODEX LIVE", FOOTER_SCALE, FOOTER)
    firmware_version = "FW 2a02678"
    firmware_version_x = FULL_PREVIEW_WIDTH - FIRMWARE_VERSION_RIGHT_MARGIN - text_width(firmware_version, FIRMWARE_VERSION_SCALE)
    draw_text(image, firmware_version_x, FOOTER_Y, firmware_version, FIRMWARE_VERSION_SCALE, FOOTER)
    fill_rect(image, 0, FOOTER_BOTTOM_CLEAR_Y, FULL_PREVIEW_WIDTH, FULL_PREVIEW_HEIGHT - FOOTER_BOTTOM_CLEAR_Y, PANEL)


def draw_maze_count_boxes(image: Image, y_offset: int) -> None:
    y = y_offset + 294
    clear_y = y_offset + 288
    boxes = [
        (maze_display_x(20), maze_display_x(128), "ACTIVE 1", BUSY),
        (maze_display_x(132), maze_display_x(187), "WAIT 0", WAITING),
        (maze_display_x(192), maze_display_x(300), "ERR 0", ERROR),
    ]
    for left, right, label, color in boxes:
        fill_rect(image, left, clear_y, right - left + 1, 22, BLACK)
        draw_text_centered(image, left, right, y, label, 2, color)


def draw_text_centered(
    image: Image,
    left: int,
    right: int,
    y: int,
    text: str,
    scale: int,
    color: tuple[int, int, int],
) -> None:
    width = len(text) * 4 * scale
    x = left + ((right - left + 1) - width) // 2
    draw_text(image, max(left, x), y, text, scale, color)


def draw_status_chip(image: Image, x: int, y: int, color: tuple[int, int, int], label: str) -> None:
    fill_rect(image, x, y, 8, 8, color)
    draw_text(image, x + 14, y - 6, label, 2, MUTED)


def make_image(width: int, height: int) -> Image:
    return [[BLACK for _ in range(width * SCALE)] for _ in range(height * SCALE)]


def write_png(path: Path, image: Image) -> None:
    width, height = image_size(image)
    raw = b"".join(b"\x00" + bytes(channel for pixel in row for channel in pixel) for row in image)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def display_constant_snapshot() -> dict[str, int]:
    return {
        "VIBE_DISPLAY_MAZE_STAGE_W": MAZE_PREVIEW_WIDTH,
        "VIBE_DISPLAY_MAZE_STAGE_H": MAZE_PREVIEW_HEIGHT,
        "VIBE_DISPLAY_MAZE_STAGE_Y": MAZE_STAGE_Y,
        "VIBE_DISPLAY_TASK_PANEL_X": TASK_PANEL_X,
        "VIBE_DISPLAY_TASK_PANEL_Y": TASK_PANEL_Y,
        "VIBE_DISPLAY_TASK_PANEL_W": TASK_PANEL_W,
        "VIBE_DISPLAY_TASK_PANEL_H": TASK_PANEL_H,
        "VIBE_DISPLAY_TASK_ROW_Y": TASK_ROW_Y,
        "VIBE_DISPLAY_TASK_ROW_STRIDE": TASK_ROW_STRIDE,
        "VIBE_DISPLAY_TASK_DETAIL_ROW_STRIDE": TASK_DETAIL_ROW_STRIDE,
        "VIBE_DISPLAY_TASK_DETAIL_Y_OFFSET": TASK_DETAIL_Y_OFFSET,
        "VIBE_DISPLAY_TASK_SWATCH_X": TASK_SWATCH_X,
        "VIBE_DISPLAY_TASK_SWATCH_Y_OFFSET": TASK_SWATCH_Y_OFFSET,
        "VIBE_DISPLAY_TASK_TEXT_X": TASK_TEXT_X,
        "VIBE_DISPLAY_TASK_SWATCH_W": TASK_SWATCH_W,
        "VIBE_DISPLAY_TASK_SWATCH_H": TASK_SWATCH_H,
        "VIBE_DISPLAY_FOOTER_Y": FOOTER_Y,
        "VIBE_DISPLAY_FOOTER_SCALE": FOOTER_SCALE,
        "VIBE_DISPLAY_FIRMWARE_VERSION_RIGHT_MARGIN": FIRMWARE_VERSION_RIGHT_MARGIN,
        "VIBE_DISPLAY_FIRMWARE_VERSION_SCALE": FIRMWARE_VERSION_SCALE,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the ESP32 Pac-Man maze preview")
    parser.add_argument("output", nargs="?", default="/tmp/vibe-maze-preview.png", help="Output PNG path")
    parser.add_argument("--full-screen", action="store_true", help="Render the full 320x820 ESP32 screen preview")
    parser.add_argument("--dump-display-constants", action="store_true", help="Write preview layout constants as JSON")
    args = parser.parse_args()

    if args.dump_display_constants:
        print(json.dumps(display_constant_snapshot(), sort_keys=True))
        return

    if args.full_screen:
        image = make_image(FULL_PREVIEW_WIDTH, FULL_PREVIEW_HEIGHT)
        draw_full_screen(image)
    else:
        image = make_image(MAZE_PREVIEW_WIDTH, MAZE_PREVIEW_HEIGHT)
        draw_maze(image)
    write_png(Path(args.output), image)
    print(args.output)


if __name__ == "__main__":
    main()
