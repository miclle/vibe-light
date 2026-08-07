# LED 交通信号灯 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让三色 LED 在没有 Agent 状态时持续模拟红、绿、黄交通信号灯，并让已有 Agent 状态效果优先显示、结束后自动回到持续运行的交通灯相位。

**Architecture:** 在可做 host-side 测试的 `vibe_led_model` 中新增基于单调运行时间的交通灯状态和最终输出仲裁函数。BLE 层继续负责提供当前状态包与运行时间；有 Agent 信号时输出原有同步慢闪效果，否则输出交通灯相位，因此覆盖期间交通灯时钟仍持续前进。

**Tech Stack:** ESP-IDF、C11、NimBLE、host-side C tests。

## Global Constraints

- 交通灯循环固定为红灯 `5000 ms`、绿灯 `5000 ms`、黄灯 `2000 ms`，顺序为红 → 绿 → 黄 → 红。
- Agent 状态继续沿用当前独立红、黄、绿通道和 `500 ms` 亮 / `500 ms` 灭的同步慢闪规则。
- 任一 Agent 通道生效时完全覆盖交通灯；全部 Agent 通道结束后按单调运行时间对应的相位继续交通灯，不重置周期。
- BLE 未连接时也显示交通灯；协议字段、GPIO 和 macOS 端保持不变。
- 本轮不提交或推送代码。

---

### Task 1: 可测试的交通灯与优先级模型

**Files:**
- Modify: `projects/esp32-led/tests/vibe_led_model_test.c`
- Modify: `projects/esp32-led/main/vibe_led_model.h`
- Modify: `projects/esp32-led/main/vibe_led_model.c`

**Interfaces:**
- Produces: `vibe_led_state_for_traffic_cycle(int64_t uptime_ms)`。
- Produces: `vibe_led_state_for_output(const vibe_status_packet_t *packet, int64_t status_now_ms, int64_t uptime_ms, int64_t traffic_cycle_started_at_ms, const vibe_led_policy_t *policy)`。

- [x] **Step 1: Write failing host tests**

```c
assert(vibe_led_state_for_traffic_cycle(0).red_on);
assert(vibe_led_state_for_traffic_cycle(5000).green_on);
assert(vibe_led_state_for_traffic_cycle(10000).yellow_on);
assert(vibe_led_state_for_traffic_cycle(12000).red_on);
assert(vibe_led_state_for_output(&busy, now, 6000, 0, &POLICY).yellow_on);
assert(vibe_led_state_for_output(&idle, now, 6000, 0, &POLICY).green_on);
```

- [x] **Step 2: Run tests and verify RED**

Run: `projects/esp32-led/tests/run_tests.sh`

Expected: compilation fails because the two traffic-light APIs do not exist.

- [x] **Step 3: Implement the minimal model**

```c
#define VIBE_LED_TRAFFIC_RED_DURATION_MS 5000
#define VIBE_LED_TRAFFIC_GREEN_DURATION_MS 5000
#define VIBE_LED_TRAFFIC_YELLOW_DURATION_MS 2000

vibe_led_state_t vibe_led_state_for_output(
    const vibe_status_packet_t *packet,
    int64_t status_now_ms,
    int64_t uptime_ms,
    int64_t traffic_cycle_started_at_ms,
    const vibe_led_policy_t *policy
)
{
    vibe_led_state_t agent = vibe_led_state_for_status(packet, status_now_ms, policy);
    if (vibe_led_state_any_on(agent)) {
        return vibe_led_state_apply_slow_blink(agent, uptime_ms);
    }
    return vibe_led_state_for_traffic_cycle(uptime_ms - traffic_cycle_started_at_ms);
}
```

- [x] **Step 4: Run tests and verify GREEN**

Run: `projects/esp32-led/tests/run_tests.sh`

Expected: `vibe_led_model_test: ok`.

### Task 2: BLE 刷新路径接入

**Files:**
- Modify: `projects/esp32-led/main/vibe_ble.c`

**Interfaces:**
- Consumes: `vibe_led_state_for_output(const vibe_status_packet_t *packet, int64_t status_now_ms, int64_t uptime_ms, int64_t traffic_cycle_started_at_ms, const vibe_led_policy_t *policy)` from Task 1.
- Produces: the GPIO state passed to `vibe_led_output_set(...)` on every timer tick, status write, connection and disconnection.

- [x] **Step 1: Route final output through the model**

在临界区内保留当前有效状态时间计算；连接时传入 `&current_status`，未连接时传入 `NULL`，然后把最终结果交给 GPIO 输出：

```c
if (current_connection_handle != BLE_HS_CONN_HANDLE_NONE) {
    led_state = vibe_led_state_for_output(
        &current_status,
        now,
        current_uptime_ms,
        traffic_cycle_started_at_uptime_ms,
        &POLICY
    );
} else {
    led_state = vibe_led_state_for_output(
        NULL,
        0,
        current_uptime_ms,
        traffic_cycle_started_at_uptime_ms,
        &POLICY
    );
}
vibe_led_output_set(led_state);
```

- [x] **Step 2: Preserve traffic mode on disconnect**

把断连路径的全灭输出改为调用 `apply_current_status()`，让 `NULL` 状态包选择交通灯相位。

- [x] **Step 3: Run firmware host tests**

Run: `projects/esp32-led/tests/run_tests.sh && projects/esp32/tests/run_status_parser_tests.sh`

Expected: both test binaries exit 0.

### Task 3: 文档同步与项目验证

**Files:**
- Modify: `projects/esp32-led/README.md`
- Modify: `README.md`
- Modify: `TODO.md`
- Modify: `docs/architecture.md`
- Modify: `.agents/rules/project-architecture.md`
- Modify: `.agents/rules/esp32-firmware.md`

**Interfaces:**
- Documents: traffic cycle timing, Agent override behavior, disconnect behavior and the firmware-local responsibility boundary.

- [x] **Step 1: Update behavior documentation**

将“空闲 / 断连时全部熄灭”改为红 5 秒、绿 5 秒、黄 2 秒的循环；明确 Agent 效果优先且结束后按持续运行的相位恢复。

- [x] **Step 2: Run project verification**

Run: `make quick`

Expected: Swift、两套 firmware host tests、文档检查和 whitespace checks 全部退出 0。

- [x] **Step 3: Inspect final scope**

Run: `git status --short && git diff --check && git diff --stat`

Expected: only the plan、LED model/test/BLE integration and the documented behavior surfaces are modified; whitespace checks pass.
