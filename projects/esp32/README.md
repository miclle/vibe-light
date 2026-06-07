# ESP32 Firmware

这里是 Vibe Light 的 ESP32-S3 固件工程。

目标硬件为 Waveshare `ESP32-S3-LCD-3.16`，固件负责：

- 作为 BLE Peripheral 广播 `VibeLight` 设备。
- 暴露 Vibe Light GATT service 和状态写入 / 健康状态特征。
- 接收 macOS 应用写入的 `StatusPacket`。
- 驱动 LCD 或 LED 输出 `idle`、`busy`、`waiting`、`success`、`error`、`offline` 等状态。

协议和硬件约束见：

- [架构设计](../../docs/architecture.md)
- [硬件记录](../../docs/hardware.md)

## 当前阶段

当前固件优先实现最小通信闭环：

- 广播设备名：`VibeLight-S3`
- GATT service：`7d8f0001-7b9a-4f0b-9e8a-8b4c2c7f1000`
- 状态写入 characteristic：`7d8f0002-7b9a-4f0b-9e8a-8b4c2c7f1000`
- 健康读取 characteristic：`7d8f0003-7b9a-4f0b-9e8a-8b4c2c7f1000`
- 状态包格式：UTF-8 JSON `StatusPacket`

屏幕驱动当前已接入 Waveshare `ESP32-S3-LCD-3.16` 的 ST7701 RGB LCD 初始化、背光 PWM 和基础 RGB565 绘制。`vibe_display_show_status` 会把 `source`、`state`、`detail` 和时间戳显示到屏幕，同时保留串口日志用于联调。

BLE Central 连接后，屏幕会显示 `idle / desktop connected`；断开后会显示 `offline / desktop disconnected`，避免设备停留在过期的任务状态上。

当前没有引入完整 LVGL，先用轻量 framebuffer 绘制确认 LCD 链路稳定。后续如果需要更复杂的布局、动画或中文字体，再在这个基础上接入 LVGL。

## 构建

安装并启用 ESP-IDF 后，在本目录执行：

```bash
get_idf
idf.py set-target esp32s3
idf.py build
```

当前本机使用 ESP-IDF v5.5.1 构建通过。`get_idf` 会先避开 PlatformIO 的 Python 环境，再加载 `/Users/miclle/esp/esp-idf/export.sh`。

烧录和串口监视：

```bash
idf.py -p /dev/tty.usbmodemXXXX flash monitor
```

如果无法进入下载模式，按住 BOOT 后单击 RST，再重新执行烧录命令。

## 联调

1. 烧录固件并打开串口日志。
2. 启动 macOS app。
3. 在“硬件设备”中扫描并连接 `VibeLight-S3`。
4. 点击发送最近状态包。
5. LCD 应显示最新 `source`、`state`、`detail`，串口也会输出类似内容：

   ```text
   Vibe Light | source=codex state=busy detail=running shell ts=...
   ```
