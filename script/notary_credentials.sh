#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
ACTION="validate"
TEMP_KEY_FILE=""

cleanup() {
  if [[ -n "$TEMP_KEY_FILE" ]]; then
    rm -f "$TEMP_KEY_FILE"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
usage: script/notary_credentials.sh [store|validate] [options]

Loads notarization credentials from .env by default.

Actions:
  store       Store App Store Connect API credentials into the Keychain profile.
  validate    Validate the configured Keychain profile or direct API key credentials.

Options:
  --env-file PATH   Load credentials from PATH instead of .env.
  -h, --help        Show this help.

Required for store:
  NOTARYTOOL_PROFILE
  APPLE_API_KEY_PATH or APPLE_API_KEY
  APPLE_API_KEY_ID
  APPLE_API_ISSUER

Notes:
  Prefer APPLE_API_KEY_PATH to avoid putting .p8 private key content in .env.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    store|validate)
      ACTION="$1"
      shift
      ;;
    --env-file)
      ENV_FILE="${2:?missing value for --env-file}"
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

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
elif [[ "$ENV_FILE" != "$ROOT_DIR/.env" ]]; then
  echo "env file does not exist: $ENV_FILE" >&2
  exit 2
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command not found: $1" >&2
    exit 1
  fi
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "$name is required. Copy .env.example to .env and fill it in." >&2
    exit 2
  fi
}

api_key_path() {
  local key_path="${APPLE_API_KEY_PATH:-}"
  local key_value="${APPLE_API_KEY:-}"

  if [[ -n "$key_path" ]]; then
    if [[ ! -f "$key_path" ]]; then
      echo "APPLE_API_KEY_PATH does not exist: $key_path" >&2
      exit 2
    fi
    printf '%s\n' "$key_path"
    return
  fi

  if [[ -n "$key_value" && -f "$key_value" ]]; then
    printf '%s\n' "$key_value"
    return
  fi

  if [[ -n "$key_value" ]]; then
    TEMP_KEY_FILE="$(mktemp "${TMPDIR:-/tmp}/vibe-light-notary-key.XXXXXX.p8")"
    printf '%s\n' "$key_value" >"$TEMP_KEY_FILE"
    chmod 600 "$TEMP_KEY_FILE"
    printf '%s\n' "$TEMP_KEY_FILE"
    return
  fi

  echo "APPLE_API_KEY_PATH or APPLE_API_KEY is required." >&2
  exit 2
}

validate_api_key_env() {
  local key_path
  key_path="$(api_key_path)"
  require_value APPLE_API_KEY_ID "${APPLE_API_KEY_ID:-}"
  require_value APPLE_API_ISSUER "${APPLE_API_ISSUER:-}"
  xcrun notarytool history \
    --key "$key_path" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER" >/dev/null
}

require_command xcrun

case "$ACTION" in
  store)
    require_value NOTARYTOOL_PROFILE "${NOTARYTOOL_PROFILE:-}"
    key_path="$(api_key_path)"
    require_value APPLE_API_KEY_ID "${APPLE_API_KEY_ID:-}"
    require_value APPLE_API_ISSUER "${APPLE_API_ISSUER:-}"
    xcrun notarytool store-credentials "$NOTARYTOOL_PROFILE" \
      --key "$key_path" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER" \
      --validate
    ;;
  validate)
    if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
      xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" >/dev/null
      printf 'Validated notarytool profile: %s\n' "$NOTARYTOOL_PROFILE"
    else
      validate_api_key_env
      printf 'Validated App Store Connect API key credentials.\n'
    fi
    ;;
  *)
    echo "unknown action: $ACTION" >&2
    usage >&2
    exit 2
    ;;
esac
