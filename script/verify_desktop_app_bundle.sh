#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/VibeLightApp.app}"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
REQUIRE_SPARKLE_METADATA="${VIBE_LIGHT_REQUIRE_SPARKLE_METADATA:-0}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle does not exist: $APP_BUNDLE" >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "app Info.plist does not exist: $INFO_PLIST" >&2
  exit 1
fi

icon_file="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "$icon_file" ]]; then
  echo "app Info.plist is missing CFBundleIconFile: $INFO_PLIST" >&2
  exit 1
fi

icon_name="${icon_file%.icns}.icns"
icon_path="$APP_BUNDLE/Contents/Resources/$icon_name"
if [[ ! -f "$icon_path" ]]; then
  echo "app icon file is missing: $icon_path" >&2
  exit 1
fi

if [[ ! -s "$icon_path" ]]; then
  echo "app icon file is empty: $icon_path" >&2
  exit 1
fi

if [[ "$REQUIRE_SPARKLE_METADATA" == "1" ]]; then
  for key in SUFeedURL SUPublicEDKey CFBundleShortVersionString CFBundleVersion; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" 2>/dev/null || true)"
    if [[ -z "$value" ]]; then
      echo "app Info.plist is missing $key: $INFO_PLIST" >&2
      exit 1
    fi
  done

  automatic_checks="$(/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ "$automatic_checks" != "true" ]]; then
    echo "app Info.plist must enable SUEnableAutomaticChecks for release updates: $INFO_PLIST" >&2
    exit 1
  fi
fi

printf 'Verified desktop app bundle icon: %s\n' "$icon_path"
if [[ "$REQUIRE_SPARKLE_METADATA" == "1" ]]; then
  printf 'Verified desktop app Sparkle update metadata.\n'
fi
