#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: script/verify_desktop_release_arch.sh --arch arm64|x86_64 APP_BUNDLE

Verifies every Mach-O file inside a macOS app bundle contains the expected
architecture slice.
EOF
}

EXPECTED_ARCH=""
APP_BUNDLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      EXPECTED_ARCH="${2:?missing value for --arch}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "$APP_BUNDLE" ]]; then
        echo "unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      APP_BUNDLE="$1"
      shift
      ;;
  esac
done

case "$EXPECTED_ARCH" in
  arm64|x86_64) ;;
  "")
    echo "--arch is required" >&2
    usage >&2
    exit 2
    ;;
  *)
    echo "unsupported architecture: $EXPECTED_ARCH" >&2
    exit 2
    ;;
esac

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle does not exist: ${APP_BUNDLE:-<missing>}" >&2
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command not found: $1" >&2
    exit 1
  fi
}

require_command file
require_command lipo

checked_count=0
while IFS= read -r -d '' file_url; do
  if ! /usr/bin/file -b "$file_url" | grep -q "Mach-O"; then
    continue
  fi
  archs="$(lipo -archs "$file_url" 2>/dev/null || true)"
  if [[ -z "$archs" ]]; then
    echo "could not read Mach-O architectures: $file_url" >&2
    exit 1
  fi
  if ! grep -Eq "(^|[[:space:]])${EXPECTED_ARCH}($|[[:space:]])" <<<"$archs"; then
    echo "Mach-O file is missing $EXPECTED_ARCH slice: $file_url" >&2
    echo "  architectures: $archs" >&2
    exit 1
  fi
  checked_count=$((checked_count + 1))
done < <(find "$APP_BUNDLE" -type f -print0)

if [[ "$checked_count" -eq 0 ]]; then
  echo "no Mach-O files found in app bundle: $APP_BUNDLE" >&2
  exit 1
fi

printf 'Verified %s Mach-O files contain %s: %s\n' "$checked_count" "$EXPECTED_ARCH" "$APP_BUNDLE"
