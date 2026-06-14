#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VibeLightApp"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
RESOURCE_BUNDLE="$APP_BUNDLE/Contents/Resources/VibeLight_VibeLightApp.bundle"
RELEASE_DIR="$ROOT_DIR/dist/release"
VERSION="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
TARGET_ARCH=""
SIGNING_IDENTITY_VALUE="${SIGNING_IDENTITY:-}"
NOTARIZE=0
SKIP_BUILD=0
NOTARYTOOL_PROFILE_VALUE="${NOTARYTOOL_PROFILE:-}"
APPLE_API_KEY_VALUE="${APPLE_API_KEY:-}"
APPLE_API_KEY_PATH_VALUE="${APPLE_API_KEY_PATH:-}"
APPLE_API_KEY_ID_VALUE="${APPLE_API_KEY_ID:-}"
APPLE_API_ISSUER_VALUE="${APPLE_API_ISSUER:-}"
NOTARYTOOL_TIMEOUT="${NOTARYTOOL_TIMEOUT:-30m}"
SPARKLE_PUBLIC_ED_KEY_VALUE="${SPARKLE_PUBLIC_ED_KEY:-}"
TEMP_KEY_FILE=""

cleanup() {
  if [[ -n "$TEMP_KEY_FILE" ]]; then
    rm -f "$TEMP_KEY_FILE"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
usage: script/package_desktop_release.sh [options]

Builds, Developer ID signs, verifies, and optionally notarizes the macOS app.

Environment:
  SIGNING_IDENTITY      Required. Developer ID Application identity name or hash.
  NOTARYTOOL_PROFILE   Optional. Keychain profile for xcrun notarytool.
  APPLE_API_KEY         Optional. .p8 key content, or path to a .p8 file.
  APPLE_API_KEY_PATH    Optional. Path to a .p8 file.
  APPLE_API_KEY_ID      Required for API key notarization.
  APPLE_API_ISSUER      Required for API key notarization.
  NOTARYTOOL_TIMEOUT    Optional. Defaults to 30m.
  SPARKLE_PUBLIC_ED_KEY Required. Sparkle EdDSA public key for update verification.

Options:
  --arch arm64|x86_64   Build and verify a specific macOS architecture.
  --identity VALUE      Override SIGNING_IDENTITY.
  --notarytool-profile VALUE
                        Override NOTARYTOOL_PROFILE.
  --apple-api-key VALUE .p8 key content, or path to a .p8 file.
  --apple-api-key-path VALUE
                        Path to a .p8 file.
  --apple-api-key-id VALUE
                        App Store Connect API Key ID.
  --apple-api-issuer VALUE
                        App Store Connect API Issuer ID.
  --notarytool-timeout VALUE
                        Timeout passed to notarytool --wait.
  --version VERSION     Archive version suffix. Defaults to current git short SHA.
  --skip-build          Sign the existing dist/VibeLightApp.app.
  --notarize            Submit, wait, staple, and validate notarization.
  -h, --help            Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      TARGET_ARCH="${2:?missing value for --arch}"
      shift 2
      ;;
    --identity)
      SIGNING_IDENTITY_VALUE="${2:?missing value for --identity}"
      shift 2
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
      NOTARYTOOL_TIMEOUT="${2:?missing value for --notarytool-timeout}"
      shift 2
      ;;
    --version)
      VERSION="${2:?missing value for --version}"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --notarize)
      NOTARIZE=1
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

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command not found: $1" >&2
    exit 1
  fi
}

require_command codesign
require_command ditto
require_command file
require_command lipo
require_command security
require_command xcrun

if [[ -n "$TARGET_ARCH" ]]; then
  case "$TARGET_ARCH" in
    arm64|x86_64) ;;
    *)
      echo "unsupported architecture: $TARGET_ARCH" >&2
      exit 2
      ;;
  esac
fi

api_key_path() {
  if [[ -n "$TEMP_KEY_FILE" ]]; then
    printf '%s\n' "$TEMP_KEY_FILE"
    return
  fi

  local key_url="$APPLE_API_KEY_PATH_VALUE"
  if [[ -z "$key_url" && -n "$APPLE_API_KEY_VALUE" && -f "$APPLE_API_KEY_VALUE" ]]; then
    key_url="$APPLE_API_KEY_VALUE"
  fi
  if [[ -z "$key_url" && -n "$APPLE_API_KEY_VALUE" ]]; then
    TEMP_KEY_FILE="$(mktemp "${TMPDIR:-/tmp}/vibe-light-notary-key.XXXXXX.p8")"
    printf '%s\n' "$APPLE_API_KEY_VALUE" >"$TEMP_KEY_FILE"
    chmod 600 "$TEMP_KEY_FILE"
    key_url="$TEMP_KEY_FILE"
  fi
  printf '%s\n' "$key_url"
}

