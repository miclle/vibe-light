#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="VibeLightApp"
BUNDLE_ID="dev.miclle.VibeLight"
MIN_SYSTEM_VERSION="14.0"
SIGNING_IDENTITY_VALUE="${SIGNING_IDENTITY:-}"
APP_VERSION="${VIBE_LIGHT_APP_VERSION:-0.0.0}"
APP_BUILD_NUMBER="${VIBE_LIGHT_BUILD_NUMBER:-}"
BUILD_ARCH="${VIBE_LIGHT_BUILD_ARCH:-}"
SPARKLE_FEED_URL="${VIBE_LIGHT_SPARKLE_FEED_URL:-https://github.com/miclle/vibe-light/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/projects/macos/desktop"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_BUNDLE_NAME="VibeLight_VibeLightApp.bundle"
RESOURCE_BUNDLE="$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
APP_ICON_NAME="AppIcon.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift_args=(build --package-path "$PROJECT_DIR")
if [[ -n "$BUILD_ARCH" ]]; then
  case "$BUILD_ARCH" in
    arm64|x86_64) ;;
    *)
      echo "unsupported VIBE_LIGHT_BUILD_ARCH: $BUILD_ARCH" >&2
      exit 2
      ;;
  esac
  swift_args+=(--arch "$BUILD_ARCH")
fi

swift "${swift_args[@]}"
BUILD_PRODUCTS_DIR="$(swift "${swift_args[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_PRODUCTS_DIR/$APP_NAME"
HOOK_BINARY="$BUILD_PRODUCTS_DIR/vibe-light-hook"
BUILD_RESOURCE_BUNDLE="$BUILD_PRODUCTS_DIR/$RESOURCE_BUNDLE_NAME"
SPARKLE_FRAMEWORK="$(find "$PROJECT_DIR/.build" -path '*/Sparkle.framework' -type d -prune | head -n 1 || true)"

if [[ -z "$APP_BUILD_NUMBER" ]]; then
  APP_BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
mkdir -p "$APP_FRAMEWORKS"
ditto --noextattr --norsrc "$BUILD_BINARY" "$APP_BINARY"
ditto --noextattr --norsrc "$HOOK_BINARY" "$APP_MACOS/vibe-light-hook"
ditto --noextattr --norsrc "$BUILD_RESOURCE_BUNDLE" "$RESOURCE_BUNDLE"
ditto --noextattr --norsrc "$RESOURCE_BUNDLE/$APP_ICON_NAME" "$APP_RESOURCES/$APP_ICON_NAME"
if [[ -n "$SPARKLE_FRAMEWORK" ]]; then
  ditto --noextattr --norsrc "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
fi
chmod +x "$APP_BINARY"
chmod +x "$APP_MACOS/vibe-light-hook"

discover_signing_identity() {
  security find-identity -p codesigning -v 2>/dev/null \
    | awk -F '"' '/Developer ID Application/ { print $2; exit }'
}

sign_app() {
  local identity="$SIGNING_IDENTITY_VALUE"
  if [[ -z "$identity" ]]; then
    identity="$(discover_signing_identity)"
  fi

  xattr -cr "$APP_BUNDLE"

  if [[ -n "$identity" ]]; then
    codesign --force --deep --options runtime --sign "$identity" "$APP_BUNDLE"
  else
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
  fi
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" >/dev/null
}

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>Vibe Light</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Vibe Light scans for ESP32 devices and sends status packets over BLE.</string>
  <key>NSBluetoothPeripheralUsageDescription</key>
  <string>Vibe Light scans for ESP32 devices and sends status packets over BLE.</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
</dict>
</plist>
PLIST

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"
fi

sign_app
"$ROOT_DIR/script/verify_desktop_app_bundle.sh" "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --package|package)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..60}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.5
    done
    echo "$APP_NAME did not start within 30 seconds" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
