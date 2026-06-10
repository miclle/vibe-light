# Vibe Light 硬件记录

## 当前硬件

项目当前采购的开发板为 Waveshare `ESP32-S3-LCD-3.16`。

- 官方文档：https://www.waveshare.net/wiki/ESP32-S3-LCD-3.16
- 产品定位：基于 ESP32-S3 的 HMI 开发板，适合用作 Vibe Light 的 BLE 外设和本地状态显示终端。

## 关键规格

| 项目 | 记录 |
| --- | --- |
| 主控 | ESP32-S3R8，Xtensa 32 位 LX7 双核处理器，最高 240MHz |
| 无线 | 2.4GHz Wi-Fi，Bluetooth 5 LE |
| 内存 | 512KB SRAM，384KB ROM |
| 存储 | 16MB NOR Flash，8MB PSRAM |
| 显示 | 3.16 英寸 LCD，320 x 820 分辨率，64K 色，RGB565 / RGB 并口 |
| 传感器 | QMI8658 六轴 IMU |
| RTC | PCF85063 RTC，预留 RTC 独立电池接口 |
| 存储扩展 | Micro SD 卡槽，使用前需格式化为 FAT32 |
| 电源 | USB Type-C 供电/下载调试，3.7V MX1.25 锂电池充放电接口，拨动开关控制系统电源 |
| 外设接口 | UART、I2C SH1.0 4PIN、USB MX1.25 4PIN |
| 按键 | RST、BOOT；按住 BOOT 后单击 RST 可进入下载模式 |

## 与项目架构的关系

这块板子可以承担架构中的 ESP32-S3 硬件层：

- 作为 BLE Peripheral 广播 `VibeLight` 设备并暴露 GATT 服务。
- 接收 macOS 应用写入的 `StatusPacket`。
- 使用 3.16 英寸 LCD 显示 `idle`、`busy`、`waiting`、`success`、`error`、`offline` 等状态。
- 通过健康状态特征回传运行时长、连接状态和最近状态。

板载 LCD 让第一版不必再外接单独屏幕；板载 BOOT 按键可以保留为调试输入，例如切换测试界面或控制背光。板载 Micro SD、RTC、IMU 和电池电压读取能力暂不属于核心链路，但可作为后续诊断页或设备健康信息的扩展来源。

## 当前源码采用的板级连接

以下来自当前 `projects/esp32/main/vibe_display.c`，是固件实现正在使用的 GPIO 配置。项目记录中已有一次目标板实机闭环：串口日志确认 LCD 初始化和 BLE 广播，macOS 桌面端可连接并写入 `v: 2` 状态包，屏幕可显示 high score、Codex 5H / 7D 用量和底部任务列表。当前 RGB panel 配置为 16-bit data width、18MHz PCLK、PSRAM framebuffer、2 个 framebuffer 和 10 行 bounce buffer。

| 用途 | GPIO |
| --- | --- |
| ST7701 3-wire SPI CS / SCK / SDO | 0 / 2 / 1 |
| RGB DE / PCLK / VSYNC / HSYNC / RESET | 40 / 41 / 39 / 38 / 16 |
| RGB R0-R4 | 17 / 46 / 3 / 8 / 18 |
| RGB G0-G5 | 14 / 13 / 12 / 11 / 10 / 9 |
| RGB B0-B4 | 21 / 5 / 45 / 48 / 47 |
| 背光 PWM | 6，主动低电平，当前 duty `0` 为 full brightness |

## 开发方式

官方文档提供 Arduino IDE 和 ESP-IDF 两种开发路径。当前项目更适合优先采用 ESP-IDF：

- BLE GATT 服务和特征定义更接近底层协议实现。
- LCD、LVGL、SD、RTC、IMU 等模块后续可以按需逐步启用。
- 项目最终需要稳定固件行为，而不是仅运行示例程序。

## 起步路线

当前源码目标已经超过“只显示 state/detail”的最小样机：固件目录已具备 BLE Peripheral、状态解析、健康读取、ST7701 LCD 初始化、PSRAM framebuffer、底部任务面板和 Codex 吃豆人参考迷宫动画，并已有一次目标板实机闭环记录。下一步重点是延长运行观察、复核板级细节并把健康诊断补齐，而不是继续扩展板载外设。

推荐按以下阶段推进：

