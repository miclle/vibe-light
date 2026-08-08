#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/script/prepare_ota_signing_config.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    echo "expected command to fail: $*" >&2
    exit 1
  fi
}

expect_failure env -u VIBE_OTA_SIGNING_KEY "$SCRIPT" "$TEST_DIR/signing.defaults"
expect_failure env VIBE_OTA_SIGNING_KEY="$TEST_DIR/missing.pem" "$SCRIPT" "$TEST_DIR/signing.defaults"

printf '%s\n' 'test-private-key-content' >"$TEST_DIR/key.pem"
chmod 0644 "$TEST_DIR/key.pem"
expect_failure env VIBE_OTA_SIGNING_KEY="$TEST_DIR/key.pem" "$SCRIPT" "$TEST_DIR/signing.defaults"

chmod 0600 "$TEST_DIR/key.pem"
VIBE_OTA_SIGNING_KEY="$TEST_DIR/key.pem" "$SCRIPT" "$TEST_DIR/signing.defaults"
KEY_REAL_DIR="$(cd "$TEST_DIR" && pwd -P)"
OUTPUT_MODE="$(stat -f '%Lp' "$TEST_DIR/signing.defaults" 2>/dev/null || stat -c '%a' "$TEST_DIR/signing.defaults")"
[[ "$OUTPUT_MODE" == "600" ]]

grep -q '^CONFIG_SECURE_SIGNED_APPS_NO_SECURE_BOOT=y$' "$TEST_DIR/signing.defaults"
grep -q '^CONFIG_SECURE_SIGNED_ON_UPDATE_NO_SECURE_BOOT=y$' "$TEST_DIR/signing.defaults"
grep -q '^CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES=y$' "$TEST_DIR/signing.defaults"
grep -Fqx "CONFIG_SECURE_BOOT_SIGNING_KEY=\"$KEY_REAL_DIR/key.pem\"" "$TEST_DIR/signing.defaults"

printf '%s\n' 'same-path-private-key' >"$TEST_DIR/same-path.pem"
chmod 0600 "$TEST_DIR/same-path.pem"
expect_failure env VIBE_OTA_SIGNING_KEY="$TEST_DIR/same-path.pem" \
  "$SCRIPT" "$TEST_DIR/same-path.pem"
grep -Fqx 'same-path-private-key' "$TEST_DIR/same-path.pem"

printf '%s\n' 'symlink-private-key' >"$TEST_DIR/symlink-key.pem"
chmod 0600 "$TEST_DIR/symlink-key.pem"
ln -s "$TEST_DIR/symlink-key.pem" "$TEST_DIR/symlink-output.defaults"
expect_failure env VIBE_OTA_SIGNING_KEY="$TEST_DIR/symlink-key.pem" \
  "$SCRIPT" "$TEST_DIR/symlink-output.defaults"
grep -Fqx 'symlink-private-key' "$TEST_DIR/symlink-key.pem"

printf '%s\n' 'CONFIG_SECURE_BOOT_SIGNING_KEY="/old/key.pem"' >"$TEST_DIR/sdkconfig"
VIBE_OTA_SIGNING_KEY="$TEST_DIR/key.pem" \
  "$SCRIPT" "$TEST_DIR/signing.defaults" "$TEST_DIR/sdkconfig"
[[ ! -e "$TEST_DIR/sdkconfig" ]]

printf 'CONFIG_SECURE_BOOT_SIGNING_KEY="%s/key.pem"\n' "$KEY_REAL_DIR" >"$TEST_DIR/sdkconfig"
VIBE_OTA_SIGNING_KEY="$TEST_DIR/key.pem" \
  "$SCRIPT" "$TEST_DIR/signing.defaults" "$TEST_DIR/sdkconfig"
grep -Fqx "CONFIG_SECURE_BOOT_SIGNING_KEY=\"$KEY_REAL_DIR/key.pem\"" "$TEST_DIR/sdkconfig"
if grep -R -F 'test-private-key-content' "$TEST_DIR/signing.defaults" "$ROOT_DIR/projects/macos/desktop/Sources/VibeLightApp/Resources" >/dev/null 2>&1; then
  echo "private key content leaked into generated config or bundle resources" >&2
  exit 1
fi

echo "test_ota_signing_config: ok"
