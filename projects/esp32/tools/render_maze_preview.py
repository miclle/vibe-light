#!/usr/bin/env python3
"""Render a host-side PNG preview of the ESP32 Pac-Man maze.

The script intentionally uses only the Python standard library so it can run on
the development machine without extra image packages. Coordinates mirror the
firmware's current 320px-wide maze stage closely enough for visual regression
checks while hardware flashing is unavailable.
"""

from __future__ import annotations

import argparse
import struct
import zlib
from pathlib import Path


SCALE = 2
MAZE_PREVIEW_WIDTH = 320
MAZE_PREVIEW_HEIGHT = 320
FULL_PREVIEW_WIDTH = 320
FULL_PREVIEW_HEIGHT = 820
HEADER_HEIGHT = 82
MAZE_STAGE_Y = 82
TASK_PANEL_X = 18
TASK_PANEL_Y = 430
TASK_PANEL_W = 284
TASK_PANEL_H = 390
TASK_ROW_Y = 492
TASK_ROW_STRIDE = 56
TASK_SWATCH_W = 3
TASK_SWATCH_H = 10

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
PANEL = (0, 50, 60)
MUTED = (130, 230, 255)
BUSY = (0, 180, 255)
WAITING = (255, 220, 0)
ERROR = (255, 60, 60)
MAZE = (0, 70, 255)
DOT = (255, 230, 0)
RED = (255, 0, 0)
GREEN = (0, 220, 0)
PINK = (255, 0, 255)
CYAN = (0, 255, 255)


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


def draw_digit(image: Image, digit: str, x: int, y: int, color: tuple[int, int, int]) -> None:
    glyphs = {
        "0": ("111", "101", "101", "101", "111"),
        "1": ("010", "110", "010", "010", "111"),
    }
    for row_index, row in enumerate(glyphs[digit]):
        for col_index, pixel in enumerate(row):
            if pixel == "1":
                fill_rect(image, x + col_index * 2, y + row_index * 2, 1, 1, color)


def draw_score(image: Image, y_offset: int) -> None:
    draw_digit(image, "1", 8, y_offset + 5, WHITE)
    draw_digit(image, "0", 16, y_offset + 5, WHITE)


LETTER_GLYPHS = {
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
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
    "Y": ("101", "101", "010", "010", "010"),
}


def draw_text(image: Image, x: int, y: int, text: str, scale: int, color: tuple[int, int, int]) -> None:
    cursor = x
    for char in text.upper():
        if char == " ":
            cursor += 4 * scale
            continue
        glyph = LETTER_GLYPHS.get(char)
        if glyph is None:
            cursor += 4 * scale
            continue
        for row_index, row in enumerate(glyph):
            for col_index, pixel in enumerate(row):
                if pixel == "1":
                    fill_rect(image, cursor + col_index * scale, y + row_index * scale, scale, scale, color)
        cursor += 4 * scale


