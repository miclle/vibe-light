#!/usr/bin/env bash
set -euo pipefail

OTA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDF_PATH="${IDF_PATH:-/Users/miclle/esp/esp-idf}"
CJSON_DIR="$IDF_PATH/components/json/cJSON"
BUILD_DIR="$OTA_DIR/../../esp32-led/build/host-tests"
BINARY="$BUILD_DIR/vibe_ota_protocol_test"

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
  -I "$OTA_DIR" \
  -I "$CJSON_DIR" \
  "$OTA_DIR/tests/vibe_ota_protocol_test.c" \
  "$OTA_DIR/vibe_ota_protocol.c" \
  "$CJSON_DIR/cJSON.c" \
  -o "$BINARY"

"$BINARY"
