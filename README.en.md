# Vibe Light

[中文 README](README.md)

Vibe Light syncs the status of local AI coding tools to a physical desktop display.

The project combines a native macOS app with ESP32-S3 display firmware. Codex / Claude write local hook events, the macOS app normalizes those events into a compact task state, and the app sends that state to the ESP32-S3 over BLE. The hardware display shows whether the tools are idle, running, waiting for approval, or recently failed, along with Codex usage pressure and a Codex maze animation while work is in progress.

<table>
  <tr>
    <td align="center" width="50%">
      <img src="docs/assets/vibe-light-device-demo.gif" alt="Vibe Light running on ESP32-S3 hardware" width="320">
    </td>
    <td align="center" width="50%">
      <img src="docs/assets/vibe-light-device-running.jpg" alt="Vibe Light task list and maze display on ESP32-S3 hardware" width="320">
    </td>
  </tr>
  <tr>
    <td align="center"><sub>Live motion on real ESP32-S3 hardware.</sub></td>
    <td align="center"><sub>Running state photo showing task rows, timing, and maze details.</sub></td>
  </tr>
</table>

## What It Does

- Shows whether local AI coding tools are idle, running, waiting for the user, completed successfully, or recently errored.
- Aggregates multiple Codex / Claude tasks into one hardware-friendly status view.
- Displays up to 5 task summaries, active / waiting / error counts, task freshness, runtime, and Codex context usage.
- Drives a portrait 320 x 820 ESP32-S3 LCD interface and plays a Codex maze animation while the status is `busy`.
- Provides in-app macOS firmware flashing so test users can initialize the target ESP32-S3 device without installing ESP-IDF.

## Current Status

Vibe Light has a `v0.1.1` macOS release. The core loop already includes the macOS app, ESP32-S3 firmware, BLE status sync, in-app firmware flashing, and Sparkle app updates.

The current release package includes:

- A notarized macOS app.
- Prebuilt firmware for the Waveshare `ESP32-S3-LCD-3.16`.
- A firmware flashing helper and bundled Python runtime.
- `esptool` dependencies, plus open-source notices, a source offer, and a source archive.
- Sparkle update metadata and an appcast for checking stable GitHub releases.

The release flow now covers Developer ID signing, notarization, the release checklist, open-source notices, source-offer checks, and Sparkle appcast generation. The `v0.1.1` downloaded package has been validated through the real user path: launching the app, updating from an older build through the default stable feed, flashing ESP32-S3 firmware over USB, reconnecting over BLE, and reading device health.

## Hardware

The currently supported target device is:

- Waveshare `ESP32-S3-LCD-3.16`
- ESP32-S3 with 8 MB PSRAM
- 320 x 820 ST7701 RGB LCD
- USB for firmware flashing
- BLE for status sync

Hardware facts and official reference links live in [docs/hardware.md](docs/hardware.md).

## Try It

Regular test users can use the GitHub release package directly. They do not need to build firmware from source.

1. Download the latest `VibeLightApp-*-notarized.zip` package from [GitHub Releases](https://github.com/miclle/vibe-light/releases).
2. Extract the zip with Finder or Archive Utility. If using the command line, `ditto -x -k` is recommended.
3. Open `VibeLightApp.app`.
4. Connect the ESP32-S3 development board over USB.
5. Use the app's firmware flashing page to read the chip and write the bundled firmware.
6. After flashing, press `RST` if needed, then connect to `VibeLight-S3` in the app.
7. Install the Codex / Claude hooks from the app, then use your AI coding tools normally.

The bundled flashing path does not require ESP-IDF, `idf.py`, Homebrew `esptool`, or a local Python environment.
Stable updates are discovered through the app's "Check for Updates..." menu item and automatic background checks.

## macOS App

The desktop app lives in [projects/macos/desktop](projects/macos/desktop). It uses SwiftPM, SwiftUI, and CoreBluetooth.

It currently has five main views:

- General: current hardware display state, recent event bridge state, manual debug status, and basic preferences.
- Agent Install: install or uninstall the Vibe Light hooks for Codex / Claude.
- Hardware Devices: scan for devices, connect, send status packets, read health packets, and send display demo packets.
- Firmware Flashing: guide USB chip reads, firmware writes, reboot, BLE reconnect, and health verification.
- Events: inspect locally collected hook events and diagnostics.

The hook CLI stays quiet: it reads JSON from stdin and appends events to `~/Library/Application Support/VibeLight/events.jsonl`. On failure, it writes only to stderr and exits fail-open so it does not interrupt existing Codex / Claude workflows.

## ESP32-S3 Firmware

The firmware lives in [projects/esp32](projects/esp32). It is responsible for:

- Advertising as a BLE Peripheral named `VibeLight-S3`.
- Receiving compact UTF-8 JSON `StatusPacket` writes from the macOS app.
- Returning health packets with uptime, connection state, latest display state, heap, render tick, backlight state, and latest parse error.
- Driving the Waveshare LCD directly with a lightweight framebuffer renderer.
- Remaining compatible with the current `v: 2` multitask status packet and the older `v: 1` single-status packet.

The protocol, status model, and cross-layer responsibilities are documented in [docs/architecture.md](docs/architecture.md). Firmware details live in [projects/esp32/README.md](projects/esp32/README.md).

## Build From Source

Set up a development environment:

```bash
make check-env
make setup
```

`make setup` can interactively install missing Homebrew dependencies and install ESP-IDF under the default `~/esp/esp-idf` path. If ESP-IDF downloads are slow in China, use:

```bash
script/setup_env.sh --install --china-mirror
```

Build, test, and launch the macOS app:

```bash
make desktop-build
make desktop-test
make desktop-run
```

Run firmware host-side tests and generate display previews:

```bash
make esp32-test
make esp32-preview
```

If ESP-IDF is available locally, build and flash firmware from source:

```bash
make esp32-build
make esp32-flash ESP32_PORT=/dev/cu.usbmodemXXXX
```

Only enter an activated ESP-IDF shell when running `idf.py` manually:

```bash
make idf-shell
```

## Verification

Quick verification for desktop logic, protocol parsing, firmware host-side tests, display previews, and whitespace:

```bash
make quick
```

Full verification including an ESP32 firmware build:

```bash
make verify
```

For docs-only changes, run at least:

```bash
make docs-check
```

Firmware display previews are generated at:

```text
/tmp/vibe-maze-preview.png
/tmp/vibe-screen-preview.png
```

## Project Layout

```text
projects/
  macos/
    desktop/   # macOS SwiftPM app, hook CLI, BLE client, tests
  esp32/       # ESP32-S3 firmware and host-side tests
docs/          # Architecture, hardware, firmware flashing, release notes
script/        # Environment setup, verification, packaging, release scripts
```

## Documentation

- [Architecture](docs/architecture.md)
- [Hardware notes](docs/hardware.md)
- [Firmware flashing flow](docs/desktop-firmware-flashing.md)
- [ESP32 firmware guide](projects/esp32/README.md)
- [Roadmap and validation notes](TODO.md)
- [Agent guide](AGENTS.md)

## License

Vibe Light first-party source code uses the [Vibe Light Non-Commercial Source License](LICENSE). Third-party components remain under their respective upstream licenses.
