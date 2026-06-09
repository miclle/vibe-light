# Project Architecture Rules

## Product Shape

Vibe Light is a local status bridge for AI coding tools. The macOS app collects Codex / Claude events, normalizes them into a small display state, and writes that state to an ESP32-S3 display device over BLE. The ESP32-S3 firmware renders the visible hardware experience.

## Cross-Layer Boundary

- macOS owns tool semantics, event ingestion, task aggregation, preferences, BLE scanning and BLE writes.
- The BLE protocol owns stable packet shape, versioning and compatibility.
- ESP32-S3 owns packet parsing, health reporting, LCD drawing and local animation.
- Do not push full hook payloads, session history or frame-by-frame animation data into the hardware protocol.

## Status Contract

The stable display states are `idle`, `busy`, `waiting`, `success`, `error` and `offline`.

Current desktop packets use `v: 2` with aggregate counts and up to 5 task rows. The firmware remains compatible with `v: 1` single-status packets. If BLE write length is constrained, desktop code may fall back from `v: 2` to `v: 1`.

## Task Aggregation

`TaskTracker` is the source of truth for multi-task display state:

- `waiting` outranks `busy`.
- `busy` outranks recent `error` and `success`.
- `error` outranks `success` when no task is active.
- Active rows are capped at 5 before crossing BLE.

Firmware should display the rows it receives. It should not infer Codex or Claude lifecycle semantics.

## Animation Direction

The Codex Pac-Man style animation is firmware-local display behavior. `activeCount`, `waitingCount` and `errorCount` can tune visual emphasis, but they must not change protocol meaning. Animation ticks must be non-blocking and must not block BLE callbacks, JSON parsing or health reads.

The current firmware uses a 320px reference maze stage, a bottom task panel and a 240ms animation timer. Actor count comes from `tasks[]` first, then falls back to `activeCount`, and remains capped at 5.
