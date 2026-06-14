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

  mkdir -p "$app_url/Contents/MacOS" "$app_url/Contents/Resources"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$app_url/Contents/MacOS/VibeLightApp"
  chmod +x "$app_url/Contents/MacOS/VibeLightApp"
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

assert_appcast_embeds_release_notes() {
  local app_url="$TMP_DIR/AppcastUpdates.app"
  local archive_url="$TMP_DIR/VibeLightApp-1.2.3-notarized.zip"
  local notes_url="$TMP_DIR/notes.md"
  local appcast_url="$TMP_DIR/appcast.xml"
  local fake_generate_appcast="$TMP_DIR/generate_appcast"

  make_app_bundle "$app_url" yes
  ditto -c -k --keepParent --noextattr --norsrc "$app_url" "$archive_url"
  printf 'Release notes from test.\n' >"$notes_url"

  cat >"$fake_generate_appcast" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

output_name="appcast.xml"
embed_release_notes=0
archive_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --embed-release-notes)
      embed_release_notes=1
      shift
      ;;
    -o)
      output_name="${2:?missing value for -o}"
      shift 2
      ;;
    --download-url-prefix)
      shift 2
      ;;
    *)
      archive_dir="$1"
      shift
      ;;
  esac
done

if [[ "$embed_release_notes" != "1" ]]; then
  echo "missing --embed-release-notes" >&2
  exit 2
fi

archive_name="$(find "$archive_dir" -name '*.zip' -type f -maxdepth 1 | head -n 1 | xargs basename)"
notes_text="$(find "$archive_dir" -name '*.md' -type f -maxdepth 1 -print -quit | xargs cat)"
cat >"$output_name" <<XML
<?xml version="1.0"?>
<rss>
  <channel>
    <item>
      <description>$notes_text</description>
      <enclosure url="https://example.test/$archive_name"/>
    </item>
  </channel>
</rss>
XML
SH
  chmod +x "$fake_generate_appcast"

  SPARKLE_GENERATE_APPCAST="$fake_generate_appcast" "$ROOT_DIR/script/generate_desktop_appcast.sh" \
    --archive "$archive_url" \
    --release-notes "$notes_url" \
    --download-url-prefix "https://github.com/miclle/vibe-light/releases/download/v1.2.3/" \
    --output "$appcast_url" >/dev/null

  grep -q 'VibeLightApp-1.2.3-notarized.zip' "$appcast_url" || fail "appcast should reference the update archive"
  grep -q 'Release notes from test.' "$appcast_url" || fail "appcast should embed release notes"
  if grep -q 'sparkle:releaseNotesLink' "$appcast_url"; then
    fail "appcast should not link to a release notes asset that is not uploaded"
  fi
}

assert_verify_fails_without_update_metadata
assert_verify_accepts_update_metadata
assert_appcast_script_exists
assert_appcast_embeds_release_notes

printf 'desktop update release tests passed\n'