validate_notarization_credentials() {
  if [[ "$NOTARIZE" -eq 0 ]]; then
    return
  fi

  if [[ -n "$NOTARYTOOL_PROFILE_VALUE" ]]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE_VALUE" >/dev/null 2>&1; then
      echo "notarytool profile is not available or is invalid: $NOTARYTOOL_PROFILE_VALUE" >&2
      echo "Create it with:" >&2
      echo "  xcrun notarytool store-credentials $NOTARYTOOL_PROFILE_VALUE --key /path/to/AuthKey.p8 --key-id <KEY_ID> --issuer <ISSUER_ID> --validate" >&2
      exit 2
    fi
    return
  fi

  local key_url
  key_url="$(api_key_path)"
  if [[ -z "$key_url" || -z "$APPLE_API_KEY_ID_VALUE" || -z "$APPLE_API_ISSUER_VALUE" ]]; then
    echo "notarization requires NOTARYTOOL_PROFILE, or APPLE_API_KEY/APPLE_API_KEY_PATH plus APPLE_API_KEY_ID and APPLE_API_ISSUER" >&2
    exit 2
  fi
  if [[ ! -f "$key_url" ]]; then
    echo "Apple API key file does not exist: $key_url" >&2
    exit 2
  fi
}

if [[ -z "$SIGNING_IDENTITY_VALUE" ]]; then
  echo "SIGNING_IDENTITY is required, for example:" >&2
  echo "  SIGNING_IDENTITY=\"Developer ID Application: Miclle Zheng (6UG7DDAY6C)\" $0" >&2
  exit 2
fi

if [[ -z "$SPARKLE_PUBLIC_ED_KEY_VALUE" ]]; then
  echo "SPARKLE_PUBLIC_ED_KEY is required for release builds." >&2
  echo "Generate/import Sparkle keys with Sparkle's generate_keys tool, then export only the public key into this environment." >&2
  exit 2
fi

if ! security find-identity -p codesigning -v | grep -F -- "$SIGNING_IDENTITY_VALUE" >/dev/null; then
  echo "signing identity is not available in the current keychain: $SIGNING_IDENTITY_VALUE" >&2
  security find-identity -p codesigning -v >&2
  exit 1
fi