1. **验证官方硬件示例**
   - 先烧录 Waveshare 官方 `09_FactoryProgram` 或 `07_LVGL_V8_Test` / `08_LVGL_V9_Test`。
   - 确认 USB 下载、PSRAM、LCD、背光和基础板级初始化都正常。
   - 这个阶段不接入 Vibe Light 协议，只确认硬件和官方示例链路可用。

2. **打通 BLE Peripheral**
   - ESP32-S3 广播 `VibeLight-S3`。
   - 暴露 Vibe Light GATT service 和状态写入 characteristic。
   - macOS app 能扫描、连接，并写入 `StatusPacket` JSON。
   - ESP32-S3 收到坏包时保持运行，不重启、不阻塞 BLE 回调。

3. **验证当前屏幕实现**
   - 屏幕顶部显示 `VIBE LIGHT` 和状态色。
   - 中间区域显示 320px 参考迷宫舞台，`busy` 时显示 Codex 吃豆人角色和豆子。
   - 底部贴边任务面板显示 `A` / `W` / `E` 计数和最多 5 条任务摘要；没有任务时显示空任务状态。
   - Host-side PNG 预览入口：

     ```bash
     projects/esp32/tools/render_maze_preview.py /tmp/vibe-maze-preview.png
     projects/esp32/tools/render_maze_preview.py --full-screen /tmp/vibe-screen-preview.png
     ```

4. **验证健康状态回读**
   - 通过健康状态 characteristic 回传协议版本、设备名、运行时长、连接状态和最近状态。
   - macOS app 发现健康状态特征后读取设备状态，用于诊断连接质量。

5. **再做产品化增强**
   - 视觉主题、状态动画、屏幕亮度、电池信息、RTC、IMU、SD 卡日志和 Wi-Fi 配网都放在闭环稳定之后。

第一版固件的验收标准：

- macOS app 能发现 `VibeLight-S3`。
- macOS app 能连接设备。
- macOS app 点击发送最近状态包后，ESP32-S3 能收到并解析 JSON。
- LCD 能展示顶部状态色、参考迷宫、底部任务计数和任务摘要；无任务时能回退到空任务状态。
- `busy` 状态下动画 timer 非阻塞运行，角色数量、整轮豆子重置和主角方向与 host-side 测试 / PNG 预览一致。
- 未知状态或格式错误的 JSON 不会导致固件崩溃。

当前项目记录已经覆盖发现、连接、`v: 2` 写入和基础屏幕确认；后续验收应继续补充长时间运行、重复连接、低余量 reset 提示、等待态尾标轮播和错误包恢复等场景。

如果先验证屏幕和板载资源，可使用官方示例工程：

- `01_ADC_Test`：读取系统电压。
- `02_I2C_PCF85063`：读取 RTC 时间。
- `03_I2C_QMI8658`：读取 IMU 原始数据。
- `04_SD_Card`：挂载并读取 SD 卡信息。
- `05_WIFI_AP` / `06_WIFI_STA`：验证 Wi-Fi。
- `07_LVGL_V8_Test` / `08_LVGL_V9_Test`：验证 LCD 和 LVGL。
- `09_FactoryProgram`：综合测试 PSRAM、Flash、SD、Wi-Fi/Bluetooth、锂电池电压、RTC、IMU 和 BOOT 按键。

## 资料入口

官方资料页包含以下后续固件开发需要的资源：

- 原理图：用于确认 LCD、背光、SD、按键、电池检测、I2C 设备等引脚。
- 示例程序：用于提取板级初始化、LCD 驱动、LVGL 配置和外设初始化方式。
- 数据手册：ESP32-S3、QMI8658、PCF85063、ST7701。
- 固件烧录工具和测试固件：用于出厂功能验证或恢复板子状态。

## 待确认事项

- 对照原理图或官方示例复核当前源码里的 LCD、背光、SD、I2C、BOOT、电池电压检测 GPIO。
- 继续确认当前 ST7701 初始化序列与官方示例的差异，以及长时间运行时是否足够稳定。
- 确认 ESP-IDF 版本和项目固件目录结构。当前固件目录已经落在 `projects/esp32`，本机记录的 ESP-IDF 构建版本为 v5.5.1；当前渲染路径未引入 LVGL。
- 确认 BLE 与 LCD 刷新并行运行时的内存占用和刷新性能。
- 在实机上继续观察 PSRAM framebuffer、主动低电平背光 PWM、Codex 吃豆人动画、低余量 reset 提示和任务尾标轮播是否稳定。
