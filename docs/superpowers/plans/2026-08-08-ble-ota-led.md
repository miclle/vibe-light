# BLE OTA LED Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a testable ESP32-S3 DevKit LED BLE A/B OTA path from the existing macOS firmware bundle, including one-time USB migration, resumable BLE transfer, target/hash validation, boot rollback, and post-reboot version confirmation.

**Architecture:** Keep the existing status service compatible, extend health with optional OTA identity, and add a separate OTA primary service with control/status and binary data characteristics. NimBLE callbacks only copy and enqueue frames; a dedicated FreeRTOS OTA worker owns parsing and `esp_ota_*` calls and publishes committed offsets/credits. The desktop selects one connected peripheral, validates the existing firmware bundle, streams only its application image, and confirms the new `esp_app_desc` identity after reconnect.

**Tech Stack:** ESP-IDF 5.5.1, NimBLE, FreeRTOS, C11, mbedTLS SHA-256, Swift 6.1, CoreBluetooth, SwiftUI, Swift Testing, Python 3.

## Global Constraints

- Work directly on the existing `main` checkout because the user explicitly authorized it; do not create a branch or worktree.
- Do not commit, stage, or push unless the user separately requests it.
- Preserve current status packet UUIDs, packet compatibility, multi-device fan-out, and the 1024-byte status limit.
- OTA is single-target: regular status writes continue to every other ready peripheral.
- BLE callbacks must not perform flash erase/write or other blocking OTA work.
- Existing single-app devices require one USB migration that writes bootloader, partition table, initial OTA data, and `ota_0`.
- Release OTA images must be signed; private signing keys must never enter Git, the application bundle, logs, or documentation.
- Secure Boot V2 and eFuse anti-rollback are out of scope for development boards because they are irreversible production provisioning decisions.
- A BLE disconnect can resume from the last device-committed offset during the same boot; a device power loss restarts the update from byte zero while retaining the previously bootable slot.
- The first implementation target is `VibeLight-LED`; shared APIs and manifest fields must remain directly reusable by the LCD firmware.

---

### Task 1: OTA Partition and Bundle Contract

**Files:**
- Create: `projects/esp32-common/partitions_ota_16mb.csv`
- Modify: `projects/esp32-led/sdkconfig.defaults`
- Modify: `projects/esp32-led/sdkconfig`
- Modify: `projects/esp32/tools/package_firmware_bundle.py`
- Modify: `projects/macos/desktop/Sources/VibeLightCore/FirmwareFlashing.swift`
- Test: `projects/macos/desktop/Tests/VibeLightCoreTests/FirmwareOTATests.swift`
- Test: `projects/esp32/tools/test_package_firmware_bundle.py`
- Modify: `script/verify.sh`

**Interfaces:**
- Consumes: ESP-IDF `flasher_args.json` keys `flash_files`, `flash_settings`, and `app` plus `project_description.json.project_name` and `.project_version`.
- Produces: optional `FirmwareBundleManifest.ota` with `protocolVersion`, `application`, `projectName`, `appVersion`, `size`, `sha256`, and `secureSigned`; legacy manifests decode with `ota == nil` and remain USB-only.

- [x] **Step 1: Write the failing Python bundle test**

  Create a temporary build directory containing literal `flasher_args.json`, `project_description.json`, and three binary files. Execute `package_firmware_bundle.py` and assert the generated manifest contains:

  ```python
  assert manifest["ota"] == {
      "appVersion": "v0.1.3-1-g1234567",
      "application": "vibe_light_led.bin",
      "projectName": "vibe_light_led",
      "protocolVersion": 1,
      "secureSigned": False,
      "sha256": hashlib.sha256(b"LED-APP").hexdigest(),
      "size": 7,
  }
  ```

- [x] **Step 2: Run the Python test and verify RED**

  Run: `python3 -m unittest projects/esp32/tools/test_package_firmware_bundle.py`

  Expected: FAIL because the generated manifest has no `ota` object.

