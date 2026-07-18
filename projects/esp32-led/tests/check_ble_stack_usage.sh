#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBJECT_FILE="${1:-$ROOT_DIR/build/esp-idf/main/CMakeFiles/__idf_main.dir/vibe_ble.c.obj}"
OBJDUMP="${OBJDUMP:-xtensa-esp32s3-elf-objdump}"
SDKCONFIG_FILE="${VIBE_LED_SDKCONFIG:-$ROOT_DIR/sdkconfig}"
REQUIRED_HOST_STACK_SIZE="${VIBE_NIMBLE_REQUIRED_HOST_STACK_SIZE:-8192}"
MINIMUM_HEADROOM="${VIBE_NIMBLE_STACK_HEADROOM:-1024}"

if [[ ! -f "$OBJECT_FILE" ]]; then
  echo "missing LED BLE object: $OBJECT_FILE; run make esp32-led-build first" >&2
  exit 2
fi

if [[ ! -f "$SDKCONFIG_FILE" ]]; then
  echo "missing LED sdkconfig: $SDKCONFIG_FILE; run make esp32-led-build first" >&2
  exit 2
fi

configured_host_stack="$(awk -F= '$1 == "CONFIG_BT_NIMBLE_HOST_TASK_STACK_SIZE" { print $2 }' "$SDKCONFIG_FILE")"
if [[ ! "$configured_host_stack" =~ ^[0-9]+$ ]]; then
  echo "could not read CONFIG_BT_NIMBLE_HOST_TASK_STACK_SIZE from $SDKCONFIG_FILE" >&2
  exit 2
fi

if (( configured_host_stack < REQUIRED_HOST_STACK_SIZE )); then
  echo "LED NimBLE host stack is ${configured_host_stack} bytes; at least ${REQUIRED_HOST_STACK_SIZE} bytes are required for status parsing in the GATT callback" >&2
  exit 1
fi

HOST_STACK_SIZE="${VIBE_NIMBLE_HOST_STACK_SIZE:-$configured_host_stack}"

frame_size() {
  local symbol="$1"
  local value
  value="$($OBJDUMP -d "$OBJECT_FILE" | awk -v target="<$symbol>:" '
    index($0, target) { found = 1; next }
    found && !printed && /entry/ { print $NF; printed = 1 }
  ')"
  if [[ -z "$value" ]]; then
    echo "could not read stack frame for $symbol from $OBJECT_FILE" >&2
    exit 2
  fi
  printf '%d' "$((value))"
}

write_frame="$(frame_size handle_status_write)"
apply_frame="$(frame_size apply_current_status)"
combined_frame=$((write_frame + apply_frame))
maximum_combined=$((HOST_STACK_SIZE - MINIMUM_HEADROOM))

if (( combined_frame > maximum_combined )); then
  echo "LED BLE nested stack frames use ${combined_frame} bytes (${write_frame} + ${apply_frame}); limit is ${maximum_combined} bytes to preserve ${MINIMUM_HEADROOM} bytes of NimBLE headroom" >&2
  exit 1
fi

printf 'LED BLE nested stack frames: %d bytes (%d + %d), %d bytes headroom reserved\n' \
  "$combined_frame" "$write_frame" "$apply_frame" "$MINIMUM_HEADROOM"
