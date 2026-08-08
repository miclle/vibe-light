#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBJECT_FILE="${1:-$ROOT_DIR/build/esp-idf/main/CMakeFiles/__idf_main.dir/vibe_ble.c.obj}"
OBJDUMP="${OBJDUMP:-xtensa-esp32s3-elf-objdump}"
NM="${NM:-xtensa-esp32s3-elf-nm}"
SDKCONFIG_FILE="${VIBE_LED_SDKCONFIG:-$ROOT_DIR/sdkconfig}"
OTA_ARCHIVE="${VIBE_OTA_ARCHIVE:-$ROOT_DIR/build/esp-idf/vibe_ota/libvibe_ota.a}"
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

if [[ ! -f "$OTA_ARCHIVE" ]]; then
  echo "missing OTA component archive: $OTA_ARCHIVE; run make esp32-led-build first" >&2
  exit 2
fi

if "$NM" -u "$OTA_ARCHIVE" | grep -Eq 'xQueue(CreateMutex|SemaphoreTake)$'; then
  echo "OTA component references a blocking FreeRTOS mutex; BLE/GAP callback paths must use non-blocking state access" >&2
  exit 1
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
ota_control_frame="$(frame_size handle_ota_control_write)"
ota_data_frame="$(frame_size handle_ota_data_write)"
ota_status_frame="$(frame_size handle_ota_status_read)"
maximum_ota_frame="$ota_control_frame"
for candidate in "$ota_data_frame" "$ota_status_frame"; do
  if (( candidate > maximum_ota_frame )); then
    maximum_ota_frame="$candidate"
  fi
done

if (( combined_frame > maximum_combined )); then
  echo "LED BLE nested stack frames use ${combined_frame} bytes (${write_frame} + ${apply_frame}); limit is ${maximum_combined} bytes to preserve ${MINIMUM_HEADROOM} bytes of NimBLE headroom" >&2
  exit 1
fi

if (( maximum_ota_frame > maximum_combined )); then
  echo "LED OTA BLE callback uses ${maximum_ota_frame} bytes; limit is ${maximum_combined} bytes to preserve ${MINIMUM_HEADROOM} bytes of NimBLE headroom" >&2
  exit 1
fi

printf 'LED BLE nested stack frames: %d bytes (%d + %d), %d bytes headroom reserved\n' \
  "$combined_frame" "$write_frame" "$apply_frame" "$MINIMUM_HEADROOM"
printf 'LED OTA BLE callback frames: control=%d data=%d status=%d bytes\n' \
  "$ota_control_frame" "$ota_data_frame" "$ota_status_frame"