def draw_maze(image: Image, y_offset: int = 0) -> None:
    x = 0
    y = y_offset
    w = 320
    h = 320
    t = 1
    mx = x + 58
    my = y + 48

    fill_rect(image, x, y, w, h, BLACK)
    draw_rects(image, [
        (x, y, w, t, CYAN), (x, y + h - t, w, t, CYAN), (x, y, t, h, CYAN), (x + w - t, y, t, h, CYAN),
        (x + 4, y + 4, w - 8, t, MAZE), (x + 4, y + h - 5, w - 8, t, MAZE),
        (x + 4, y + 4, t, h - 8, MAZE), (x + w - 5, y + 4, t, h - 8, MAZE),
    ])
    draw_text(image, x + 34, y + 12, "SCORE", 1, CYAN)
    draw_text(image, x + 22, y + 28, "001240", 2, WHITE)
    draw_text(image, x + 112, y + 12, "HIGH SCORE", 1, PINK)
    draw_text(image, x + 116, y + 28, "012340", 2, WHITE)
    draw_text(image, x + 204, y + 12, "LEVEL", 1, GREEN)
    draw_text(image, x + 218, y + 28, "02", 2, WHITE)
    draw_text(image, x + 260, y + 12, "LIVES", 1, DOT)
    for life_x in (272, 288, 304):
        fill_circle(image, x + life_x, y + 34, 4, DOT)
        fill_triangle(image, x + life_x + 5, y + 34, x + life_x + 1, y + 31, x + life_x + 1, y + 37, BLACK)
    fill_rect(image, x + 14, y + 58, w - 28, t, MAZE)

    draw_rects(image, [
        (x + 8, y + 72, 46, 34, PINK), (x + 10, y + 74, 42, 30, BLACK),
        (x + 8, y + 208, 46, 68, PINK), (x + 10, y + 210, 42, 64, BLACK),
        (x + 280, y + 84, 32, 40, CYAN), (x + 282, y + 86, 28, 36, BLACK),
        (x + 280, y + 144, 32, 40, CYAN), (x + 282, y + 146, 28, 36, BLACK),
        (x + 280, y + 210, 32, 46, PINK), (x + 282, y + 212, 28, 42, BLACK),
        (mx, my, 216, 216, CYAN), (mx + 2, my + 2, 212, 212, BLACK),
        (mx + 6, my + 6, 204, t, MAZE), (mx + 6, my + 209, 204, t, MAZE),
        (mx + 6, my + 6, t, 204, MAZE), (mx + 209, my + 6, t, 204, MAZE),
        (mx + 20, my + 22, 36, t, CYAN), (mx + 20, my + 52, 36, t, CYAN), (mx + 20, my + 22, t, 30, CYAN), (mx + 56, my + 22, t, 30, CYAN),
        (mx + 76, my + 22, 56, t, CYAN), (mx + 76, my + 52, 56, t, CYAN), (mx + 76, my + 22, t, 30, CYAN), (mx + 132, my + 22, t, 30, CYAN),
        (mx + 160, my + 22, 34, t, CYAN), (mx + 160, my + 52, 34, t, CYAN), (mx + 160, my + 22, t, 30, CYAN), (mx + 194, my + 22, t, 30, CYAN),
        (mx + 30, my + 76, 36, t, CYAN), (mx + 82, my + 74, 54, t, CYAN), (mx + 82, my + 77, 54, t, MAZE), (mx + 152, my + 76, 36, t, CYAN),
        (mx + 56, my + 72, t, 56, CYAN), (mx + 84, my + 92, 28, t, CYAN), (mx + 112, my + 92, t, 30, CYAN),
        (mx + 160, my + 72, t, 56, CYAN), (mx + 132, my + 92, 28, t, CYAN), (mx + 132, my + 92, t, 30, CYAN),
        (mx + 74, my + 120, 68, t, CYAN), (mx + 74, my + 150, 68, t, CYAN), (mx + 74, my + 120, t, 30, CYAN), (mx + 142, my + 120, t, 30, CYAN), (mx + 96, my + 120, 20, t, PINK),
        (mx + 18, my + 158, 70, t, CYAN), (mx + 18, my + 188, 70, t, CYAN), (mx + 88, my + 158, t, 30, CYAN),
        (mx + 128, my + 158, 70, t, CYAN), (mx + 128, my + 188, 70, t, CYAN), (mx + 128, my + 158, t, 30, CYAN),
        (mx + 80, my + 170, 34, t, CYAN), (mx + 120, my + 170, 34, t, CYAN),
        (x + 10, y + 286, 104, 26, PINK), (x + 12, y + 288, 100, 22, BLACK),
        (x + 122, y + 286, 74, 26, PINK), (x + 124, y + 288, 70, 22, BLACK),
        (x + 204, y + 286, 106, 26, CYAN), (x + 206, y + 288, 102, 22, BLACK),
    ])
    draw_text(image, x + 15, y + 84, "PAC", 2, DOT)
    draw_text(image, x + 18, y + 218, "STATUS", 1, CYAN)
    draw_text(image, x + 20, y + 254, "READY", 1, GREEN)
    draw_text(image, x + 287, y + 112, "PAUSE", 1, CYAN)
    draw_text(image, x + 286, y + 226, "SOUND", 1, PINK)
    draw_text(image, x + 292, y + 240, "ON", 1, PINK)
    draw_text(image, x + 34, y + 292, "BONUS", 1, PINK)
    draw_text(image, x + 140, y + 292, "ARCADE", 1, PINK)
    draw_text(image, x + 142, y + 302, "CLASSIC", 1, RED)
    draw_text(image, x + 226, y + 292, "GAME TIP", 1, CYAN)
    for ghost_x, ghost_y, color in ((84, 140, RED), (98, 140, PINK), (112, 140, CYAN), (126, 140, (255, 170, 0)), (108, 74, RED), (48, 132, PINK), (170, 132, CYAN)):
        fill_circle(image, mx + ghost_x, my + ghost_y, 4, color)
    lanes = [
        (78, 62, 144, 62, 11), (176, 62, 252, 62, 11),
        (78, 104, 144, 104, 10), (176, 104, 252, 104, 10),
        (78, 150, 132, 150, 7), (188, 150, 252, 150, 7),
        (78, 238, 144, 238, 11), (176, 238, 252, 238, 11),
        (82, 68, 82, 230, 6), (132, 68, 132, 230, 6),
        (188, 68, 188, 230, 6), (238, 68, 238, 230, 6),
    ]
    index = 0
    for x1, y1, x2, y2, count in lanes:
        divisor = count - 1 if count > 1 else 1
        for i in range(count):
            dot_x = x + x1 + ((x2 - x1) * i) // divisor
            dot_y = y + y1 + ((y2 - y1) * i) // divisor
            radius = 3 if index in (0, 21, 56, 77) else 1
            fill_circle(image, dot_x, dot_y, radius, DOT)
            index += 1
    fill_circle(image, mx + 110, my + 190, 7, DOT)
    fill_triangle(image, mx + 120, my + 190, mx + 110, my + 185, mx + 110, my + 195, BLACK)
    return

    draw_text(image, x + 8, y - 16, "SCORE", 1, CYAN)
    draw_text(image, x + 56, y - 16, "1240", 1, WHITE)
    draw_text(image, x + 218, y - 16, "LIVES", 1, DOT)
    for life_x in (270, 288, 306):
        fill_circle(image, x + life_x, y - 12, 4, DOT)
        fill_triangle(image, x + life_x + 5, y - 12, x + life_x + 1, y - 15, x + life_x + 1, y - 9, BLACK)

    mini_rects = [
        (x, y, w, t, CYAN), (x, y + h - t, w, t, CYAN), (x, y, t, h, CYAN), (x + w - t, y, t, h, CYAN),
        (x + 3, y + 3, w - 6, t, MAZE), (x + 3, y + h - 4, w - 6, t, MAZE),
        (x + 3, y + 3, t, h - 6, MAZE), (x + w - 4, y + 3, t, h - 6, MAZE),
        (x, y + 39, 24, 14, BLACK), (x + w - 24, y + 39, 24, 14, BLACK),
        (x, y + 38, 27, t, CYAN), (x, y + 53, 27, t, CYAN),
        (x + w - 27, y + 38, 27, t, CYAN), (x + w - 27, y + 53, 27, t, CYAN),
        (x + 32, y + 15, 44, t, CYAN), (x + 32, y + 31, 44, t, CYAN),
        (x + 32, y + 15, t, 17, CYAN), (x + 76, y + 15, t, 17, CYAN),
        (x + 96, y + 15, 56, t, CYAN), (x + 96, y + 31, 56, t, CYAN),
        (x + 96, y + 15, t, 17, CYAN), (x + 152, y + 15, t, 17, CYAN),
        (x + 168, y + 15, 56, t, CYAN), (x + 168, y + 31, 56, t, CYAN),
        (x + 168, y + 15, t, 17, CYAN), (x + 224, y + 15, t, 17, CYAN),
        (x + 244, y + 15, 44, t, CYAN), (x + 244, y + 31, 44, t, CYAN),
        (x + 244, y + 15, t, 17, CYAN), (x + 288, y + 15, t, 17, CYAN),
        (x + 58, y + 44, 30, t, CYAN), (x + 58, y + 47, 30, t, MAZE),
        (x + 112, y + 43, 96, t, CYAN), (x + 112, y + 46, 96, t, MAZE),
        (x + 232, y + 44, 30, t, CYAN), (x + 232, y + 47, 30, t, MAZE),
        (x + 84, y + 38, t, 38, CYAN), (x + 96, y + 55, 34, t, CYAN),
        (x + 130, y + 55, t, 18, CYAN), (x + 236, y + 38, t, 38, CYAN),
        (x + 190, y + 55, 34, t, CYAN), (x + 190, y + 55, t, 18, CYAN),
        (x + 132, y + 62, 56, t, CYAN), (x + 132, y + 86, 56, t, CYAN),
        (x + 132, y + 62, t, 24, CYAN), (x + 188, y + 62, t, 24, CYAN),
        (x + 154, y + 62, 12, t, PINK),
        (x + 28, y + 70, 72, t, CYAN), (x + 28, y + 86, 72, t, CYAN), (x + 100, y + 70, t, 17, CYAN),
        (x + 220, y + 70, 72, t, CYAN), (x + 220, y + 86, 72, t, CYAN), (x + 220, y + 70, t, 17, CYAN),
        (x + 118, y + 78, 36, t, CYAN), (x + 166, y + 78, 36, t, CYAN),
    ]
    draw_rects(image, mini_rects)

    lanes = [
        (30, 10, 144, 10, 12), (176, 10, 290, 10, 12),
        (30, 35, 144, 35, 12), (176, 35, 290, 35, 12),
        (30, 58, 96, 58, 8), (224, 58, 290, 58, 8),
        (30, 90, 144, 90, 12), (176, 90, 290, 90, 12),
        (24, 12, 24, 86, 8), (104, 12, 104, 86, 8), (216, 12, 216, 86, 8), (296, 12, 296, 86, 8),
    ]
    for x1, y1, x2, y2, count in lanes:
        divisor = count - 1 if count > 1 else 1
        for i in range(count):
            dot_x = x + x1 + ((x2 - x1) * i) // divisor
            dot_y = y + y1 + ((y2 - y1) * i) // divisor
            fill_circle(image, dot_x, dot_y, 1, DOT)
    for dot_x, dot_y in ((24, 23), (296, 23), (24, 84), (296, 84)):
        fill_circle(image, x + dot_x, y + dot_y, 4, DOT)

    for ghost_x, ghost_y, color in ((146, 75, RED), (158, 75, PINK), (170, 75, CYAN), (182, 75, (255, 170, 0)), (160, 43, RED), (104, 66, PINK), (250, 66, CYAN)):
        fill_circle(image, x + ghost_x, y + ghost_y, 4, color)
    fill_circle(image, x + 188, y + 82, 7, DOT)
    fill_triangle(image, x + 198, y + 82, x + 188, y + 77, x + 188, y + 87, BLACK)
    return

    maze_rects = [
        (x, y, w, t, MAZE),
        (x, y + h - t, w, t, MAZE),
        (x, y, t, h, MAZE),
        (x + w - t, y, t, h, MAZE),
        (x + 2, y + 3, w - 4, t, MAZE),
        (x + 2, y + h - 4, w - 4, t, MAZE),
        (x + 3, y + 2, t, h - 4, MAZE),
        (x + w - 4, y + 2, t, h - 4, MAZE),
        (x, y, 3, 2, BLACK),
        (x + w - 3, y, 3, 2, BLACK),
        (x, y + h - 2, 3, 2, BLACK),
        (x + w - 3, y + h - 2, 3, 2, BLACK),
        (x + 2, y + 1, 3, t, MAZE),
        (x + w - 5, y + 1, 3, t, MAZE),
        (x + 2, y + h - 2, 3, t, MAZE),
        (x + w - 5, y + h - 2, 3, t, MAZE),
        (x, y + 34, t, 12, BLACK),
        (x + w - t, y + 34, t, 12, BLACK),
        (x + 3, y + 34, t, 12, BLACK),
        (x + w - 4, y + 34, t, 12, BLACK),
        (0, y + 33, x + 22, t, MAZE),
        (0, y + 48, x + 22, t, MAZE),
        (x + w - 22, y + 33, MAZE_PREVIEW_WIDTH - (x + w - 22), t, MAZE),
        (x + w - 22, y + 48, MAZE_PREVIEW_WIDTH - (x + w - 22), t, MAZE),
        (x + 26, y + 23, 12, t, MAZE),
        (x + 26, y + 26, 12, t, MAZE),
        (x + 26, y + 23, t, 4, MAZE),
        (x + 38, y + 23, t, 4, MAZE),
        (x + 232, y + 23, 12, t, MAZE),
        (x + 232, y + 26, 12, t, MAZE),
        (x + 232, y + 23, t, 4, MAZE),
        (x + 244, y + 23, t, 4, MAZE),
        (x + 276, y + 23, 18, t, MAZE),
        (x + 276, y + 26, 18, t, MAZE),
        (x + 276, y + 23, t, 4, MAZE),
        (x + 294, y + 23, t, 4, MAZE),
        (x + 33, y + 12, 37, t, MAZE),
        (x + 34, y + 15, 35, t, MAZE),
        (x + 33, y + 12, t, 4, MAZE),
        (x + 70, y + 12, t, 4, MAZE),
        (x + 81, y + 12, 67, t, MAZE),
        (x + 82, y + 15, 65, t, MAZE),
        (x + 81, y + 12, t, 4, MAZE),
        (x + 148, y + 12, t, 4, MAZE),
        (x + 160, y + 12, 33, t, MAZE),
        (x + 161, y + 15, 31, t, MAZE),
        (x + 160, y + 12, t, 4, MAZE),
        (x + 193, y + 12, t, 4, MAZE),
        (x + 223, y + 12, 18, t, MAZE),
        (x + 224, y + 15, 16, t, MAZE),
        (x + 223, y + 12, t, 4, MAZE),
        (x + 241, y + 12, t, 4, MAZE),
        (x + 253, y + 12, 18, t, MAZE),
        (x + 254, y + 15, 16, t, MAZE),
        (x + 253, y + 12, t, 4, MAZE),
        (x + 271, y + 12, t, 4, MAZE),
        (x + 52, y + 30, 25, t, MAZE),
        (x + 52, y + 30, t, 27, MAZE),
        (x + 76, y + 30, t, 11, MAZE),
        (x + 62, y + 41, 15, t, MAZE),
        (x + 76, y + 41, t, 16, MAZE),
        (x + 52, y + 57, 25, t, MAZE),
        (x + 56, y + 34, 17, t, MAZE),
        (x + 56, y + 34, t, 19, MAZE),
        (x + 66, y + 45, 7, t, MAZE),
        (x + 56, y + 53, 17, t, MAZE),
        (x + 81, y + 30, 28, t, RED),
        (x + 81, y + 30, t, 27, RED),
        (x + 108, y + 30, t, 27, RED),
        (x + 81, y + 57, 28, t, RED),
        (x + 85, y + 34, 20, t, RED),
        (x + 85, y + 34, t, 19, RED),
        (x + 104, y + 34, t, 19, RED),
        (x + 85, y + 53, 20, t, RED),
        (x + 126, y + 34, 20, t, DOT),
        (x + 126, y + 34, t, 20, DOT),
        (x + 145, y + 34, t, 20, DOT),
        (x + 126, y + 53, 20, t, DOT),
        (x + 130, y + 38, 12, t, DOT),
        (x + 130, y + 38, t, 12, DOT),
        (x + 141, y + 38, t, 12, DOT),
        (x + 130, y + 50, 12, t, DOT),
        (x + 159, y + 31, 34, t, MAZE),
        (x + 159, y + 31, t, 19, MAZE),
        (x + 191, y + 31, t, 19, MAZE),
        (x + 159, y + 48, 34, t, MAZE),
        (x + 163, y + 35, 26, t, MAZE),
        (x + 163, y + 35, t, 11, MAZE),
        (x + 188, y + 35, t, 11, MAZE),
        (x + 163, y + 46, 26, t, MAZE),
        (x + 203, y + 14, t, 42, GREEN),
        (x + 212, y + 14, t, 42, GREEN),
        (x + 224, y + 30, 28, t, RED),
        (x + 224, y + 30, t, 27, RED),
        (x + 251, y + 30, t, 14, RED),
        (x + 234, y + 41, 18, t, RED),
        (x + 234, y + 52, 18, t, RED),
        (x + 224, y + 57, 28, t, RED),
        (x + 228, y + 34, 20, t, RED),
        (x + 228, y + 34, t, 19, RED),
        (x + 238, y + 42, 10, t, RED),
        (x + 238, y + 50, 10, t, RED),
        (x + 228, y + 53, 20, t, RED),
        (x + 258, y + 33, 28, t, MAZE),
        (x + 258, y + 48, 28, t, MAZE),
        (x + 284, y + 33, t, 16, MAZE),
        (x + 116, y + 53, 32, t, MAZE),
        (x + 170, y + 53, 44, t, MAZE),
        (x + 184, y + 61, t, 12, MAZE),
        (x + 18, y + 76, 88, t, MAZE),
        (x + 18, y + 79, 88, t, MAZE),
        (x + 18, y + 76, t, 4, MAZE),
        (x + 106, y + 76, t, 4, MAZE),
        (x + 126, y + 76, 42, t, MAZE),
        (x + 126, y + 79, 42, t, MAZE),
        (x + 126, y + 76, t, 4, MAZE),
        (x + 168, y + 76, t, 4, MAZE),
        (x + 190, y + 76, 78, t, MAZE),
        (x + 190, y + 79, 78, t, MAZE),
        (x + 190, y + 76, t, 4, MAZE),
        (x + 268, y + 76, t, 4, MAZE),
        (x + 150, y + 89, t, 5, MAZE),
        (x + 151, y + 93, 18, t, MAZE),
        (x + 168, y + 89, t, 5, MAZE),
    ]
    draw_rects(image, maze_rects)

    lanes = [
        (14, 8, 306, 8, 34),
        (14, 88, 138, 88, 16),
        (182, 88, 306, 88, 16),
        (14, 30, 44, 30, 4),
        (14, 46, 44, 46, 4),
        (116, 58, 196, 58, 8),
        (116, 30, 116, 66, 5),
        (196, 30, 196, 66, 5),
        (256, 30, 306, 30, 5),
        (256, 46, 306, 46, 5),
    ]
    index = 0
    for x1, y1, x2, y2, count in lanes:
        divisor = count - 1 if count > 1 else 1
        for i in range(count):
            dot_x = x1 + ((x2 - x1) * i) // divisor
            dot_y = y1 + ((y2 - y1) * i) // divisor
            radius = 3 if index in (0, 33, 34, 65) else 1
            fill_circle(image, dot_x, y + dot_y, radius, DOT)
            index += 1

    for ghost_x, ghost_y, color in ((144, y + 43, PINK), (156, y + 51, CYAN), (124, y + 86, CYAN), (246, y + 86, RED)):
        fill_circle(image, ghost_x, ghost_y, 4, color)

    for life_x in (10, 24):
        fill_circle(image, life_x, y + h + 14, 4, DOT)
        fill_triangle(image, life_x + 5, y + h + 14, life_x + 1, y + h + 11, life_x + 1, y + h + 17, BLACK)
    fill_circle(image, 188, y + 82, 7, DOT)
    fill_triangle(image, 198, y + 82, 188, y + 77, 188, y + 87, BLACK)
    fill_circle(image, x + w - 14, y + h + 16, 2, RED)
    fill_circle(image, x + w - 10, y + h + 16, 2, RED)