validate_notarization_credentials

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  release_short_version="$VERSION"
  if [[ ! "$release_short_version" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    release_short_version="$(printf '%s\n' "$VERSION" | sed -E 's/[^0-9]+/./g; s/^\.//; s/\.$//' | awk -F. '{ printf "%d.%d.%d", ($1 == "" ? 0 : $1), ($2 == "" ? 0 : $2), ($3 == "" ? 0 : $3) }')"
  fi
  VIBE_LIGHT_APP_VERSION="$release_short_version" \
    VIBE_LIGHT_BUILD_ARCH="$TARGET_ARCH" \
    VIBE_LIGHT_REQUIRE_SPARKLE_METADATA=1 \
    SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY_VALUE" \
    "$ROOT_DIR/script/build_and_run.sh" --package
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle does not exist: $APP_BUNDLE" >&2
  exit 1
fi

xattr -cr "$APP_BUNDLE"

sign_path() {
  local path="$1"
  codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY_VALUE" "$path"
}

sign_nested_macho() {
  local signed_count=0
  while IFS= read -r -d '' file_url; do
    if /usr/bin/file -b "$file_url" | grep -q "Mach-O"; then
      sign_path "$file_url"
      signed_count=$((signed_count + 1))
    fi
  done < <(find "$APP_BUNDLE" -type f -print0)
  printf 'Signed %s nested Mach-O files.\n' "$signed_count"
}

sign_nested_bundles() {
  local signed_count=0
  while IFS= read -r bundle_url; do
    sign_path "$bundle_url"
    signed_count=$((signed_count + 1))
  done < <(find "$APP_BUNDLE" \
    \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' \) \
    ! -path "$APP_BUNDLE" \
    -type d \
    | sort -r)
  printf 'Signed %s nested code bundles.\n' "$signed_count"
}

verify_nested_macho() {
  while IFS= read -r -d '' file_url; do
    if /usr/bin/file -b "$file_url" | grep -q "Mach-O"; then
      codesign --verify --strict --verbose=2 "$file_url"
    fi
  done < <(find "$APP_BUNDLE" -type f -print0)
}

verify_nested_bundles() {
  while IFS= read -r bundle_url; do
    codesign --verify --strict --verbose=2 "$bundle_url"
  done < <(find "$APP_BUNDLE" \
    \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' \) \
    ! -path "$APP_BUNDLE" \
    -type d \
    | sort -r)
}

make_archive() {
  local suffix="$1"
  local archive_arch_suffix=""
  if [[ -n "$TARGET_ARCH" ]]; then
    archive_arch_suffix="-$TARGET_ARCH"
  fi
  local archive_url="$RELEASE_DIR/$APP_NAME-$VERSION$archive_arch_suffix$suffix.zip"
  mkdir -p "$RELEASE_DIR"
  rm -f "$archive_url"
  ditto -c -k --keepParent --noextattr --norsrc "$APP_BUNDLE" "$archive_url"
  printf '%s\n' "$archive_url"
}

notarytool_submit() {
  local archive_url="$1"
  if [[ -n "$NOTARYTOOL_PROFILE_VALUE" ]]; then
    xcrun notarytool submit "$archive_url" \
      --keychain-profile "$NOTARYTOOL_PROFILE_VALUE" \
      --wait \
      --timeout "$NOTARYTOOL_TIMEOUT"
    return
  fi

  local key_url
  key_url="$(api_key_path)"

  if [[ -z "$key_url" || -z "$APPLE_API_KEY_ID_VALUE" || -z "$APPLE_API_ISSUER_VALUE" ]]; then
    echo "notarization requires NOTARYTOOL_PROFILE, or APPLE_API_KEY/APPLE_API_KEY_PATH plus APPLE_API_KEY_ID and APPLE_API_ISSUER" >&2
    exit 2
  fi

  xcrun notarytool submit "$archive_url" \
    --key "$key_url" \
    --key-id "$APPLE_API_KEY_ID_VALUE" \
    --issuer "$APPLE_API_ISSUER_VALUE" \
    --wait \
    --timeout "$NOTARYTOOL_TIMEOUT"
}

sign_nested_macho
sign_nested_bundles
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  sign_path "$RESOURCE_BUNDLE"
fi
sign_path "$APP_BUNDLE"

verify_nested_macho
verify_nested_bundles
codesign --verify --strict --verbose=4 "$APP_BUNDLE"
if [[ -n "$TARGET_ARCH" ]]; then
  "$ROOT_DIR/script/verify_desktop_release_arch.sh" --arch "$TARGET_ARCH" "$APP_BUNDLE"
fi
VIBE_LIGHT_REQUIRE_SPARKLE_METADATA=1 "$ROOT_DIR/script/verify_desktop_app_bundle.sh" "$APP_BUNDLE"

ARCHIVE_PATH="$(make_archive "")"
printf 'Wrote signed archive: %s\n' "$ARCHIVE_PATH"

if [[ "$NOTARIZE" -eq 1 ]]; then
  notarytool_submit "$ARCHIVE_PATH"
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  ARCHIVE_PATH="$(make_archive "-notarized")"
  printf 'Wrote notarized archive: %s\n' "$ARCHIVE_PATH"
fi

if command -v syspolicy_check >/dev/null 2>&1; then
  if syspolicy_check distribution "$APP_BUNDLE"; then
    printf 'Distribution policy check passed.\n'
  elif [[ "$NOTARIZE" -eq 1 ]]; then
    echo "Distribution policy check failed after notarization." >&2
    exit 1
  else
    echo "Distribution policy check did not pass; this is expected for a signed app before notarization." >&2
  fi
elif command -v spctl >/dev/null 2>&1 && spctl -a -vv --type execute "$APP_BUNDLE"; then
  printf 'Gatekeeper assessment passed.\n'
elif [[ "$NOTARIZE" -eq 1 ]]; then
  echo "Gatekeeper assessment failed after notarization." >&2
  exit 1
else
  echo "Gatekeeper assessment did not pass; this is expected for a signed app before notarization." >&2
fi

printf 'Prepared signed desktop app: %s\n' "$APP_BUNDLE"
