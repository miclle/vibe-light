#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="dev"
MINIMUM_DESKTOP_VERSION="dev"
SKIP_ESP32_BUILD=0
PYTHON_RUNTIME=""
REQUIRE_BUNDLED_PYTHON=0

usage() {
  cat <<'EOF'
usage: script/prepare_desktop_firmware_release.sh [options]

Prepares the desktop app firmware flashing resources:
  1. build ESP32 firmware unless skipped
  2. package FirmwareBundle from flasher_args.json
  3. vendor esptool Python packages into FirmwareTools
  4. verify the bundled helper with a narrowed PATH

Options:
  --version VERSION                 Firmware version recorded in manifest.json
  --minimum-desktop-version VERSION Minimum compatible desktop version
  --python-runtime PATH             Copy a standalone Python runtime into FirmwareTools/python
  --require-bundled-python          Fail unless FirmwareTools/python/bin/python3 exists
  --skip-esp32-build                Reuse existing projects/esp32/build outputs
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
fi

projects/esp32/tools/package_firmware_bundle.py \
  --version "$VERSION" \
  --minimum-desktop-version "$MINIMUM_DESKTOP_VERSION"

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

printf 'Prepared desktop firmware release resources for %s (minimum desktop %s).\n' \
  "$VERSION" "$MINIMUM_DESKTOP_VERSION"
