#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if command -v rg >/dev/null 2>&1; then
  SEARCH=(rg -n --no-heading)
else
  SEARCH=(grep -RIn)
fi

section() {
  printf '\n==> %s\n' "$1"
}

run_or_note() {
  local title="$1"
  shift
  section "$title"
  "$@" || true
}

section "Git status"
git status --short --branch

section "Recent commits"
git log --oneline -5

section "Documentation surfaces"
for path in \
  README.md \
  README.en.md \
  TODO.md \
  docs/architecture.md \
  docs/hardware.md \
  projects/esp32/README.md \
  AGENTS.md \
  .agents/rules \
  .agents/skills; do
  if [[ -e "$path" ]]; then
    printf 'ok  %s\n' "$path"
  else
    printf 'missing  %s\n' "$path"
  fi
done

section "Agent guide links"
if [[ -L CLAUDE.md ]]; then
  printf 'CLAUDE.md -> %s\n' "$(readlink CLAUDE.md)"
elif [[ -e CLAUDE.md ]]; then
  printf 'CLAUDE.md exists but is not a symlink\n'
else
  printf 'CLAUDE.md is missing\n'
fi

run_or_note "Make verification targets" "${SEARCH[@]}" "quick|verify|docs-context|docs-check|esp32-preview|esp32-test" Makefile
run_or_note "Repository verification script" "${SEARCH[@]}" "run_step|Git whitespace check|ESP32 display previews" script/verify.sh

run_or_note "macOS protocol models" "${SEARCH[@]}" "StatusPacket|StatusTask|StatusUsage|CodexUsage|HealthPacket|max.*UTF8|encodedJSON" \
  projects/macos/desktop/Sources/VibeLightCore/StatusModels.swift

run_or_note "macOS task aggregation" "${SEARCH[@]}" "TaskTracker|shouldTrack|memory|statusPacket|aggregateState|activeCount|waitingCount|errorCount|codexUsage" \
  projects/macos/desktop/Sources/VibeLightCore/TaskTracker.swift

run_or_note "Hook and usage ingestion" "${SEARCH[@]}" "vibe-light-hook|standardOutput|standardError|token_count|transcript|contextUsedPercent|rate_limits" \
  projects/macos/desktop/Sources/VibeLightHook \
  projects/macos/desktop/Sources/VibeLightCore/EventLog.swift

run_or_note "ESP32 protocol parser" "${SEARCH[@]}" "VIBE_STATUS_MAX_TASKS|vibe_status_packet_t|contextUsedPercent|contextRemainingPercent|1024|unknown|idle" \
  projects/esp32/main/vibe_status.h \
  projects/esp32/main/vibe_status.c \
  projects/esp32/main/vibe_ble.c

run_or_note "ESP32 display model constants and formatting" "${SEARCH[@]}" "VIBE_DISPLAY_MAZE|VIBE_DISPLAY_TASK|ANIMATION_PERIOD|PELLET|CTX|signature|actor_count|usage_summary|footer_text|firmware_version" \
  projects/esp32/main/vibe_display_model.h \
  projects/esp32/main/vibe_display_model.c \
  projects/esp32/main/vibe_display_format.c \
  projects/esp32/main/vibe_display_score.c

run_or_note "ESP32 display hardware path" "${SEARCH[@]}" "LCD_H_RES|LCD_V_RES|ST7701|PCLK|PSRAM|BACKLIGHT|bounce_buffer|esp_timer" \
  projects/esp32/main/vibe_display.c

run_or_note "Host-side docs preview tooling" "${SEARCH[@]}" "FULL_PREVIEW|MAZE|TASK_PANEL|CJK|generate_cjk_font|write_png" \
  projects/esp32/tools/render_maze_preview.py

section "Suggested next commands"
printf 'make docs-check\n'
printf 'make quick  # when docs mention firmware display, protocol, previews, or verification behavior\n'
