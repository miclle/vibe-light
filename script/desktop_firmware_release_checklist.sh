#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
MINIMUM_DESKTOP_VERSION="dev"
PYTHON_RUNTIME=""
REQUIRE_BUNDLED_PYTHON=0
SKIP_ESP32_BUILD=0
SKIP_PREPARE=0
SKIP_PACKAGE=0
NOTARIZE=0
SIGNING_IDENTITY_VALUE="${SIGNING_IDENTITY:-}"
NOTARYTOOL_PROFILE_VALUE="${NOTARYTOOL_PROFILE:-}"
APPLE_API_KEY_VALUE="${APPLE_API_KEY:-}"
APPLE_API_KEY_PATH_VALUE="${APPLE_API_KEY_PATH:-}"
APPLE_API_KEY_ID_VALUE="${APPLE_API_KEY_ID:-}"
APPLE_API_ISSUER_VALUE="${APPLE_API_ISSUER:-}"
NOTARYTOOL_TIMEOUT_VALUE="${NOTARYTOOL_TIMEOUT:-}"
CHIP_PORT="${ESP32_PORT:-}"
CHIP_BAUD="${ESP32_BAUD:-460800}"

usage() {
  cat <<'EOF'
usage: script/desktop_firmware_release_checklist.sh [options]

Runs the desktop firmware release checklist and writes a markdown report under
dist/release/. By default it prepares firmware resources, packages/signs the
desktop app, and optionally runs a non-destructive chip read when --chip-port is
provided.

Options:
  --version VERSION                 Firmware/archive version. Defaults to current git short SHA.
  --minimum-desktop-version VERSION Minimum compatible desktop version. Defaults to dev.
  --python-runtime PATH             Copy a standalone Python runtime into FirmwareTools/python.
  --require-bundled-python          Fail unless bundled Python runtime is present.
  --skip-esp32-build                Reuse existing projects/esp32/build outputs.
  --skip-prepare                    Skip script/prepare_desktop_firmware_release.sh.
  --skip-package                    Skip script/package_desktop_release.sh.
  --identity VALUE                  Developer ID Application identity.
  --notarize                        Submit, wait, staple, and validate notarization.
  --notarytool-profile VALUE        Keychain profile for xcrun notarytool.
  --apple-api-key VALUE             .p8 key content, or path to a .p8 file.
  --apple-api-key-path VALUE        Path to a .p8 file.
  --apple-api-key-id VALUE          App Store Connect API Key ID.
  --apple-api-issuer VALUE          App Store Connect API Issuer ID.
  --notarytool-timeout VALUE        Timeout passed to notarytool --wait.
  --chip-port PATH                  Run helper chip_id against this serial port after packaging.
  --chip-baud BAUD                  Baud for chip_id. Defaults to ESP32_BAUD or 460800.
  -h, --help                        Show this help.
EOF
}

quote_command() {
  printf '%q ' "$@"
}

run_logged() {
  local title="$1"
  local log_url="$2"
  shift 2

  printf '\n==> %s\n' "$title"
  printf 'log: %s\n' "$log_url"
  mkdir -p "$(dirname "$log_url")"
  {
    printf '$ '
    quote_command "$@"
    printf '\n'
    "$@"
  } 2>&1 | tee "$log_url"
}

append_report() {
  printf '%s\n' "$@" >>"$REPORT_URL"
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
    --skip-prepare)
      SKIP_PREPARE=1
      shift
      ;;
    --skip-package)
      SKIP_PACKAGE=1
      shift
      ;;
    --identity)
      SIGNING_IDENTITY_VALUE="${2:?missing value for --identity}"
      shift 2
      ;;
    --notarize)
      NOTARIZE=1
      shift
      ;;
    --notarytool-profile)
      NOTARYTOOL_PROFILE_VALUE="${2:?missing value for --notarytool-profile}"
      shift 2
      ;;
    --apple-api-key)
      APPLE_API_KEY_VALUE="${2:?missing value for --apple-api-key}"
      shift 2
      ;;
    --apple-api-key-path)
      APPLE_API_KEY_PATH_VALUE="${2:?missing value for --apple-api-key-path}"
      shift 2
      ;;
    --apple-api-key-id)
      APPLE_API_KEY_ID_VALUE="${2:?missing value for --apple-api-key-id}"
      shift 2
      ;;
    --apple-api-issuer)
      APPLE_API_ISSUER_VALUE="${2:?missing value for --apple-api-issuer}"
      shift 2
      ;;
    --notarytool-timeout)
      NOTARYTOOL_TIMEOUT_VALUE="${2:?missing value for --notarytool-timeout}"
      shift 2
      ;;
    --chip-port)
      CHIP_PORT="${2:?missing value for --chip-port}"
      shift 2
      ;;
    --chip-baud)
      CHIP_BAUD="${2:?missing value for --chip-baud}"
      shift 2
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

