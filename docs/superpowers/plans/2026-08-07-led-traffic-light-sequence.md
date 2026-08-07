# LED 交通灯顺序修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将空闲交通灯改为绿 → 黄 → 红 → 黄的连续循环，同时保持 Agent 状态完整覆盖并在结束后恢复持续推进的交通灯时间线。

**Architecture:** 继续由 `vibe_led_model` 按自检结束后的单调时间计算本地交通灯相位，不修改 BLE 协议或硬件层。把现有三相位模型改成四相位模型，两个黄灯相位都使用现有的 2000 ms 时长，绿灯和红灯各保持 5000 ms。

**Tech Stack:** C11、ESP-IDF、host-side `assert` 测试、Make。

## Global Constraints

- 交通灯固定为绿灯 `5000 ms`、黄灯 `2000 ms`、红灯 `5000 ms`、黄灯 `2000 ms`。
- Agent 条件继续完整覆盖交通灯，包括慢闪的灭灯半周期。
- Agent 条件结束后按原单调时间线恢复，不重置交通灯周期。
- BLE 协议、GPIO4 / GPIO5 / GPIO6 和启动自检顺序保持不变。

---

### Task 1: 四相位交通灯模型与回归测试

**Files:**
- Modify: `projects/esp32-led/tests/vibe_led_model_test.c`
- Modify: `projects/esp32-led/main/vibe_led_model.c`
- Modify: `projects/esp32-led/main/vibe_led_model.h`

**Interfaces:**
- Consumes: `vibe_led_state_for_traffic_cycle(int64_t uptime_ms)` and `vibe_led_state_for_output(...)`.
- Produces: unchanged public signatures with a 14000 ms green-yellow-red-yellow cycle.

- [x] **Step 1: Write the failing boundary test**

```c
assert_only_green(vibe_led_state_for_traffic_cycle(0));
assert_only_green(vibe_led_state_for_traffic_cycle(4999));
assert_only_yellow(vibe_led_state_for_traffic_cycle(5000));
assert_only_yellow(vibe_led_state_for_traffic_cycle(6999));
assert_only_red(vibe_led_state_for_traffic_cycle(7000));
assert_only_red(vibe_led_state_for_traffic_cycle(11999));
assert_only_yellow(vibe_led_state_for_traffic_cycle(12000));
assert_only_yellow(vibe_led_state_for_traffic_cycle(13999));
assert_only_green(vibe_led_state_for_traffic_cycle(14000));
```

- [x] **Step 2: Run the LED host test and verify RED**

Run: `projects/esp32-led/tests/run_tests.sh`

Expected: assertion failure at uptime 0 because the current model returns red instead of green.

- [x] **Step 3: Implement the minimal four-phase calculation**

Compute boundaries at 5000, 7000, 12000 and 14000 ms. Return green before the first boundary, yellow before the second, red before the third, and yellow for the final phase.

- [x] **Step 4: Update Agent override and resume expectations**

Move the Agent override assertions to the red traffic phase at 7000 / 7500 ms, then assert that idle output uses the four-phase timeline at its explicit epoch and after Agent status ends.

- [x] **Step 5: Run the LED host test and verify GREEN**

Run: `projects/esp32-led/tests/run_tests.sh`

Expected: `vibe_led_model_test: ok`.

### Task 2: 同步规则和用户文档

**Files:**
- Modify: `.agents/rules/project-architecture.md`
- Modify: `.agents/rules/esp32-firmware.md`
- Modify: `README.md`
- Modify: `TODO.md`
- Modify: `docs/architecture.md`
- Modify: `docs/hardware.md`
- Modify: `projects/esp32-led/README.md`

**Interfaces:**
- Consumes: the four-phase timing implemented in Task 1.
- Produces: one consistent source description of green → yellow → red → yellow.

- [x] **Step 1: Replace three-phase descriptions**

Document the four phases and exact durations without changing Agent status semantics, startup self-test, GPIO mapping or BLE behavior.

- [x] **Step 2: Run documentation and whitespace checks**

Run: `make docs-check && git diff --check`

Expected: both commands exit 0.

### Task 3: 完整验证

**Files:**
- Verify only: repository changes from Tasks 1 and 2.

**Interfaces:**
- Consumes: completed source, tests and documentation.
- Produces: fresh host-test, quick-gate and ESP-IDF build evidence.

- [x] **Step 1: Run the normal quick gate**

Run: `make quick`

Expected: macOS tests, firmware host tests, previews and checks all exit 0.

- [x] **Step 2: Build the LED firmware**

Run: `make esp32-led-build`

Expected: ESP-IDF builds `vibe_light_led.bin` successfully.

- [x] **Step 3: Review the final boundary**

Run: `git status --short --branch && git diff --stat && git diff --check`

Expected: only the planned source, test, rule and documentation files are modified; no whitespace errors.

### Task 4: 烧录并验证 LED 开发板

**Files:**
- Verify: `projects/esp32-led/build/bootloader/bootloader.bin`
- Verify: `projects/esp32-led/build/partition_table/partition-table.bin`
- Verify: `projects/esp32-led/build/vibe_light_led.bin`

**Interfaces:**
- Consumes: the verified ESP-IDF build from Task 3 and the connected ESP32-S3 LED board.
- Produces: flash write, digest readback and startup-log evidence for the new firmware.

- [ ] **Step 1: Confirm the serial target and chip identity**

Run `esptool.py chip_id` against the live `/dev/cu.usbmodem*` candidate and require an ESP32-S3 before writing.

- [ ] **Step 2: Flash the LED firmware**

Run: `make esp32-led-test && make esp32-led-flash-only ESP32_PORT=<confirmed-port>`

Expected: bootloader, partition table and `vibe_light_led.bin` each report successful hash verification.

- [ ] **Step 3: Verify flash readback**

Run `esptool.py verify_flash` for offsets `0x0`, `0x8000` and `0x10000` with the matching build artifacts.

Expected: all three ranges report `verify OK (digest matched)`.

- [ ] **Step 4: Inspect startup output**

Run `idf.py -p <confirmed-port> monitor`, observe startup through the LED self-test and first runtime output, then exit the monitor cleanly.

Expected: the new app version boots without panic; after the red-yellow-green self-test, the traffic fallback starts on green unless an Agent condition connects and overrides it.
