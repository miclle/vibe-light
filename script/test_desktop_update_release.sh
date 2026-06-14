#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vibe-light-update-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "test failed: $*" >&2
  exit 1
}

make_app_bundle() {
  local app_url="$1"
  local include_update_keys="$2"
  local info_url="$app_url/Contents/Info.plist"

  mkdir -p "$app_url/Contents/Resources"
  printf 'icon' >"$app_url/Contents/Resources/AppIcon.icns"

  cat >"$info_url" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>VibeLightApp</string>
  <key>CFBundleIdentifier</key>
  <string>dev.miclle.VibeLight</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>Vibe Light</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
PLIST

  if [[ "$include_update_keys" == "yes" ]]; then
    /usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 1.2.3' "$info_url"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 123' "$info_url"
    /usr/libexec/PlistBuddy -c 'Add :SUFeedURL string https://github.com/miclle/vibe-light/releases/latest/download/appcast.xml' "$info_url"
    /usr/libexec/PlistBuddy -c 'Add :SUPublicEDKey string abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGH=' "$info_url"
    /usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool true' "$info_url"
  fi
}

assert_verify_fails_without_update_metadata() {
  local app_url="$TMP_DIR/MissingUpdates.app"
  local err_url="$TMP_DIR/missing-updates.err"
  make_app_bundle "$app_url" no

  if VIBE_LIGHT_REQUIRE_SPARKLE_METADATA=1 "$ROOT_DIR/script/verify_desktop_app_bundle.sh" "$app_url" 2>"$err_url"; then
    fail "bundle verification passed without Sparkle update metadata"
  fi
  grep -q 'SUFeedURL' "$err_url" || fail "missing-update failure should mention SUFeedURL"
}

assert_verify_accepts_update_metadata() {
  local app_url="$TMP_DIR/WithUpdates.app"
  make_app_bundle "$app_url" yes

  VIBE_LIGHT_REQUIRE_SPARKLE_METADATA=1 "$ROOT_DIR/script/verify_desktop_app_bundle.sh" "$app_url" >/dev/null
}

assert_appcast_script_exists() {
  "$ROOT_DIR/script/generate_desktop_appcast.sh" --help >/dev/null
}

assert_verify_fails_without_update_metadata
assert_verify_accepts_update_metadata
assert_appcast_script_exists

printf 'desktop update release tests passed\n'