RELEASE_DIR="$ROOT_DIR/dist/release"
LOG_DIR="$RELEASE_DIR/logs"
REPORT_URL="$RELEASE_DIR/desktop-firmware-release-$VERSION.md"
mkdir -p "$LOG_DIR"
rm -f "$REPORT_URL"

GIT_COMMIT="$(git rev-parse HEAD)"
GIT_STATUS="$(git status --short)"
STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

append_report "# Desktop Firmware Release Checklist"
append_report ""
append_report "- Started: \`$STARTED_AT\`"
append_report "- Git commit: \`$GIT_COMMIT\`"
append_report "- Firmware version: \`$VERSION\`"
append_report "- Minimum desktop version: \`$MINIMUM_DESKTOP_VERSION\`"
append_report "- Python runtime: \`${PYTHON_RUNTIME:-not provided}\`"
append_report "- Require bundled Python: \`$REQUIRE_BUNDLED_PYTHON\`"
append_report "- Signing identity: \`${SIGNING_IDENTITY_VALUE:-not provided}\`"
append_report "- Notarize: \`$NOTARIZE\`"
append_report "- Chip port: \`${CHIP_PORT:-not provided}\`"
append_report "- Chip baud: \`$CHIP_BAUD\`"
append_report ""

if [[ -n "$GIT_STATUS" ]]; then
  append_report "## Working Tree"
  append_report ""
  append_report '```text'
  append_report "$GIT_STATUS"
  append_report '```'
  append_report ""
fi

if [[ "$SKIP_PREPARE" -eq 0 ]]; then
  prepare_args=(
    "$ROOT_DIR/script/prepare_desktop_firmware_release.sh"
    --version "$VERSION"
    --minimum-desktop-version "$MINIMUM_DESKTOP_VERSION"
  )
  if [[ -n "$PYTHON_RUNTIME" ]]; then
    prepare_args+=(--python-runtime "$PYTHON_RUNTIME")
  fi
  if [[ "$REQUIRE_BUNDLED_PYTHON" -eq 1 ]]; then
    prepare_args+=(--require-bundled-python)
  fi
  if [[ "$SKIP_ESP32_BUILD" -eq 1 ]]; then
    prepare_args+=(--skip-esp32-build)
  fi

  prepare_log="$LOG_DIR/prepare-firmware-$VERSION.log"
  run_logged "Prepare firmware resources" "$prepare_log" "${prepare_args[@]}"
  append_report "## Firmware Resources"
  append_report ""
  append_report "- Status: passed"
  append_report "- Log: \`${prepare_log#$ROOT_DIR/}\`"
  append_report ""
else
  append_report "## Firmware Resources"
  append_report ""
  append_report "- Status: skipped"
  append_report ""
fi

if [[ "$SKIP_PACKAGE" -eq 0 ]]; then
  package_args=("$ROOT_DIR/script/package_desktop_release.sh" --version "$VERSION")
  if [[ -n "$SIGNING_IDENTITY_VALUE" ]]; then
    package_args+=(--identity "$SIGNING_IDENTITY_VALUE")
  fi
  if [[ "$NOTARIZE" -eq 1 ]]; then
    package_args+=(--notarize)
  fi
  if [[ -n "$NOTARYTOOL_PROFILE_VALUE" ]]; then
    package_args+=(--notarytool-profile "$NOTARYTOOL_PROFILE_VALUE")
  fi
  if [[ -n "$APPLE_API_KEY_VALUE" ]]; then
    package_args+=(--apple-api-key "$APPLE_API_KEY_VALUE")
  fi
  if [[ -n "$APPLE_API_KEY_PATH_VALUE" ]]; then
    package_args+=(--apple-api-key-path "$APPLE_API_KEY_PATH_VALUE")
  fi
  if [[ -n "$APPLE_API_KEY_ID_VALUE" ]]; then
    package_args+=(--apple-api-key-id "$APPLE_API_KEY_ID_VALUE")
  fi
  if [[ -n "$APPLE_API_ISSUER_VALUE" ]]; then
    package_args+=(--apple-api-issuer "$APPLE_API_ISSUER_VALUE")
  fi
  if [[ -n "$NOTARYTOOL_TIMEOUT_VALUE" ]]; then
    package_args+=(--notarytool-timeout "$NOTARYTOOL_TIMEOUT_VALUE")
  fi

  package_log="$LOG_DIR/package-desktop-$VERSION.log"
  run_logged "Package desktop app" "$package_log" "${package_args[@]}"
  append_report "## Desktop App"
  append_report ""
  append_report "- Status: passed"
  append_report "- Log: \`${package_log#$ROOT_DIR/}\`"
  append_report "- App bundle: \`dist/VibeLightApp.app\`"
  append_report ""
else
  append_report "## Desktop App"
  append_report ""
  append_report "- Status: skipped"
  append_report ""
fi

