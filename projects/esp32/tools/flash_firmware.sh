#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ESP32_DIR="$ROOT_DIR/projects/esp32"
IDF_PATH="${IDF_PATH:-/Users/miclle/esp/esp-idf}"
PORT="${ESP32_PORT:-/dev/cu.usbmodem1101}"
BAUD="${ESP32_BAUD:-460800}"
IDF_SAFE_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
RUN_MONITOR=1

usage() {
  cat >&2 <<'EOF'
usage: projects/esp32/tools/flash_firmware.sh [--flash-only] [port]

Environment:
  IDF_PATH    ESP-IDF checkout path. Defaults to /Users/miclle/esp/esp-idf
  ESP32_PORT  Serial port used when [port] is omitted.
  ESP32_BAUD  Flash baud rate. Defaults to 460800.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --flash-only)
      RUN_MONITOR=0
      shift
      ;;
    *)
      PORT="$1"
      shift
      ;;
  esac
done

if [[ ! -f "$IDF_PATH/export.sh" ]]; then
  echo "ESP-IDF export.sh not found at $IDF_PATH/export.sh" >&2
  exit 1
fi

unset IDF_PYTHON_ENV_PATH
export PATH="$IDF_SAFE_PATH"
source "$IDF_PATH/export.sh" >/tmp/vibe-idf-export.log
cd "$ESP32_DIR"

if lsof "$PORT" >/tmp/vibe-esp32-port-users.log 2>/dev/null; then
  echo "$PORT is busy. Close the existing monitor or stop these processes:" >&2
  cat /tmp/vibe-esp32-port-users.log >&2
  exit 1
fi

if [[ "$RUN_MONITOR" == "1" ]]; then
  idf.py -p "$PORT" -b "$BAUD" flash monitor
else
  idf.py -p "$PORT" -b "$BAUD" flash
fi
