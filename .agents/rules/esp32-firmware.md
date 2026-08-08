# ESP32 Firmware Rules

## Scope

The LCD firmware lives in `projects/esp32` and targets Waveshare `ESP32-S3-LCD-3.16`. The LED firmware lives in `projects/esp32-led` and targets `ESP32-S3-DevKitC-1 N16R8`. Both use ESP-IDF and share the BLE status/health parser in `projects/esp32-common/vibe_protocol`.

## Core Files

- `main/vibe_ble.*`: BLE peripheral, `VibeLight-S3` advertising, status write characteristic and health read characteristic.
- `../esp32-common/vibe_protocol/vibe_status.*`: JSON packet parsing, alert flags and display state conversion shared by both firmwares.
- `main/vibe_display_model.*`: render signatures, reference maze coordinates, eaten-pellet visibility reset, actor count and animation geometry that can be tested on host.
- `main/vibe_display_format.c`: task row formatting, task timing / freshness trailing labels, Codex usage line and reset hint, compact counts, footer text and firmware-version text.
- `main/vibe_display_score.*`: NVS-backed high score persistence.
- `main/vibe_display.*`: LCD initialization, framebuffer ownership, backlight PWM, orientation dispatch, final panel flush and non-blocking animation timer.
- `main/vibe_display_portrait.*`: portrait layout, task rows, score/header/footer rendering and portrait Pac-Man animation.
- `main/vibe_display_landscape.*`: landscape RLE maze rendering and landscape-to-physical framebuffer rotation.
- `tests/vibe_status_parser_test.c`: host-side parser and display-model regression tests.

## Rules

- Keep BLE callbacks and parser paths non-blocking.
- Keep OTA Flash operations out of NimBLE callbacks. Callbacks may validate/copy a bounded frame and use a zero-wait queue only; `esp_ota_*`, SHA-256, signature/identity checks and reboot belong to the OTA worker.
- Preserve the LED A/B partition contract in `projects/esp32-common/partitions_ota_16mb.csv`. Existing single-app boards require one full USB migration; application OTA must never claim it can repair a bootloader or partition table.
- OTA progress means bytes committed by `esp_ota_write`, not bytes accepted by CoreBluetooth or queued in RAM. Resume only the same session ID and SHA within the 60-second same-boot grace period.
- Keep production OTA signing keys external with mode `0600`; never add a key, generated signing defaults file or key content to the repository or firmware bundle.
- LED output channels are independent and active-high by default: red GPIO4, yellow GPIO5, green GPIO6, each through its own 330 ohm resistor. Derive each channel separately so error, busy, and waiting/recent-success signals can blink together; keep the shared slow-blink cadence at 500 ms on and 500 ms off unless the product behavior changes explicitly.
- When no Agent LED condition is active, run the firmware-local traffic-light cycle as green 5000 ms, yellow 2000 ms, red 5000 ms and yellow 2000 ms. Start its monotonic timeline after the startup self-test. Agent output fully overrides it, including the off half of blinking; resume from that timeline when Agent output ends, and keep the traffic light active while BLE is disconnected.
- Keep status writes under the current firmware limit; packets at 1024 bytes or larger are rejected.
- Unknown top-level or task states should degrade to `idle`; malformed packets should be rejected without mutating the previous packet.
- Keep display-model logic testable in `vibe_display_model.*` when it does not require hardware handles.
- Keep display text formatting testable in `vibe_display_format.c` rather than folding it into the hardware drawing layer.
- Avoid introducing LVGL until the lightweight framebuffer path is insufficient for a concrete feature such as fonts, complex layout or richer animation.
- `busy` animation should stay firmware-local. The desktop app sends state and counts, not animation frames.
- Keep task trailing-label behavior testable: task-level `updatedAt` plus top-level `ts` maps to `RUN`, `WAIT` or freshness labels; active tasks rotate between timing and task-level `contextUsedPercent` as the `CTX` label, with 80%+ context usage shown more often in warning color and 90%+ shown in critical color; missing or invalid timing falls back to `CTX`; legacy `contextRemainingPercent` remains accepted as a compatibility input.
- Preserve the LCD connection affordance unless product direction changes: Central connect shows `idle / desktop connected`; disconnect shows `offline / desktop disconnected`. The LED firmware uses the traffic-light fallback instead of a separate disconnected output.
- Preserve active-low backlight behavior for the current board unless hardware evidence says otherwise.
- Keep `projects/esp32/tools/render_maze_preview.py` aligned with display model constants when changing the maze, task panel or previewable layout.

## Verification

Run host-side C tests:

```bash
projects/esp32/tests/run_status_parser_tests.sh
projects/esp32-led/tests/run_tests.sh
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