- [x] **Step 3: Write the failing Swift compatibility tests**

  Add tests proving an OTA manifest exposes the application URL and a legacy manifest decodes as USB-only:

  ```swift
  #expect(manifest.ota?.projectName == "vibe_light_led")
  #expect(bundle.otaApplicationURL?.lastPathComponent == "vibe_light_led.bin")
  #expect(legacyManifest.ota == nil)
  #expect(legacyBundle.otaApplicationURL == nil)
  ```

- [x] **Step 4: Run the Swift tests and verify RED**

  Run: `swift test --package-path projects/macos/desktop --filter FirmwareOTA`

  Expected: compilation failure because the OTA manifest API does not exist.

- [x] **Step 5: Implement the manifest contract and bundle generator**

  Add these Codable fields without changing the existing USB `files` contract:

  ```swift
  public struct OTAApplication: Codable, Equatable, Sendable {
      public let protocolVersion: Int
      public let application: String
      public let projectName: String
      public let appVersion: String
      public let size: Int
      public let sha256: String
      public let secureSigned: Bool
  }

  public let ota: OTAApplication?
  ```

  The Python packager must find the app path through `flasher_args["app"]["file"]`, fail if that file is absent from `flash_files`, read project identity from `project_description.json`, and hash the copied application artifact.

- [x] **Step 6: Add the shared 16 MiB A/B partition table**

  Use this exact layout so the existing 24 KiB NVS region remains intact:

  ```csv
  # Name,   Type, SubType, Offset,   Size,     Flags
  nvs,      data, nvs,     0x9000,   0x6000,
  phy_init, data, phy,     0xf000,   0x1000,
  otadata,  data, ota,     0x10000,  0x2000,
  ota_0,    app,  ota_0,   0x20000,  0x400000,
  ota_1,    app,  ota_1,   0x420000, 0x400000,
  ```

  Configure the LED project to use `../esp32-common/partitions_ota_16mb.csv` and enable `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y`. Regenerate/update the committed `sdkconfig`; changing defaults alone is insufficient.

- [x] **Step 7: Verify GREEN and the generated partition behavior**

  Run:

  ```bash
  python3 -m unittest projects/esp32/tools/test_package_firmware_bundle.py
  swift test --package-path projects/macos/desktop --filter FirmwareOTA
  make esp32-led-build
  python "$IDF_PATH/components/partition_table/gen_esp32part.py" projects/esp32-led/build/partition_table/partition-table.bin
  jq '{flash_files,app}' projects/esp32-led/build/flasher_args.json
  ```

  Expected: tests pass; the decoded table contains `otadata`, `ota_0`, and `ota_1`; `flash_files` includes `ota_data_initial.bin`; the app offset is `0x20000`; the app size is below `0x400000`.

---

### Task 2: Shared OTA Session Protocol

**Files:**
- Create: `projects/esp32-common/vibe_ota/CMakeLists.txt`
- Create: `projects/esp32-common/vibe_ota/vibe_ota_protocol.h`
- Create: `projects/esp32-common/vibe_ota/vibe_ota_protocol.c`
- Create: `projects/esp32-common/vibe_ota/tests/vibe_ota_protocol_test.c`
- Create: `projects/esp32-common/vibe_ota/tests/run_tests.sh`
- Modify: `script/verify.sh`

**Interfaces:**
- Consumes: control JSON and binary frames from either firmware's BLE adapter.
- Produces: `vibe_ota_begin_request_t`, `vibe_ota_data_frame_t`, protocol errors, and status JSON independent of ESP-IDF flash handles.

- [x] **Step 1: Write failing C protocol tests**

  Cover literal begin JSON and binary frames. Required observable cases:

  ```c
  assert(vibe_ota_parse_begin(valid_json, strlen(valid_json), &request) == VIBE_OTA_PROTOCOL_OK);
  assert(strcmp(request.project_name, "vibe_light_led") == 0);
  assert(request.image_size == 556640);
  assert(vibe_ota_parse_begin(oversized_json, strlen(oversized_json), &request) == VIBE_OTA_PROTOCOL_INVALID_SIZE);
  assert(vibe_ota_parse_data_frame(frame, frame_len, &parsed) == VIBE_OTA_PROTOCOL_OK);
  assert(parsed.session_id == 0x11223344);
  assert(parsed.offset == 0x1000);
  assert(parsed.payload_len == 4);
  ```

  Also assert malformed SHA hex, empty project name, missing size, frames shorter than eight bytes, and payloads larger than the declared maximum are rejected without mutating the output struct.

