#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

usage() {
  cat <<'EOF'
usage: script/desktop_release_notarized.sh [options] [-- checklist-options...]

Loads .env, then runs the full desktop firmware release checklist with
notarization enabled.

Options:
  --env-file PATH   Load release variables from PATH instead of .env.
  -h, --help        Show this help.

Common .env variables:
  SIGNING_IDENTITY
  NOTARYTOOL_PROFILE, or APPLE_API_KEY_PATH/APPLE_API_KEY + APPLE_API_KEY_ID + APPLE_API_ISSUER
  PYTHON_RUNTIME
  RELEASE_ARCH
  RELEASE_VERSION
  MINIMUM_DESKTOP_VERSION
  ESP32_PORT
  ESP32_BAUD
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:?missing value for --env-file}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
elif [[ "$ENV_FILE" != "$ROOT_DIR/.env" ]]; then
  echo "env file does not exist: $ENV_FILE" >&2
  exit 2
fi

short_sha="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
today="$(date '+%Y.%m.%d')"
version="${RELEASE_VERSION:-}"
if [[ -z "$version" ]]; then
  version="$today-dev-$short_sha"
fi

args=(
  "$ROOT_DIR/script/desktop_firmware_release_checklist.sh"
  --version "$version"
  --minimum-desktop-version "${MINIMUM_DESKTOP_VERSION:-dev}"
  --notarize
)

if [[ -n "${RELEASE_ARCH:-}" ]]; then
  args+=(--arch "$RELEASE_ARCH")
fi

if [[ -n "${PYTHON_RUNTIME:-}" ]]; then
  args+=(--python-runtime "$PYTHON_RUNTIME")
fi

if [[ "${REQUIRE_BUNDLED_PYTHON:-1}" != "0" ]]; then
  args+=(--require-bundled-python)
fi

if [[ -n "${ESP32_PORT:-}" ]]; then
  args+=(--chip-port "$ESP32_PORT")
fi

if [[ -n "${ESP32_BAUD:-}" ]]; then
  args+=(--chip-baud "$ESP32_BAUD")
fi

exec "${args[@]}" "$@"
