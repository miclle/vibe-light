#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDF_PATH="${IDF_PATH:-/Users/miclle/esp/esp-idf}"
CJSON_DIR="$IDF_PATH/components/json/cJSON"
BUILD_DIR="$ROOT_DIR/build/host-tests"
BINARY="$BUILD_DIR/vibe_status_parser_test"

for render_mode_file in \
  "$ROOT_DIR/main/vibe_display_portrait.c" \
  "$ROOT_DIR/main/vibe_display_portrait.h" \
  "$ROOT_DIR/main/vibe_display_landscape.c" \
  "$ROOT_DIR/main/vibe_display_landscape.h"; do
  if [[ ! -f "$render_mode_file" ]]; then
    echo "render mode file missing: $render_mode_file" >&2
    exit 1
  fi
done

python3 - "$ROOT_DIR/main/CMakeLists.txt" <<'PY'
import sys
from pathlib import Path

cmake = Path(sys.argv[1]).read_text()
for source in ("vibe_display_portrait.c", "vibe_display_landscape.c"):
    assert f'"{source}"' in cmake, source
PY

find_cjk_font_python() {
  local candidates=(
    "${VIBE_CJK_FONT_PYTHON:-}"
    "$HOME/.platformio/penv/bin/python3"
    "$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
    "/opt/homebrew/bin/python3"
    "/usr/local/bin/python3"
    "/usr/bin/python3"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" -c 'import PIL' >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "python3 with Pillow is required to generate the CJK font test asset. Set VIBE_CJK_FONT_PYTHON to a suitable interpreter." >&2
  return 1
}

if [[ ! -f "$CJSON_DIR/cJSON.c" ]]; then
  echo "cJSON source not found. Set IDF_PATH to an ESP-IDF checkout." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

clang \
  -std=c11 \
  -Wall \
  -Wextra \
  -I "$ROOT_DIR/main" \
  -I "$CJSON_DIR" \
  "$ROOT_DIR/tests/vibe_status_parser_test.c" \
  "$ROOT_DIR/main/vibe_cjk_font.c" \
  "$ROOT_DIR/main/vibe_display_format.c" \
  "$ROOT_DIR/main/vibe_display_model.c" \
  "$ROOT_DIR/main/vibe_display_maze_data.c" \
  "$ROOT_DIR/main/vibe_landscape_maze_data.c" \
  "$ROOT_DIR/main/vibe_health.c" \
  "$ROOT_DIR/main/vibe_status.c" \
  "$CJSON_DIR/cJSON.c" \
  -o "$BINARY"

"$BINARY"

CJK_FONT_PYTHON="$(find_cjk_font_python)"

python3 "$ROOT_DIR/tools/render_maze_preview.py" --dump-display-constants >/tmp/vibe-display-preview-constants.json
python3 "$ROOT_DIR/tools/render_maze_preview.py" --landscape-screen /tmp/vibe-landscape-preview-test.png
python3 - /tmp/vibe-display-preview-constants.json "$ROOT_DIR/main/vibe_display_model.h" <<'PY'
import json
import re
import sys
from pathlib import Path

constants = json.loads(Path(sys.argv[1]).read_text())
header = Path(sys.argv[2]).read_text()

def header_define(name):
    match = re.search(rf"#define\s+{name}\s+(\d+)", header)
    assert match is not None, name
    return int(match.group(1))

for name in (
    "VIBE_DISPLAY_MAZE_STAGE_Y",
    "VIBE_DISPLAY_TASK_PANEL_Y",
    "VIBE_DISPLAY_TASK_ROW_Y",
    "VIBE_DISPLAY_TASK_DETAIL_ROW_STRIDE",
    "VIBE_DISPLAY_TASK_TEXT_X",
    "VIBE_DISPLAY_FOOTER_Y",
    "VIBE_DISPLAY_FIRMWARE_VERSION_RIGHT_MARGIN",
):
    assert constants[name] == header_define(name), name
PY

"$CJK_FONT_PYTHON" - /tmp/vibe-landscape-preview-test.png "$ROOT_DIR/../../docs/Pac-Man-landscape.png" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

preview = Image.open(Path(sys.argv[1])).convert("RGB")
reference = Image.open(Path(sys.argv[2]).resolve()).convert("RGB")
reference = reference.resize(preview.size, Image.Resampling.BILINEAR)

assert preview.size == (1640, 640), preview.size
mean_diff = sum(ImageStat.Stat(ImageChops.difference(preview, reference)).mean) / 3
assert mean_diff < 22, mean_diff
PY

FONT_BIN="$BUILD_DIR/vibe_cjk_font.bin"
"$CJK_FONT_PYTHON" "$ROOT_DIR/tools/generate_cjk_font.py" "$FONT_BIN" >/tmp/vibe-cjk-font-test.log
"$CJK_FONT_PYTHON" - "$FONT_BIN" <<'PY'
import struct
import sys

data = open(sys.argv[1], "rb").read()
magic, version, width, height, bytes_per_glyph, count = struct.unpack_from("<4sHHHHH", data)
assert magic == b"VCJK"
assert version == 1
assert (width, height, bytes_per_glyph) == (18, 18, 90)
table_start = 14
table = [
    struct.unpack_from("<H", data, table_start + index * 2)[0]
    for index in range(count)
]
assert ord("你") in table
assert ord("显") in table
assert ord("。") in table
assert ord("？") in table
assert len(data) == 14 + count * 2 + count * bytes_per_glyph
PY