def draw_full_screen(image: Image) -> None:
    fill_rect(image, 0, 0, 320, HEADER_HEIGHT, BUSY)
    fill_rect(image, 0, MAZE_STAGE_Y, 320, MAZE_PREVIEW_HEIGHT, BLACK)
    fill_rect(image, TASK_PANEL_X, TASK_PANEL_Y, TASK_PANEL_W, TASK_PANEL_H, PANEL)

    draw_text(image, 24, 22, "VIBE LIGHT", 3, WHITE)
    draw_maze(image, MAZE_STAGE_Y)

    count_y = TASK_PANEL_Y + 26
    draw_status_chip(image, 32, count_y, BUSY, "A1")
    draw_status_chip(image, 126, count_y, WAITING, "W0")
    draw_status_chip(image, 220, count_y, ERROR, "E0")

    tasks = [
        (BUSY, "1", "MANUAL"),
        (WAITING, "2", "BUILD"),
        (ERROR, "3", "TEST"),
        (BUSY, "4", "FLASH"),
        (WAITING, "5", "READY"),
    ]
    for index, (color, badge, title) in enumerate(tasks):
        y = TASK_ROW_Y + index * TASK_ROW_STRIDE
        fill_rect(image, 32, y, TASK_SWATCH_W, TASK_SWATCH_H, color)
        draw_text(image, 44, y, badge, 1, color)
        draw_text(image, 70, y, title, 1, WHITE)


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


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the ESP32 Pac-Man maze preview")
    parser.add_argument("output", nargs="?", default="/tmp/vibe-maze-preview.png", help="Output PNG path")
    parser.add_argument("--full-screen", action="store_true", help="Render the full 320x820 ESP32 screen preview")
    args = parser.parse_args()

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
