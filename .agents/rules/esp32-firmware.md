# ESP32 Firmware Rules

## Scope

The firmware lives in `projects/esp32` and targets Waveshare `ESP32-S3-LCD-3.16`. It uses ESP-IDF, BLE GATT, cJSON, ST7701 RGB LCD initialization, PSRAM framebuffer drawing and a lightweight renderer instead of LVGL for the current phase.

## Core Files

- `main/vibe_ble.*`: BLE peripheral, `VibeLight-S3` advertising, status write characteristic and health read characteristic.
- `main/vibe_status.*`: JSON packet parsing and display state conversion.
- `main/vibe_display_model.*`: render signatures, task row formatting, task timing / freshness trailing labels, compact counts, reference maze coordinates, eaten-pellet visibility reset, actor count and animation geometry that can be tested on host.
- `main/vibe_display.*`: LCD initialization, framebuffer drawing, backlight PWM and non-blocking animation timer.
- `tests/vibe_status_parser_test.c`: host-side parser and display-model regression tests.

## Rules

- Keep BLE callbacks and parser paths non-blocking.
- Keep status writes under the current firmware limit; packets at 1024 bytes or larger are rejected.
- Unknown top-level or task states should degrade to `idle`; malformed packets should be rejected without mutating the previous packet.
- Keep display-model logic testable in `vibe_display_model.*` when it does not require hardware handles.
- Avoid introducing LVGL until the lightweight framebuffer path is insufficient for a concrete feature such as fonts, complex layout or richer animation.
- `busy` animation should stay firmware-local. The desktop app sends state and counts, not animation frames.
- Keep task trailing-label behavior testable: task-level `updatedAt` plus top-level `ts` maps to `RUN`, `WAIT` or freshness labels; active tasks rotate between timing and task-level `contextUsedPercent` as the `CTX` label, with 80%+ context usage shown more often in warning color and 90%+ shown in critical color; missing or invalid timing falls back to `CTX`; legacy `contextRemainingPercent` remains accepted as a compatibility input.
- Preserve the current connection affordance unless product direction changes: Central connect shows `idle / desktop connected`; disconnect shows `offline / desktop disconnected`.
- Preserve active-low backlight behavior for the current board unless hardware evidence says otherwise.
- Keep `projects/esp32/tools/render_maze_preview.py` aligned with display model constants when changing the maze, task panel or previewable layout.

## Verification

Run host-side C tests:

```bash
projects/esp32/tests/run_status_parser_tests.sh
```

Generate host-side visual previews when changing display geometry:

```bash
projects/esp32/tools/render_maze_preview.py /tmp/vibe-maze-preview.png
projects/esp32/tools/render_maze_preview.py --full-screen /tmp/vibe-screen-preview.png
```

Run a full firmware build when ESP-IDF is available:

```bash
./script/verify.sh
```
