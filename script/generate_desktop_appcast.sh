#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
ARCHIVE_PATH=""
RELEASE_NOTES_PATH=""
OUTPUT_PATH="$ROOT_DIR/dist/release/appcast.xml"
DOWNLOAD_URL_PREFIX=""
GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"

usage() {
  cat <<'EOF'
usage: script/generate_desktop_appcast.sh [options]

Generates a Sparkle appcast for the notarized desktop release archive.

Options:
  --version VERSION             Release version. Defaults to current git short SHA.
  --archive PATH                Update archive. Defaults to dist/release/VibeLightApp-<version>-notarized.zip.
  --release-notes PATH          Optional markdown or HTML notes copied next to the archive.
  --output PATH                 Appcast output path. Defaults to dist/release/appcast.xml.
  --download-url-prefix URL     Required. Public URL prefix for release assets.
  --generate-appcast PATH       Override Sparkle generate_appcast tool path.
  SPARKLE_PRIVATE_KEY           Optional. Private EdDSA key content for signing.
  -h, --help                    Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:?missing value for --version}"
      shift 2
      ;;
    --archive)
      ARCHIVE_PATH="${2:?missing value for --archive}"
      shift 2
      ;;
    --release-notes)
      RELEASE_NOTES_PATH="${2:?missing value for --release-notes}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:?missing value for --output}"
      shift 2
      ;;
    --download-url-prefix)
      DOWNLOAD_URL_PREFIX="${2:?missing value for --download-url-prefix}"
      shift 2
      ;;
    --generate-appcast)
      GENERATE_APPCAST="${2:?missing value for --generate-appcast}"
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

if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  echo "--download-url-prefix is required" >&2
  exit 2
fi

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="$ROOT_DIR/dist/release/VibeLightApp-$VERSION-notarized.zip"
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "release archive does not exist: $ARCHIVE_PATH" >&2
  exit 1
fi

if [[ -n "$RELEASE_NOTES_PATH" && ! -f "$RELEASE_NOTES_PATH" ]]; then
  echo "release notes file does not exist: $RELEASE_NOTES_PATH" >&2
  exit 1
fi

if [[ -z "$GENERATE_APPCAST" ]]; then
  GENERATE_APPCAST="$(command -v generate_appcast || true)"
fi
if [[ -z "$GENERATE_APPCAST" ]]; then
  GENERATE_APPCAST="$(find "$ROOT_DIR/projects/macos/desktop/.build" -path '*/generate_appcast' -type f -perm -111 | head -n 1 || true)"
fi
if [[ -z "$GENERATE_APPCAST" || ! -x "$GENERATE_APPCAST" ]]; then
  echo "Sparkle generate_appcast tool was not found. Build or resolve the desktop Swift package first." >&2
  exit 1
fi

updates_dir="$(mktemp -d "${TMPDIR:-/tmp}/vibe-light-appcast.XXXXXX")"
trap 'rm -rf "$updates_dir"' EXIT

archive_name="$(basename "$ARCHIVE_PATH")"
ditto --noextattr --norsrc "$ARCHIVE_PATH" "$updates_dir/$archive_name"
if [[ -n "$RELEASE_NOTES_PATH" ]]; then
  case "$RELEASE_NOTES_PATH" in
    *.html) notes_extension="html" ;;
    *) notes_extension="md" ;;
  esac
  cp "$RELEASE_NOTES_PATH" "$updates_dir/${archive_name%.*}.$notes_extension"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
output_dir="$(cd "$(dirname "$OUTPUT_PATH")" && pwd)"
output_name="$(basename "$OUTPUT_PATH")"
appcast_args=(
  --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  --embed-release-notes
  -o "$output_name"
)
if [[ -n "$SPARKLE_PRIVATE_KEY" ]]; then
  appcast_args+=(--ed-key-file -)
  (cd "$output_dir" && printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" "${appcast_args[@]}" "$updates_dir")
else
  (cd "$output_dir" && "$GENERATE_APPCAST" "${appcast_args[@]}" "$updates_dir")
fi

generated_appcast="$output_dir/$output_name"
if [[ ! -f "$generated_appcast" ]]; then
  echo "Sparkle did not generate the expected appcast: $generated_appcast" >&2
  exit 1
fi

printf 'Wrote Sparkle appcast: %s\n' "$OUTPUT_PATH"