FIRMWARE_TOOLS_URL="projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareTools"
NOTICE_URL="$FIRMWARE_TOOLS_URL/THIRD_PARTY_NOTICES.md"
OPEN_SOURCE_NOTICE_URL="$FIRMWARE_TOOLS_URL/OPEN_SOURCE_NOTICES.md"
SOURCE_OFFER_URL="$FIRMWARE_TOOLS_URL/SOURCE_OFFER.md"
append_report "## Third-Party Notices"
append_report ""
if [[ -f "$NOTICE_URL" ]]; then
  if ! grep -q '^## esptool ' "$NOTICE_URL"; then
    echo "third-party notices are missing esptool metadata: $NOTICE_URL" >&2
    exit 1
  fi
  if [[ "$REQUIRE_BUNDLED_PYTHON" -eq 1 ]] && ! grep -q '^## python-portable ' "$NOTICE_URL"; then
    echo "third-party notices are missing bundled Python runtime metadata: $NOTICE_URL" >&2
    exit 1
  fi
  if [[ ! -f "$OPEN_SOURCE_NOTICE_URL" ]]; then
    echo "open source notices are missing: $OPEN_SOURCE_NOTICE_URL" >&2
    exit 1
  fi
  if ! grep -q '^## esptool$' "$OPEN_SOURCE_NOTICE_URL" || ! grep -q 'GPLv2+' "$OPEN_SOURCE_NOTICE_URL"; then
    echo "open source notices are missing esptool GPL metadata: $OPEN_SOURCE_NOTICE_URL" >&2
    exit 1
  fi
  if [[ ! -f "$SOURCE_OFFER_URL" ]]; then
    echo "GPL source offer is missing: $SOURCE_OFFER_URL" >&2
    exit 1
  fi
  if ! grep -q '^## esptool$' "$SOURCE_OFFER_URL" || ! grep -q 'GPLv2+' "$SOURCE_OFFER_URL"; then
    echo "GPL source offer is missing esptool metadata: $SOURCE_OFFER_URL" >&2
    exit 1
  fi
  shopt -s nullglob
  esptool_sources=("$FIRMWARE_TOOLS_URL"/sources/esptool-*.tar.* "$FIRMWARE_TOOLS_URL"/sources/esptool-*.zip)
  shopt -u nullglob
  if [[ "${#esptool_sources[@]}" -eq 0 ]]; then
    echo "GPL source archive is missing: $FIRMWARE_TOOLS_URL/sources/esptool-*.tar.*" >&2
    exit 1
  fi
  esptool_source="${esptool_sources[0]}"
  esptool_source_sha="$(shasum -a 256 "$esptool_source" | awk '{print $1}')"
  append_report "- Status: present"
  append_report "- File: \`$NOTICE_URL\`"
  append_report "- Open source notice: \`$OPEN_SOURCE_NOTICE_URL\`"
  append_report "- GPL source offer: \`$SOURCE_OFFER_URL\`"
  append_report "- esptool source archive: \`$esptool_source\`"
  append_report "- esptool source SHA-256: \`$esptool_source_sha\`"
  append_report "- Required entries: \`esptool\`$([[ "$REQUIRE_BUNDLED_PYTHON" -eq 1 ]] && printf ', `python-portable`')"
else
  append_report "- Status: missing"
  append_report "- File: \`$NOTICE_URL\`"
  echo "third-party notices are missing: $NOTICE_URL" >&2
  exit 1
fi
append_report ""

if [[ -n "$CHIP_PORT" ]]; then
  helper_url="$ROOT_DIR/dist/VibeLightApp.app/Contents/Resources/VibeLight_VibeLightApp.bundle/FirmwareTools/vibe-light-firmware-flasher"
  if [[ ! -x "$helper_url" ]]; then
    echo "packaged firmware helper is missing or not executable: $helper_url" >&2
    exit 1
  fi
  chip_log="$LOG_DIR/chip-id-$VERSION.log"
  run_logged "Read target chip" "$chip_log" env \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1 \
    "$helper_url" --chip esp32s3 --port "$CHIP_PORT" --baud "$CHIP_BAUD" chip_id

  append_report "## Target Chip"
  append_report ""
  append_report "- Status: passed"
  append_report "- Port: \`$CHIP_PORT\`"
  append_report "- Log: \`${chip_log#$ROOT_DIR/}\`"
  if grep -q "Chip is ESP32-S3" "$chip_log"; then
    append_report "- Chip: \`$(grep -m 1 'Chip is ' "$chip_log" | sed 's/^.*Chip is //')\`"
  fi
  if grep -q "MAC:" "$chip_log"; then
    append_report "- MAC: \`$(grep -m 1 'MAC:' "$chip_log" | sed 's/^.*MAC: //')\`"
  fi
  append_report ""
else
  append_report "## Target Chip"
  append_report ""
  append_report "- Status: skipped"
  append_report "- Reason: no --chip-port provided"
  append_report ""
fi

FINISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
append_report "## Result"
append_report ""
append_report "- Finished: \`$FINISHED_AT\`"
append_report "- Status: passed"

printf '\nWrote desktop firmware release checklist: %s\n' "$REPORT_URL"