- [x] **Step 2: Run the protocol tests and verify RED**

  Run: `projects/esp32-common/vibe_ota/tests/run_tests.sh`

  Expected: compilation failure because `vibe_ota_protocol.*` does not exist.

- [x] **Step 3: Implement the minimal pure protocol layer**

  Define a fixed contract:

  ```c
  #define VIBE_OTA_PROTOCOL_VERSION 1
  #define VIBE_OTA_SHA256_HEX_LENGTH 64
  #define VIBE_OTA_PROJECT_NAME_MAX 32
  #define VIBE_OTA_VERSION_MAX 32
  #define VIBE_OTA_DATA_HEADER_SIZE 8
  ```

  Control operations are `begin`, `finish`, and `abort`. Data header integers are little-endian. NimBLE callbacks copy control bytes into a bounded queue; worker-side cJSON parsing writes only to bounded fixed-size structs and releases the parse tree before returning.

- [x] **Step 4: Implement status formatting and test it**

  Add a failing assertion and then implement compact status JSON with these stable fields:

  ```json
  {"v":1,"state":"receiving","sessionId":287454020,"committedOffset":4096,"imageSize":556640,"credits":4}
  ```

  Terminal states are `idle`, `ready`, `receiving`, `verifying`, `rebooting`, `complete`, and `error`; errors carry a stable machine code and short message.

- [x] **Step 5: Verify GREEN and integrate the runner**

  Run:

  ```bash
  projects/esp32-common/vibe_ota/tests/run_tests.sh
  ./script/verify.sh --quick
  ```

  Expected: the new protocol suite and all existing quick checks pass.

---

### Task 3: ESP-IDF OTA Worker and LED BLE Service

**Files:**
- Create: `projects/esp32-common/vibe_ota/vibe_ota_service.h`
- Create: `projects/esp32-common/vibe_ota/vibe_ota_service.c`
- Modify: `projects/esp32-common/vibe_ota/CMakeLists.txt`
- Modify: `projects/esp32-led/main/CMakeLists.txt`
- Modify: `projects/esp32-led/main/vibe_ble.c`
- Modify: `projects/esp32-led/main/vibe_ble.h`
- Test: `projects/esp32-common/vibe_ota/tests/vibe_ota_protocol_test.c`
- Test: `projects/esp32-led/tests/check_ble_stack_usage.sh`

**Interfaces:**
- Consumes: parsed begin/control requests and copied binary frames from NimBLE callbacks.
- Produces: a FreeRTOS worker queue, committed-offset/credit snapshots, status notifications, and a delayed restart after successful verification.

- [x] **Step 1: Add failing state-transition tests using an injected writer**

  The pure session transition API must prove:

  ```c
  assert(vibe_ota_session_begin(&session, &request, 0x400000) == VIBE_OTA_PROTOCOL_OK);
  assert(vibe_ota_session_accept(&session, request.session_id, 0, 500) == VIBE_OTA_PROTOCOL_OK);
  assert(vibe_ota_session_accept(&session, request.session_id, 1000, 500) == VIBE_OTA_PROTOCOL_UNEXPECTED_OFFSET);
  assert(vibe_ota_session_accept(&session, request.session_id + 1, 500, 500) == VIBE_OTA_PROTOCOL_SESSION_MISMATCH);
  assert(vibe_ota_session_resume_offset(&session) == 0);
  assert(vibe_ota_session_commit(&session, 0, 500) == VIBE_OTA_PROTOCOL_OK);
  assert(vibe_ota_session_resume_offset(&session) == 500);
  ```

  Accepting a frame advances only the queued `accepted_offset`; a successful worker write advances `committed_offset`. A rejected frame must not advance either offset or SHA state.

