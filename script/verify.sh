#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---full}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDF_PATH="${IDF_PATH:-/Users/miclle/esp/esp-idf}"
IDF_SAFE_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

usage() {
  echo "usage: $0 [--full|--quick]" >&2
  exit 2
}

case "$MODE" in
  --full|full)
    RUN_ESP32_BUILD=1
    ;;
  --quick|quick)
    RUN_ESP32_BUILD=0
    ;;
  *)
    usage
    ;;
esac

run_step() {
  local title="$1"
  shift
  printf '\n==> %s\n' "$title"
  "$@"
}

run_step "Swift tests" swift test --package-path "$ROOT_DIR/projects/macos/desktop"
run_step "Desktop update release tests" "$ROOT_DIR/script/test_desktop_update_release.sh"
run_step "ESP32 status parser tests" "$ROOT_DIR/projects/esp32/tests/run_status_parser_tests.sh"
run_step "ESP32 display previews" "$ROOT_DIR/projects/esp32/tools/render_maze_preview.py" /tmp/vibe-maze-preview.png
run_step "ESP32 full-screen preview" "$ROOT_DIR/projects/esp32/tools/render_maze_preview.py" --full-screen /tmp/vibe-screen-preview.png

if [[ "$RUN_ESP32_BUILD" == "1" ]]; then
  if [[ ! -f "$IDF_PATH/export.sh" ]]; then
    echo "ESP-IDF export.sh not found. Set IDF_PATH to an ESP-IDF checkout." >&2
    exit 1
  fi

  run_step "ESP32 firmware build" zsh -lc "export PATH=\"$IDF_SAFE_PATH\" && source \"$IDF_PATH/export.sh\" >/tmp/vibe-idf-export.log && cd \"$ROOT_DIR/projects/esp32\" && idf.py build"
fi

run_step "Git whitespace check" git -C "$ROOT_DIR" diff --check

printf '\nAll checks passed.\n'
