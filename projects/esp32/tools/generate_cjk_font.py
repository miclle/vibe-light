#!/usr/bin/env python3
"""Generate a compact antialiased GB2312 level-1 CJK font for the ESP32 firmware."""

from __future__ import annotations

import argparse
import os
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

MAGIC = b"VCJK"
VERSION = 1
WIDTH = 18
HEIGHT = 18
BYTES_PER_ROW = (WIDTH + 3) // 4
BYTES_PER_GLYPH = BYTES_PER_ROW * HEIGHT
EXTRA_CODEPOINTS = "。，、！？：；（）【】《》“”‘’·—…"

DEFAULT_FONT_PATHS = [
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/Supplemental/Songti.ttc",
    "/Users/miclle/Library/Fonts/SimHei.ttf",
]


def gb2312_display_codepoints() -> list[int]:
    codepoints: set[int] = set()
    for lead in range(0xB0, 0xD8):
        for trail in range(0xA1, 0xFF):
            try:
                text = bytes([lead, trail]).decode("gb2312")
            except UnicodeDecodeError:
                continue
            if len(text) != 1:
                continue
            codepoint = ord(text)
            if 0x4E00 <= codepoint <= 0x9FFF:
                codepoints.add(codepoint)
    codepoints.update(ord(character) for character in EXTRA_CODEPOINTS)
    return sorted(codepoints)


def resolve_font_path(explicit: str | None) -> Path:
    candidates = []
    if explicit:
        candidates.append(explicit)
    env_path = os.environ.get("VIBE_CJK_FONT")
    if env_path:
        candidates.append(env_path)
    candidates.extend(DEFAULT_FONT_PATHS)

    for candidate in candidates:
        path = Path(candidate).expanduser()
        if path.is_file():
            return path
    raise SystemExit(
        "No CJK font found. Set VIBE_CJK_FONT to a Chinese TTF/TTC font path."
    )


def glyph_bitmap(font: ImageFont.FreeTypeFont, codepoint: int) -> bytes:
    char = chr(codepoint)
    image = Image.new("L", (WIDTH, HEIGHT), 0)
    draw = ImageDraw.Draw(image)
    bbox = draw.textbbox((0, 0), char, font=font)
    glyph_width = bbox[2] - bbox[0]
    glyph_height = bbox[3] - bbox[1]
    x = (WIDTH - glyph_width) // 2 - bbox[0]
    y = (HEIGHT - glyph_height) // 2 - bbox[1]
    draw.text((x, y), char, fill=255, font=font)

    packed = bytearray()
    pixels = image.load()
    for row in range(HEIGHT):
        for byte_col in range(0, WIDTH, 4):
            value = 0
            for pixel_index in range(4):
                x = byte_col + pixel_index
                alpha = pixels[x, row] if x < WIDTH else 0
                if alpha >= 192:
                    level = 3
                elif alpha >= 112:
                    level = 2
                elif alpha >= 40:
                    level = 1
                else:
                    level = 0
                value |= level << (6 - pixel_index * 2)
            packed.append(value)
    return bytes(packed)


def write_font(output: Path, font_path: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype(str(font_path), HEIGHT)
    codepoints = gb2312_display_codepoints()
    glyphs = b"".join(glyph_bitmap(font, codepoint) for codepoint in codepoints)

    header = struct.pack(
        "<4sHHHHH",
        MAGIC,
        VERSION,
        WIDTH,
        HEIGHT,
        BYTES_PER_GLYPH,
        len(codepoints),
    )
    table = b"".join(struct.pack("<H", codepoint) for codepoint in codepoints)
    output.write_bytes(header + table + glyphs)
    print(f"generated {len(codepoints)} CJK glyphs from {font_path} -> {output}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", help="Chinese TTF/TTC font path")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    write_font(args.output, resolve_font_path(args.font))


if __name__ == "__main__":
    main()