- [x] **Step 2: Run the shared tests and verify RED**

  Run: `projects/esp32-common/vibe_ota/tests/run_tests.sh`

  Expected: compilation failure for the missing session API.

- [x] **Step 3: Implement the worker ownership boundary**

  Use a fixed queue of four frame buffers. NimBLE access callbacks may only flatten the mbuf into an available frame, validate its eight-byte header, enqueue with zero wait, and return an ATT error when the pool is full. Only `vibe_ota_worker_task` may call:

  ```c
  esp_ota_get_next_update_partition(NULL);
  esp_ota_begin(partition, request.image_size, &handle);
  esp_ota_write(handle, payload, payload_len);
  esp_ota_end(handle);
  esp_ota_get_partition_description(partition, &description);
  esp_ota_set_boot_partition(partition);
  ```

  The worker maintains a streaming SHA-256 over the exact application bytes and compares it with the begin request before `esp_ota_set_boot_partition`.

- [x] **Step 4: Add the LED OTA GATT service**

  Add a separate primary service with three characteristics:

  ```text
  7d8f0101-7b9a-4f0b-9e8a-8b4c2c7f1000  OTA service
  7d8f0102-7b9a-4f0b-9e8a-8b4c2c7f1000  control write
  7d8f0103-7b9a-4f0b-9e8a-8b4c2c7f1000  data write/write-no-response
  7d8f0104-7b9a-4f0b-9e8a-8b4c2c7f1000  status read/notify
  ```

  Start OTA service state before NimBLE. Capture the status value handle during registration, subscribe via `BLE_GATT_CHR_F_NOTIFY`, and notify only from the worker or NimBLE event context supported by the stack.

- [x] **Step 5: Enforce target validation and disconnect resume**

  LED accepts only `projectName == "vibe_light_led"`. On disconnect, retain the live handle and committed offset for 60 seconds; the next central can read status and resume only with the same session ID and SHA. Expiration calls `esp_ota_abort` and returns to `idle`. A reboot or power loss discards the incomplete session and leaves the previous boot partition selected.

- [x] **Step 6: Verify firmware integration**

  Run:

  ```bash
  projects/esp32-common/vibe_ota/tests/run_tests.sh
  projects/esp32-led/tests/run_tests.sh
  make esp32-led-build
  projects/esp32-led/tests/check_ble_stack_usage.sh
  ```

  Expected: all tests/builds pass; the BLE stack check retains at least 1024 bytes headroom; the app remains below its 4 MiB slot.

---

### Task 4: Boot Validation and Health Identity

**Files:**
- Modify: `projects/esp32-common/vibe_protocol/vibe_health.h`
- Modify: `projects/esp32-common/vibe_protocol/vibe_health.c`
- Modify: `projects/esp32-led/main/main.c`
- Modify: `projects/esp32-led/main/vibe_ble.c`
- Modify: `projects/macos/desktop/Sources/VibeLightCore/StatusModels.swift`
- Test: `projects/esp32/tests/vibe_status_parser_test.c`
- Test: `projects/macos/desktop/Tests/VibeLightCoreTests/FirmwareOTATests.swift`

**Interfaces:**
- Consumes: `esp_app_get_description()`, running partition subtype, OTA image state, and successful LED/BLE readiness.
- Produces: backward-compatible health fields `firmwareVersion`, `projectName`, `otaCapable`, `runningSlot`, and `rollbackState`.

- [x] **Step 1: Write failing C health-format tests**

  Assert the real formatter produces optional identity fields and safely escapes strings:

  ```c
  assert(strstr(payload, "\"firmwareVersion\":\"v0.1.3-1-g1234567\"") != NULL);
  assert(strstr(payload, "\"projectName\":\"vibe_light_led\"") != NULL);
  assert(strstr(payload, "\"otaCapable\":true") != NULL);
  assert(strstr(payload, "\"runningSlot\":\"ota_0\"") != NULL);
  assert(strstr(payload, "\"rollbackState\":\"valid\"") != NULL);
  ```

