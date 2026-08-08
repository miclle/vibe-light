# ESP32-S3 DevKit 三色灯固件

目标硬件为 `ESP32-S3-DevKitC-1 N16R8`。固件复用 Vibe Light BLE service 和 `StatusPacket v2`，广播名为 `VibeLight-LED`。

## 接线

每个 LED 必须串联一个 330Ω 限流电阻：

| LED | GPIO | 接线 |
| --- | --- | --- |
| 红 | GPIO4 | GPIO4 → 330Ω → LED 正极，LED 负极 → GND |
| 黄 | GPIO5 | GPIO5 → 330Ω → LED 正极，LED 负极 → GND |
| 绿 | GPIO6 | GPIO6 → 330Ω → LED 正极，LED 负极 → GND |

上电后依次点亮红、黄、绿各 300ms，随后进入交通信号灯循环：绿灯 5 秒、黄灯 2 秒、红灯 5 秒、黄灯 2 秒，再回到绿灯。这个本地循环不依赖 BLE 连接。

## 灯色规则

三个灯是独立状态通道，不做互斥或优先级覆盖：

- 存在错误或 Codex 7D 低额度：红灯慢闪。
- 存在执行中的任务：黄灯慢闪。
- 存在等待人工批准 / 处理，或最近 60 秒内有任务完成：绿灯慢闪。
- 多种条件同时存在时，对应灯同步慢闪；例如一项任务完成而其他任务仍在执行时，黄灯和绿灯同时闪烁。
- 任一 Agent 条件存在时，Agent 灯效完整覆盖交通灯，包括慢闪的灭灯半周期。
- 对应条件都不存在、BLE 断开或状态超时后，恢复到按自检结束时建立的单调时间轴持续推进的交通灯相位，不从绿灯重新开始。

慢闪周期为 1 秒：点亮 500 ms、熄灭 500 ms。

macOS “通用”页的“7D 红灯阈值”默认是 10%，范围 0%–100%；桌面端把低额度判断写入 `alerts`，无告警时发送空数组，因此 LCD 与 LED 使用同一业务阈值。固件中的 `CONFIG_VIBE_LED_CODEX_7D_RED_THRESHOLD_PERCENT` 也是 10%，只作为收到缺少 `alerts` 字段的旧状态包时的兼容兜底。完成绿灯保持时间由 `CONFIG_VIBE_LED_SUCCESS_HOLD_SECONDS` 控制，默认 60 秒。

macOS 可同时连接 `VibeLight-S3` LCD 与 `VibeLight-LED`，并将同一状态包广播到两台设备；任一设备断开不会清除另一台的连接上下文。

## BLE 无线更新

LED 固件使用 16MB Flash 的 A/B 布局：`otadata`、4MB `ota_0` 和 4MB `ota_1`。已有 single-app 设备需要先通过 USB 完整烧录一次 signed bootloader、分区表、`ota_data_initial.bin` 和 signed app；只有 health 上报 `signedUpdatesRequired: true` 后，macOS“固件烧录”页才允许无线更新。

无线更新只接受项目名为 `vibe_light_led`、清单 SHA-256 正确且通过 ESP-IDF 签名验证的 application 镜像。BLE 回调只入队，Flash 写入由独立 worker 执行；同次开机断线后会保留已提交偏移 60 秒。新固件成功启动 LED、BLE GATT 和广播后才标记有效，否则下一次重启自动回滚。bootloader、分区表损坏或设备完全无法启动时仍需 USB 恢复。

## 构建和测试

```bash
make esp32-led-test
make esp32-led-build
make esp32-led-flash-only ESP32_PORT=/dev/cu.usbmodemXXXX
```

发布用签名构建要求外部私钥权限不宽于 `0600`，私钥不能放入仓库：

```bash
VIBE_OTA_SIGNING_KEY=/absolute/path/ota-signing-key.pem \
  script/prepare_desktop_firmware_release.sh \
  --signed-led-ota \
  --version <release-version> \
  --minimum-desktop-version <desktop-version>
```

普通 `make esp32-led-build` 仍是无密钥开发构建；其 bundle 会标记 `secureSigned: false`，设备 health 也会返回 `signedUpdatesRequired: false`，macOS App 不允许用它执行无线更新。

LED 固件将 NimBLE host task 栈固定为 8192 字节。完整验证会同时检查最终 `sdkconfig` 和 BLE 回调的静态栈帧，避免较大的 `StatusPacket v2` 在 GATT 写入路径再次触发栈溢出重启。

也可以在激活 ESP-IDF 后直接运行：

```bash
cd projects/esp32-led
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/cu.usbmodemXXXX flash monitor
```
