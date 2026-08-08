# macOS Desktop Rules

## Scope

The desktop app lives in `projects/macos/desktop` and is a SwiftPM app using SwiftUI and CoreBluetooth. The hook CLI shares the package and writes events into Application Support.

## Core Files

- `Sources/VibeLightCore/StatusModels.swift`: display states, hook event mapping, `StatusPacket`, `StatusTask` and `HealthPacket`.
- `Sources/VibeLightCore/TaskTracker.swift`: multi-task aggregation and `v: 2` packet creation.
- `Sources/VibeLightCore/EventStore.swift`: recent event storage and current state.
- `Sources/VibeLightCore/HardwareDevice.swift` and `HardwareReconnectPolicy.swift`: per-device connection state and reconnect behavior.
- `Sources/VibeLightApp/Views/HardwareDevicesPane.swift`: hardware scan/connect/send workflow.
- `Sources/VibeLightHook/main.swift`: stdin hook CLI entrypoint.

## Rules

- Preserve hook-first behavior. Process detection is not a replacement for hook events.
- Hook CLI writes should be fail-open: do not break Codex or Claude workflows when local logging fails.
- Keep `vibe-light-hook` stdout silent. It may write diagnostics to stderr, but stdout output can corrupt agent hook flows.
- When a managed Codex or Claude hook is already installed, app launch must refresh its stable Application Support executable from the bundled hook if the binaries differ; an app update must not leave the old decoder running indefinitely.
- Codex and Claude installs must include tool events (`PreToolUse` and `PostToolUse`); otherwise `TaskTracker` cannot surface current tool actions such as `Bash / make quick` on the ESP32 task rows.
- Keep `StatusPacket` small. Truncate user-facing text before BLE writes.
- For task timing, keep top-level `StatusPacket.ts` as packet generation time and task-level `updatedAt` as the task's last event time; firmware derives `RUN`, `WAIT` and freshness labels from the difference.
- Keep Codex usage extraction aligned between `HookPayloadDecoder`, `CodexUsageReader`, `TaskTracker`, Swift tests and the protocol docs.
- Keep one CoreBluetooth context per peripheral. Scanning and connecting a second device must not discard the first device's characteristics or health state; status writes fan out to every ready device.
- BLE OTA is strictly single-target even while normal status packets continue to fan out. Require an exact connected device selection, signed bundle, protocol/project match and `otaCapable` health before beginning.
- OTA UI progress must use the ESP32 `committedOffset`; CoreBluetooth write completion or local file reads are not Flash commit evidence. Keep file reads bounded to one BLE frame and preserve the same session ID/SHA when reconnecting within the firmware grace period.
- Do not report OTA success at `rebooting`. Wait for the selected peripheral to reconnect and return matching `firmwareVersion`, `projectName` and `rollbackState == "valid"`.
- When changing packet shape, update Swift tests, ESP32 parser tests and `docs/architecture.md` together.
- When changing hardware UI affordances, keep the "硬件设备" page useful for manual packet sending and demo packets.

## Verification

Run Swift tests for desktop/core changes:

```bash
swift test --package-path projects/macos/desktop
```

For packet or hook aggregation changes, also run:

```bash
./script/verify.sh --quick
```