- [x] **Step 2: Run the C test and verify RED**

  Run: `projects/esp32/tests/run_status_parser_tests.sh`

  Expected: compilation failure because the snapshot fields do not exist.

- [x] **Step 3: Write failing Swift decode tests**

  Decode a health JSON fixture with all new fields and another legacy fixture without them. Assert exact values for the new fixture and nil/default-safe values for the old fixture.

- [x] **Step 4: Run the Swift test and verify RED**

  Run: `swift test --package-path projects/macos/desktop --filter FirmwareOTA`

  Expected: compilation failure for missing `HealthPacket` fields.

- [x] **Step 5: Implement health identity and the rollback gate**

  Keep new Swift fields optional. On an LED first boot with `ESP_OTA_IMG_PENDING_VERIFY`, call `esp_ota_mark_app_valid_cancel_rollback()` only after GPIO initialization, startup self-test, NimBLE synchronization, GATT registration, and successful advertising. If any readiness condition fails, leave the image pending so the next reset rolls back.

- [x] **Step 6: Verify GREEN**

  Run:

  ```bash
  projects/esp32/tests/run_status_parser_tests.sh
  swift test --package-path projects/macos/desktop --filter FirmwareOTA
  make esp32-led-build
  ```

  Expected: all pass and the firmware build has rollback enabled.

---

### Task 5: macOS Single-Device OTA Engine

**Files:**
- Create: `projects/macos/desktop/Sources/VibeLightCore/FirmwareOTA.swift`
- Create: `projects/macos/desktop/Sources/VibeLightApp/Services/BluetoothFirmwareUpdater.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Services/BluetoothHardwareManager.swift`
- Test: `projects/macos/desktop/Tests/VibeLightCoreTests/FirmwareOTATests.swift`

**Interfaces:**
- Consumes: validated `FirmwareBundle`, one device ID, OTA characteristics, CoreBluetooth maximum write length, status notifications, and reconnect events.
- Produces: `FirmwareOTAState`, progress fraction, stable error/advice values, begin/data/finish frames, cancellation, and same-boot resume.

- [x] **Step 1: Write failing frame and reducer tests**

  Required hand-derived expectations:

  ```swift
  #expect(FirmwareOTADataFrame(sessionID: 0x11223344, offset: 0x1000, payload: Data([1, 2])).encoded == Data([
      0x44, 0x33, 0x22, 0x11,
      0x00, 0x10, 0x00, 0x00,
      0x01, 0x02,
  ]))
  #expect(FirmwareOTAChunkSizer.payloadLength(maximumWriteLength: 512) == 504)
  #expect(FirmwareOTAChunkSizer.payloadLength(maximumWriteLength: 8) == 0)
  ```

  Reducer tests must prove that an acknowledged `committedOffset` controls progress, a lower reconnect offset rewinds the sender to the device value, a mismatched session fails, and `rebooting` expects a disconnect instead of treating it as an error.

- [x] **Step 2: Run Swift tests and verify RED**

  Run: `swift test --package-path projects/macos/desktop --filter FirmwareOTA`

  Expected: compilation failure for missing OTA types.

- [x] **Step 3: Implement the pure OTA model**

  Define:

  ```swift
  public enum FirmwareOTAState: Equatable, Sendable {
      case idle
      case preparing
      case transferring(committed: Int, total: Int)
      case verifying
      case awaitingReconnect
      case completed(version: String)
      case failed(FirmwareOTAFailure)
  }
  ```

  Control commands encode with sorted JSON keys. File reads use bounded chunks and never load the entire firmware into an additional mutable buffer.

- [x] **Step 4: Integrate CoreBluetooth per peripheral**

  Extend `PeripheralContext` with OTA characteristics and updater state. Discover both the existing status service and OTA service. Subscribe to OTA status notifications. Only the explicitly selected device receives OTA frames; `sendPacketData` skips that context while transferring but continues writing other connected devices.

  The first safe implementation keeps one `.withResponse` data frame in flight, then waits for the device `committedOffset` notification before sending the next frame. This deliberately trades throughput for deterministic retry behavior; a future credit-based `.withoutResponse` pipeline may optimize it without changing the wire format. Never infer completion from bytes queued by the Mac.

