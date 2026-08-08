#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="dev"
MINIMUM_DESKTOP_VERSION="dev"
SKIP_ESP32_BUILD=0
PYTHON_RUNTIME=""
REQUIRE_BUNDLED_PYTHON=0
SIGNED_LED_OTA=0
LED_BUILD_DIR="projects/esp32-led/build"
SIGNING_DEFAULTS=""

cleanup() {
  if [[ -n "$SIGNING_DEFAULTS" && -f "$SIGNING_DEFAULTS" ]]; then
    rm -f "$SIGNING_DEFAULTS"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
usage: script/prepare_desktop_firmware_release.sh [options]

Prepares the desktop app firmware flashing resources:
  1. build LCD and LED ESP32 firmware unless skipped
  2. package both targets under FirmwareBundles
  3. vendor esptool Python packages into FirmwareTools
  4. verify the bundled helper with a narrowed PATH

Options:
  --version VERSION                 Firmware version recorded in manifest.json
  --minimum-desktop-version VERSION Minimum compatible desktop version
  --python-runtime PATH             Copy a standalone Python runtime into FirmwareTools/python
  --require-bundled-python          Fail unless FirmwareTools/python/bin/python3 exists
  --skip-esp32-build                Reuse existing projects/esp32/build outputs
  --signed-led-ota                  Build LED firmware with external OTA signing key
  -h, --help                        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:?missing value for --version}"
      shift 2
      ;;
    --minimum-desktop-version)
      MINIMUM_DESKTOP_VERSION="${2:?missing value for --minimum-desktop-version}"
      shift 2
      ;;
    --python-runtime)
      PYTHON_RUNTIME="${2:?missing value for --python-runtime}"
      shift 2
      ;;
    --require-bundled-python)
      REQUIRE_BUNDLED_PYTHON=1
      shift
      ;;
    --skip-esp32-build)
      SKIP_ESP32_BUILD=1
      shift
      ;;
    --signed-led-ota)
      SIGNED_LED_OTA=1
      LED_BUILD_DIR="projects/esp32-led/build-signed"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

if [[ "$SKIP_ESP32_BUILD" -eq 0 ]]; then
  make esp32-build
  if [[ "$SIGNED_LED_OTA" -eq 1 ]]; then
    SIGNING_DEFAULTS="$(mktemp "${TMPDIR:-/tmp}/vibe-ota-signing.XXXXXX")"
    script/prepare_ota_signing_config.sh "$SIGNING_DEFAULTS" "$LED_BUILD_DIR/sdkconfig"
    IDF_PATH="${IDF_PATH:-/Users/miclle/esp/esp-idf}"
    export IDF_PATH
    (
      source "$IDF_PATH/export.sh" >/tmp/vibe-idf-export.log
      cd projects/esp32-led
      idf.py -B build-signed \
        -D SDKCONFIG=build-signed/sdkconfig \
        -D "SDKCONFIG_DEFAULTS=sdkconfig.defaults;$SIGNING_DEFAULTS" \
        build
    )
  else
    make esp32-led-build
  fi
elif [[ "$SIGNED_LED_OTA" -eq 1 && ! -f "$LED_BUILD_DIR/flasher_args.json" ]]; then
  echo "signed LED build is missing: $LED_BUILD_DIR" >&2
  exit 1
fi

if [[ "$SIGNED_LED_OTA" -eq 1 ]]; then
  for setting in \
    CONFIG_SECURE_SIGNED_APPS_NO_SECURE_BOOT=y \
    CONFIG_SECURE_SIGNED_ON_UPDATE_NO_SECURE_BOOT=y \
    CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES=y \
    CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y; do
    if ! grep -Fqx "$setting" "$LED_BUILD_DIR/sdkconfig"; then
      echo "signed LED build is missing required setting: $setting" >&2
      exit 1
    fi
  done
fi

projects/esp32/tools/package_firmware_bundle.py \
  --build-dir projects/esp32/build \
  --output-dir projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareBundles/display \
  --target-hardware "Waveshare ESP32-S3-LCD-3.16" \
  --version "$VERSION" \
  --minimum-desktop-version "$MINIMUM_DESKTOP_VERSION"

led_package_args=(
  --build-dir "$LED_BUILD_DIR"
  --ota-capable
  --output-dir projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareBundles/led \
  --target-hardware "ESP32-S3-DevKitC-1 N16R8 三色灯" \
  --version "$VERSION" \
  --minimum-desktop-version "$MINIMUM_DESKTOP_VERSION"
)
if [[ "$SIGNED_LED_OTA" -eq 1 ]]; then
  led_package_args+=(--secure-signed)
fi
projects/esp32/tools/package_firmware_bundle.py "${led_package_args[@]}"

tool_args=(--clean)
if [[ -n "$PYTHON_RUNTIME" ]]; then
  tool_args+=(--python-runtime "$PYTHON_RUNTIME")
fi
if [[ "$REQUIRE_BUNDLED_PYTHON" -eq 1 ]]; then
  tool_args+=(--require-python-runtime)
fi
projects/esp32/tools/package_firmware_tools.py "${tool_args[@]}"

HELPER="projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareTools/vibe-light-firmware-flasher"
if [[ ! -x "$HELPER" ]]; then
  echo "firmware flasher helper is missing or not executable: $HELPER" >&2
  exit 1
fi

if [[ "$REQUIRE_BUNDLED_PYTHON" -eq 1 ]]; then
  export VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1
fi

HELP_OUTPUT="$(PATH=/usr/bin:/bin:/usr/sbin:/sbin "$HELPER" --help 2>&1 || true)"
if [[ "$HELP_OUTPUT" != *"esptool.py"* ]]; then
  echo "bundled helper did not report esptool.py under narrowed PATH" >&2
  printf '%s\n' "$HELP_OUTPUT" >&2
  exit 1
fi

if [[ "$REQUIRE_BUNDLED_PYTHON" -eq 1 ]]; then
  PYTHONPATH="projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareTools/python-packages" \
    PYTHONHOME="projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareTools/python" \
    projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareTools/python/bin/python3 - <<'PY'
import esptool
import intelhex
import serial
import yaml
PY
fi

printf 'Prepared desktop firmware release resources for %s (minimum desktop %s).\n' \
  "$VERSION" "$MINIMUM_DESKTOP_VERSION"
