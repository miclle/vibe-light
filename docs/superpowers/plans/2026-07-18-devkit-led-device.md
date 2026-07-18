# ESP32-S3 DevKit 三色灯设备 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增可与现有 LCD 同时工作的 ESP32-S3-DevKitC-1 三色灯设备，并由 macOS 统一广播任务告警、等待、执行和最近完成状态。

**Architecture:** macOS 继续负责 Codex / Claude 语义、7D 阈值偏好和硬件条件计算，通过向后兼容的 `StatusPacket v2.alerts` 广播给所有设备。LCD 与 LED 固件共用状态 parser；LED 固件把协议状态转换为独立、同步慢闪的三路输出，macOS 蓝牙层以 peripheral id 管理多个连接上下文。

**Tech Stack:** Swift 6.1、SwiftUI、CoreBluetooth、ESP-IDF 5.5、NimBLE、C11、cJSON。

## Global Constraints

- 默认 7D 红灯阈值为 `10%`，可在 macOS 通用设置中调整为 `0...100`。
- 最近完成绿灯保持 `60 秒`。
- 红、黄、绿为独立输出通道：告警、执行中、等待人工 / 最近完成可让对应灯按 500 ms 亮、500 ms 灭同步慢闪。
- LED GPIO 固定为红 `GPIO4`、黄 `GPIO5`、绿 `GPIO6`，高电平点亮。
- BLE service/status/health UUID 与现有设备保持一致；LED 广播名为 `VibeLight-LED`。
- 现有 `VibeLight-S3` LCD 固件、v1 fallback 和 1024 字节写入上限保持兼容。

---

### Task 1: 协议告警和 7D 阈值偏好

**Files:**
- Modify: `projects/macos/desktop/Sources/VibeLightCore/StatusModels.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightCore/TaskTracker.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightCore/VibeLightPreferences.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightCore/StatusPacketCompactor.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Models/VibeLightAppModel.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Views/GeneralPane.swift`
- Test: `projects/macos/desktop/Tests/VibeLightCoreTests/VibeLightCoreTests.swift`

**Interfaces:**
- Produces: `StatusAlert.taskError`, `StatusAlert.codex7dLow`, `StatusAlert.taskBusy`, `StatusAlert.taskWaiting`, `StatusAlert.taskSuccess` and `DisplaySnapshot.statusPacket(codex7dRedThresholdPercent:)`.
- Produces: `VibeLightPreferences.codex7dRedThresholdPercent` clamped to `0...100`.

- [ ] **Step 1: Write failing Swift tests**

```swift
#expect(snapshot.statusPacket(codex7dRedThresholdPercent: 10).alerts == [.codex7dLow])
#expect(errorSnapshot.statusPacket(codex7dRedThresholdPercent: 10).alerts == [.taskError])
#expect(VibeLightPreferences(defaults: defaults).codex7dRedThresholdPercent == 10)
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --package-path projects/macos/desktop`
Expected: compilation fails because the alert API and preference do not exist.

- [ ] **Step 3: Implement the minimal alert contract**

```swift
public enum StatusAlert: String, Codable, Equatable, Sendable {
    case taskError
    case codex7dLow
    case taskBusy
    case taskWaiting
    case taskSuccess
}

public func statusPacket(codex7dRedThresholdPercent: Int) -> StatusPacket
```

- [ ] **Step 4: Run Swift tests and verify GREEN**

Run: `swift test --package-path projects/macos/desktop`
Expected: all Swift tests pass.

### Task 2: 共用 parser 与 LED 灯色模型

**Files:**
- Create: `projects/esp32-common/vibe_protocol/CMakeLists.txt`
- Move responsibility from: `projects/esp32/main/vibe_status.*`, `projects/esp32/main/vibe_health.*`
- Create: `projects/esp32-led/main/vibe_led_model.h`
- Create: `projects/esp32-led/main/vibe_led_model.c`
- Create: `projects/esp32-led/tests/vibe_led_model_test.c`
- Create: `projects/esp32-led/tests/run_tests.sh`
- Modify: `projects/esp32/tests/run_status_parser_tests.sh`

**Interfaces:**
- Consumes: `vibe_status_packet_t.alert_flags` populated from `alerts[]`.
- Produces: `vibe_led_state_for_status(const vibe_status_packet_t *, int64_t now_ms, const vibe_led_policy_t *)`.

- [ ] **Step 1: Write failing host tests**

```c
assert(vibe_led_state_for_status(&packet, now, &policy).red_on);
assert(vibe_led_state_for_status(&waiting, now, &policy).green_on);
assert(vibe_led_state_for_status(&busy, now, &policy).yellow_on);
assert(vibe_led_state_for_status(&recent_success, now, &policy).green_on);
assert(!vibe_led_state_for_status(&expired_success, now, &policy).green_on);
```

- [ ] **Step 2: Run host test and verify RED**

Run: `projects/esp32-led/tests/run_tests.sh`
Expected: compilation fails because `vibe_led_model` does not exist.

- [ ] **Step 3: Implement the minimal parser alert flags and model**

```c
typedef struct { bool red_on; bool yellow_on; bool green_on; } vibe_led_state_t;
typedef struct { int codex_7d_red_threshold_percent; int64_t success_hold_ms; } vibe_led_policy_t;
```