- [x] **Step 5: Implement disconnect/reconnect behavior**

  An unexpected disconnect during `receiving` starts scan/reconnect for the same `CBPeripheral.identifier`. After characteristic discovery, read OTA status; if session ID/SHA match, seek the file to `committedOffset` and continue. A device status of `idle` restarts begin from zero. A disconnect after `rebooting` transitions to `awaitingReconnect`.

- [x] **Step 6: Verify GREEN and regressions**

  Run:

  ```bash
  swift test --package-path projects/macos/desktop --filter FirmwareOTA
  swift test --package-path projects/macos/desktop
  ```

  Expected: OTA tests and all existing Swift tests pass.

---

### Task 6: Wireless Update UI and Release Signing Gate

**Files:**
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Models/VibeLightAppModel.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Views/FirmwareFlashPane.swift`
- Modify: `projects/macos/desktop/Sources/VibeLightApp/Views/FirmwareFlashWizardCard.swift`
- Create: `script/prepare_ota_signing_config.sh`
- Modify: `script/prepare_desktop_firmware_release.sh`
- Modify: `.gitignore`
- Test: `script/test_ota_signing_config.sh`
- Test: `projects/macos/desktop/Tests/VibeLightCoreTests/FirmwareOTATests.swift`

**Interfaces:**
- Consumes: connected OTA-capable devices, bundle OTA metadata, updater state, and `VIBE_OTA_SIGNING_KEY` for signed release preparation.
- Produces: separate “USB 初始化” and “无线更新” choices, target/version confirmation, progress/cancel/retry UI, and a release gate that refuses unsigned OTA artifacts.

- [x] **Step 1: Write the failing signing-gate shell test**

  In a temporary directory, assert the script:

  ```text
  exits non-zero when VIBE_OTA_SIGNING_KEY is unset
  exits non-zero when the configured path is missing or group/world-readable
  writes a temporary sdkconfig fragment when the key exists with mode 600
  never copies the private key into the repository or output bundle
  ```

- [x] **Step 2: Run the shell test and verify RED**

  Run: `script/test_ota_signing_config.sh`

  Expected: failure because the signing gate does not exist.

- [x] **Step 3: Implement the external-key signing configuration**

  The generated temporary fragment must enable:

  ```text
  CONFIG_SECURE_SIGNED_APPS_NO_SECURE_BOOT=y
  CONFIG_SECURE_SIGNED_ON_UPDATE_NO_SECURE_BOOT=y
  CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES=y
  CONFIG_SECURE_BOOT_SIGNING_KEY="/absolute/path/from/VIBE_OTA_SIGNING_KEY"
  ```

  Release preparation must build in an isolated signed build directory so the tracked unsigned `sdkconfig` cannot override the fragment:

  ```bash
  idf.py -B build-signed \
    -D SDKCONFIG=build-signed/sdkconfig \
    -D "SDKCONFIG_DEFAULTS=sdkconfig.defaults;/absolute/path/to/generated-signing.defaults" \
    build
  ```

  The packager receives `--secure-signed` only for that build and writes `ota.secureSigned: true`. Development `make quick` remains key-free; an unsigned bundle has `ota.secureSigned: false` and the UI refuses wireless installation unless `#if DEBUG` explicitly allows the local test path. Release preparation must delete only its own temporary fragment on exit.

- [x] **Step 4: Write failing UI model tests**

  Assert that wireless update is enabled only when device project name, OTA protocol version, bundle project name, and signed-release flag all match. Assert that legacy/single-app devices offer USB initialization and that LCD bundles never appear for an LED device.

- [x] **Step 5: Run the Swift tests and verify RED**

  Run: `swift test --package-path projects/macos/desktop --filter FirmwareOTA`

  Expected: failure because eligibility and user-facing OTA state do not exist.

