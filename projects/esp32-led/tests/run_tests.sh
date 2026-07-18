#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
IDF_PATH="${IDF_PATH:-/Users/miclle/esp/esp-idf}"
CJSON_DIR="$IDF_PATH/components/json/cJSON"
PROTOCOL_DIR="$REPO_ROOT/projects/esp32-common/vibe_protocol"
BUILD_DIR="$ROOT_DIR/build/host-tests"
BINARY="$BUILD_DIR/vibe_led_model_test"

if [[ ! -f "$CJSON_DIR/cJSON.c" ]]; then
  echo "cJSON source not found. Set IDF_PATH to an ESP-IDF checkout." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

clang \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -I "$ROOT_DIR/main" \
  -I "$PROTOCOL_DIR" \
  -I "$CJSON_DIR" \
  "$ROOT_DIR/tests/vibe_led_model_test.c" \
  "$ROOT_DIR/main/vibe_led_model.c" \
  "$PROTOCOL_DIR/vibe_status.c" \
  "$CJSON_DIR/cJSON.c" \
  -o "$BINARY"

"$BINARY"