- [ ] **Step 4: Run both firmware host suites and verify GREEN**

Run: `projects/esp32-led/tests/run_tests.sh && projects/esp32/tests/run_status_parser_tests.sh`
Expected: both binaries exit 0.

### Task 3: DevKitC LED 固件

**Files:**
- Create: `projects/esp32-led/CMakeLists.txt`
- Create: `projects/esp32-led/sdkconfig.defaults`
- Create: `projects/esp32-led/main/CMakeLists.txt`
- Create: `projects/esp32-led/main/Kconfig.projbuild`
- Create: `projects/esp32-led/main/main.c`
- Create: `projects/esp32-led/main/vibe_led_output.*`
- Create: `projects/esp32-led/main/vibe_ble.*`
- Create: `projects/esp32-led/README.md`
- Modify: `Makefile`
- Modify: `script/verify.sh`

**Interfaces:**
- Consumes: the common Vibe Light GATT status packet.
- Produces: BLE peripheral `VibeLight-LED`, health packet and mutually-exclusive GPIO output.

- [ ] **Step 1: Add GPIO output testable mapping assertions**

```c
_Static_assert(VIBE_LED_RED_GPIO == 4, "red GPIO contract");
_Static_assert(VIBE_LED_YELLOW_GPIO == 5, "yellow GPIO contract");
_Static_assert(VIBE_LED_GREEN_GPIO == 6, "green GPIO contract");
```

- [ ] **Step 2: Implement GPIO, BLE and one-second expiry refresh**

The BLE write callback parses into the current packet, records packet and local receive timestamps, and applies `vibe_led_state_for_status`. A periodic `esp_timer` advances the effective packet time so a completed-task green indication expires even without another BLE write.

- [ ] **Step 3: Build LED firmware**

Run: `make esp32-led-build`
Expected: ESP-IDF reports `Project build complete`.

### Task 4: macOS 多设备连接和广播

**Files:**
- Modify: `projects/macos/desktop/Sources/VibeLightCore/HardwareDevice.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Services/BluetoothHardwareManager.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Models/VibeLightAppModel.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Views/HardwareDevicesPane.swift`
- Test: `projects/macos/desktop/Tests/VibeLightCoreTests/VibeLightCoreTests.swift`

**Interfaces:**
- Produces: per-device `HardwareConnectionState` and aggregate `connectedCount` behavior.
- Produces: one BLE write per ready peripheral, encoded for that peripheral's maximum write length.

- [ ] **Step 1: Write failing store tests for two simultaneous devices**

```swift
store.upsert(display)
store.upsert(led)
store.markConnecting(display.id)
store.connect(display.id)
store.markConnecting(led.id)
store.connect(led.id)
#expect(store.connectedDeviceIDs == Set([display.id, led.id]))
```

- [ ] **Step 2: Run Swift tests and verify RED**

Run: `swift test --package-path projects/macos/desktop`
Expected: compilation fails because multi-device store APIs do not exist.

- [ ] **Step 3: Implement peripheral contexts keyed by UUID**

```swift
private final class PeripheralContext {
    let peripheral: CBPeripheral
    var statusCharacteristic: CBCharacteristic?
    var healthCharacteristic: CBCharacteristic?
}
private var contextsByID: [String: PeripheralContext] = [:]
```

- [ ] **Step 4: Run Swift tests and build**

Run: `swift test --package-path projects/macos/desktop && swift build --package-path projects/macos/desktop`
Expected: both commands exit 0.

### Task 5: 双固件选择、文档与最终验证

**Files:**
- Modify: `projects/macos/desktop/Sources/VibeLightCore/FirmwareFlashing.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Models/VibeLightAppModel.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Views/FirmwareFlashWizardCard.swift`
- Modify: `projects/esp32/tools/package_firmware_bundle.py`
- Modify: `projects/macos/desktop/Package.swift`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/hardware.md`
- Modify: `TODO.md`
- Modify: `AGENTS.md` and `.agents/rules/*` only where durable workflow changed.

**Interfaces:**
- Produces: firmware target selection by `targetHardware`; chip probe still verifies `esp32s3` but never guesses LCD versus LED.

- [ ] **Step 1: Add failing firmware catalog tests**

```swift
let catalog = try FirmwareBundleCatalog().validatedBundles(in: root)
#expect(catalog.map(\.manifest.targetHardware) == ["ESP32-S3-DevKitC-1 三色灯", "Waveshare ESP32-S3-LCD-3.16"])
```

- [ ] **Step 2: Implement resource catalog and target picker**

Bundle layout:

```text
Resources/FirmwareBundles/
├── display/manifest.json
└── led/manifest.json
```

- [ ] **Step 3: Run complete verification**

Run: `make quick`
Expected: Swift tests, both host-side firmware suites, preview checks, release tests and whitespace checks pass.

Run: `make verify`
Expected: both ESP-IDF firmware projects build successfully.

- [ ] **Step 4: Record real-device validation boundary**

Document that automated builds are complete but GPIO colors, BLE coexistence and USB flashing remain unverified until the physical DevKitC-1 is attached and observed.
