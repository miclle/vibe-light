# Project Architecture Rules

## Product Shape

Vibe Light is a local status bridge for AI coding tools. The macOS app collects Codex / Claude events, normalizes them into a small display state, and broadcasts that state to every connected Vibe Light BLE device. The LCD and three-LED firmwares render different views of the same protocol.

## Cross-Layer Boundary

- macOS owns tool semantics, event ingestion, task aggregation, preferences, BLE scanning and BLE writes.
- The BLE protocol owns stable packet shape, versioning and compatibility.
- ESP32-S3 owns packet parsing, health reporting, LCD drawing/local animation or independent synchronized red/yellow/green output.
- Do not push full hook payloads, session history or frame-by-frame animation data into the hardware protocol.

## Status Contract

The stable display states are `idle`, `busy`, `waiting`, `success`, `error` and `offline`.

Current desktop packets use `v: 2` with aggregate counts, Codex usage, optional `alerts` and up to 5 task rows. Alerts include `taskError`, `codex7dLow`, `taskBusy`, `taskWaiting` and the 60-second `taskSuccess` signal; these compact flags preserve independent LED conditions even when task rows are truncated or the packet falls back to `v: 1`. The 7-day red threshold defaults to 10% and is configurable in the macOS app. Codex usage includes 5h / 7d remaining percentages and optional reset timestamps; LCD firmware shows reset hints only when remaining capacity is low. Task rows may include `updatedAt`; firmware uses top-level `ts` minus task `updatedAt` to render `RUN`, `WAIT` or freshness trailing labels, falling back to task-level context usage when timing data is unavailable. Both firmwares remain compatible with `v: 1` single-status packets. If BLE write length is constrained, desktop code may fall back from `v: 2` to `v: 1` while retaining `alerts`.

Desktop packet text is intentionally bounded before BLE writes: overall `detail` is capped at 80 UTF-8 bytes, task titles at 32 UTF-8 bytes and task details at 40 UTF-8 bytes. Firmware rejects status writes at 1024 bytes or larger.

## Task Aggregation

`TaskTracker` is the source of truth for multi-task display state:

- `waiting` outranks `busy`.
- `busy` outranks recent `error` and `success`.
- When no task is active, aggregate state returns to `idle`; recent `error` and `success` rows remain visible until they expire.
- Visible rows are capped at 5 before crossing BLE; active rows stay first, then recent error and success rows backfill the remaining space.
- Codex memory-writing helper events are filtered out and should not affect the visible hardware state.
- Codex usage comes from hook payload data or the latest transcript `token_count` event; desktop sends 5h / 7d remaining percentages, optional reset timestamps and task-level context used percentage, which remains the firmware fallback when a task row cannot show timing.

Firmware should display the rows it receives. It should not infer Codex or Claude lifecycle semantics.

Firmware may update its own connection affordance: connected Central shows `idle / desktop connected`, disconnected Central shows `offline / desktop disconnected`. It should not otherwise invent Codex or Claude task lifecycle transitions.

## Animation Direction

The Codex Pac-Man style animation is firmware-local display behavior. `activeCount`, `waitingCount` and `errorCount` can tune visual emphasis, but they must not change protocol meaning. Animation ticks must be non-blocking and must not block BLE callbacks, JSON parsing or health reads.

The current firmware uses a 320px reference maze stage, a bottom task panel and a 240ms animation timer. Actor count comes from `tasks[]` first, then falls back to `activeCount`, and remains capped at 5.
