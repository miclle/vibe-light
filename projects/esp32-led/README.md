# ESP32-S3 DevKit 三色灯固件

目标硬件为 `ESP32-S3-DevKitC-1 N16R8`。固件复用 Vibe Light BLE service 和 `StatusPacket v2`，广播名为 `VibeLight-LED`。

## 接线

每个 LED 必须串联一个 330Ω 限流电阻：

| LED | GPIO | 接线 |
| --- | --- | --- |
| 红 | GPIO4 | GPIO4 → 330Ω → LED 正极，LED 负极 → GND |
| 黄 | GPIO5 | GPIO5 → 330Ω → LED 正极，LED 负极 → GND |
| 绿 | GPIO6 | GPIO6 → 330Ω → LED 正极，LED 负极 → GND |

上电后依次点亮红、黄、绿各 300ms，随后进入交通信号灯循环：红灯 5 秒、绿灯 5 秒、黄灯 2 秒，再回到红灯。这个本地循环不依赖 BLE 连接。

## 灯色规则

三个灯是独立状态通道，不做互斥或优先级覆盖：

- 存在错误或 Codex 7D 低额度：红灯慢闪。
- 存在执行中的任务：黄灯慢闪。
- 存在等待人工批准 / 处理，或最近 60 秒内有任务完成：绿灯慢闪。
- 多种条件同时存在时，对应灯同步慢闪；例如一项任务完成而其他任务仍在执行时，黄灯和绿灯同时闪烁。
- 任一 Agent 条件存在时，Agent 灯效完整覆盖交通灯，包括慢闪的灭灯半周期。
- 对应条件都不存在、BLE 断开或状态超时后，恢复到按自检结束时建立的单调时间轴持续推进的交通灯相位，不从红灯重新开始。

慢闪周期为 1 秒：点亮 500 ms、熄灭 500 ms。

macOS “通用”页的“7D 红灯阈值”默认是 10%，范围 0%–100%；桌面端把低额度判断写入 `alerts`，无告警时发送空数组，因此 LCD 与 LED 使用同一业务阈值。固件中的 `CONFIG_VIBE_LED_CODEX_7D_RED_THRESHOLD_PERCENT` 也是 10%，只作为收到缺少 `alerts` 字段的旧状态包时的兼容兜底。完成绿灯保持时间由 `CONFIG_VIBE_LED_SUCCESS_HOLD_SECONDS` 控制，默认 60 秒。

macOS 可同时连接 `VibeLight-S3` LCD 与 `VibeLight-LED`，并将同一状态包广播到两台设备；任一设备断开不会清除另一台的连接上下文。

## 构建和测试

```bash
make esp32-led-test
make esp32-led-build
make esp32-led-flash-only ESP32_PORT=/dev/cu.usbmodemXXXX
```

LED 固件将 NimBLE host task 栈固定为 8192 字节。完整验证会同时检查最终 `sdkconfig` 和 BLE 回调的静态栈帧，避免较大的 `StatusPacket v2` 在 GATT 写入路径再次触发栈溢出重启。

也可以在激活 ESP-IDF 后直接运行：

```bash
cd projects/esp32-led
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/cu.usbmodemXXXX flash monitor
```
