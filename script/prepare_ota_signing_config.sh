#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: script/prepare_ota_signing_config.sh OUTPUT_DEFAULTS [GENERATED_SDKCONFIG]" >&2
  exit 2
fi

KEY_PATH="${VIBE_OTA_SIGNING_KEY:-}"
OUTPUT_PATH="$1"
GENERATED_SDKCONFIG="${2:-}"
if [[ -z "$KEY_PATH" ]]; then
  echo "VIBE_OTA_SIGNING_KEY must point to an external ESP-IDF signing private key." >&2
  exit 1
fi
if [[ ! -f "$KEY_PATH" || -L "$KEY_PATH" ]]; then
  echo "OTA signing key is missing, not a regular file, or is a symlink: $KEY_PATH" >&2
  exit 1
fi

KEY_DIR="$(cd "$(dirname "$KEY_PATH")" && pwd -P)"
KEY_PATH="$KEY_DIR/$(basename "$KEY_PATH")"
KEY_MODE="$(stat -f '%Lp' "$KEY_PATH" 2>/dev/null || stat -c '%a' "$KEY_PATH")"
KEY_MODE_VALUE=$((8#$KEY_MODE))
if (( (KEY_MODE_VALUE & 077) != 0 )); then
  echo "OTA signing key must not be readable or writable by group/others (expected mode 600): $KEY_PATH" >&2
  exit 1
fi

if [[ -L "$OUTPUT_PATH" ]] || { [[ -e "$OUTPUT_PATH" ]] && [[ "$OUTPUT_PATH" -ef "$KEY_PATH" ]]; }; then
  echo "OTA signing defaults output must not be a symlink or the signing key itself: $OUTPUT_PATH" >&2
  exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
mkdir -p "$OUTPUT_DIR"
umask 077
TEMP_OUTPUT="$(mktemp "$OUTPUT_DIR/.vibe-ota-signing.XXXXXX")"
cleanup() {
  rm -f "$TEMP_OUTPUT"
}
trap cleanup EXIT
{
  printf '%s\n' 'CONFIG_SECURE_SIGNED_APPS_NO_SECURE_BOOT=y'
  printf '%s\n' 'CONFIG_SECURE_SIGNED_ON_UPDATE_NO_SECURE_BOOT=y'
  printf '%s\n' 'CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES=y'
  printf 'CONFIG_SECURE_BOOT_SIGNING_KEY="%s"\n' "$KEY_PATH"
} >"$TEMP_OUTPUT"
chmod 0600 "$TEMP_OUTPUT"
mv -f "$TEMP_OUTPUT" "$OUTPUT_PATH"

if [[ -n "$GENERATED_SDKCONFIG" ]]; then
  if [[ -L "$GENERATED_SDKCONFIG" ]] || { [[ -e "$GENERATED_SDKCONFIG" ]] && [[ ! -f "$GENERATED_SDKCONFIG" ]]; }; then
    echo "generated sdkconfig must be a regular file and not a symlink: $GENERATED_SDKCONFIG" >&2
    exit 1
  fi
  if [[ -f "$GENERATED_SDKCONFIG" ]] &&
     ! grep -Fqx "CONFIG_SECURE_BOOT_SIGNING_KEY=\"$KEY_PATH\"" "$GENERATED_SDKCONFIG"; then
    rm -f "$GENERATED_SDKCONFIG"
  fi
fi
