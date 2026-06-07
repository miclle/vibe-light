# ESP32 Firmware

这里预留给 Vibe Light 的 ESP32-S3 固件工程。

目标硬件为 Waveshare `ESP32-S3-LCD-3.16`，固件负责：

- 作为 BLE Peripheral 广播 `VibeLight` 设备。
- 暴露 Vibe Light GATT service 和状态写入 / 健康状态特征。
- 接收 macOS 应用写入的 `StatusPacket`。
- 驱动 LCD 或 LED 输出 `idle`、`busy`、`waiting`、`success`、`error`、`offline` 等状态。

协议和硬件约束见：

- [架构设计](../../docs/architecture.md)
- [硬件记录](../../docs/hardware.md)