- [x] **Step 6: Implement the UI flow**

  Keep the current firmware page. Present “无线更新” first only for a selected, connected, compatible device; otherwise explain that one USB initialization is required. Show source version, target version, exact device, committed bytes, percentage, current stage, cancel, and retry. Before begin, require an explicit confirmation naming the target device and explaining that power must remain connected.

- [x] **Step 7: Verify GREEN**

  Run:

  ```bash
  script/test_ota_signing_config.sh
  swift test --package-path projects/macos/desktop --filter FirmwareOTA
  swift test --package-path projects/macos/desktop
  ```

  Expected: all pass and no private key path or content appears in tracked bundle resources.

---

### Task 7: Documentation, Full Verification, and Physical Acceptance Runbook

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/hardware.md`
- Modify: `docs/desktop-firmware-flashing.md`
- Modify: `projects/esp32-led/README.md`
- Modify: `TODO.md`
- Modify: `.agents/rules/project-architecture.md`
- Modify: `.agents/rules/esp32-firmware.md`

**Interfaces:**
- Consumes: the final source, generated partition table, automated tests, release signing boundary, and actual device observations.
- Produces: an accurate USB migration/OTA/recovery guide and an explicit list of automated versus physical evidence.

- [x] **Step 1: Update documentation from the implemented source**

  Record the OTA UUIDs, control/data/status semantics, 4 MiB A/B slots, one-time USB migration, signed-release requirement, same-boot BLE resume, power-loss restart behavior, rollback confirmation gate, and the permanent USB recovery boundary. Keep implementation detail out of the product-focused README.

- [x] **Step 2: Run the complete automated gate**

  Run:

  ```bash
  make docs-check
  make verify
  git diff --check
  ```

  Expected: every command exits zero. Decode the final LED partition table again and record the app size versus the 4 MiB slot.

- [x] **Step 3: Perform the LED USB migration**

  With the connected LED board and an explicitly resolved serial port, use the existing app/helper or:

  ```bash
  VIBE_OTA_SIGNING_KEY=/absolute/path/ota-signing-key.pem \
    script/prepare_desktop_firmware_release.sh --signed-led-ota
  cd projects/esp32-led
  idf.py -B build-signed -p /dev/cu.usbmodem1101 flash
  ```

  Completion condition: bootloader, partition table, `ota_data_initial.bin`, and `ota_0` are hash-verified; the board advertises `VibeLight-LED`; health reports `otaCapable=true`, `signedUpdatesRequired=true`, and `runningSlot=ota_0`.

  2026-08-08 evidence: `/dev/cu.usbmodem1101` resolved to LED MAC `74:4d:bd:73:8f:08` and pre-flash project `vibe_light_led`; all four signed A/B writes reported `Hash of data verified`. Partition-table readback showed `otadata @ 0x10000`, `ota_0 @ 0x20000`, and `ota_1 @ 0x420000`. Serial boot evidence showed signed app version `v0.1.2-34-g0521614-dirty` loading from `0x20000`, successful LED self-test/NimBLE advertising, and continuous desktop BLE status writes.

- [ ] **Step 4: Execute the physical fault matrix**

  Record each observation separately:

  ```text
  normal OTA: version changes and running slot toggles
  disconnect at 10%, 50%, 90%: reconnect resumes from device committed offset
  one-byte-corrupt image: hash rejection, no boot-slot change
  LCD image sent to LED: project rejection, no boot-slot change
  power loss during transfer: previous firmware boots, retry starts at zero
  forced reset before mark-valid: bootloader returns to prior slot
  successful first boot: rollbackState becomes valid and the App confirms version
  ```

  Automated/build evidence must not be presented as physical acceptance when hardware is unavailable.

- [x] **Step 5: Review the final diff and requirement coverage**

  Compare the final diff with Tasks 1–7, inspect for key leakage, blocking flash work in BLE callbacks, unbounded allocations, target-selection ambiguity, version-confirmation gaps, and regressions to multi-device status fan-out. Leave all changes uncommitted until the user requests a commit.
