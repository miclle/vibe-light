# vibe-light

Vibe Light 是一个 macOS 原生桌面应用和本地 hook 采集入口，用来把 Codex / Claude 等 AI 编程工具的运行状态同步到 ESP32-S3 硬件显示设备。

当前产品形态是“桌面状态中枢 + BLE 外设 + 竖屏硬件显示”。macOS 侧负责接收 hook、聚合多任务状态并发送 `StatusPacket`；ESP32-S3 侧负责广播 BLE 服务、解析状态包、驱动 Waveshare `ESP32-S3-LCD-3.16` 的 320 x 820 LCD，并在 `busy` 状态下运行 Codex 吃豆人边缘动画。

## macOS 桌面应用

当前实现包含四个核心界面：

- **通用**：展示当前硬件显示状态、最近事件桥接状态、手动写入调试状态和基础偏好。
- **智能体安装**：安装 / 卸载 Codex 和 Claude 的 Vibe Light hooks。
- **硬件设备**：扫描、连接广播 VibeLight BLE 服务的 ESP32-S3 设备，并发送当前状态包。
- **事件**：读取本机采集到的 hook 事件，按最新优先展示来源、事件类型、状态和诊断信息。

桌面端当前发送 `v: 2` 状态包：除了整体 `source`、`state`、`detail`，还包含 `activeCount`、`waitingCount`、`errorCount` 和最多 5 条任务摘要。BLE 写入长度不足时会降级为兼容旧固件的 `v: 1` 单状态包。

## ESP32-S3 固件

固件位于 `projects/esp32`，当前目标硬件为 Waveshare `ESP32-S3-LCD-3.16`。当前实现已经覆盖：

- BLE Peripheral 广播 `VibeLight-S3`，并暴露状态写入 / 健康读取 GATT 特征。
- `StatusPacket` JSON 解析，兼容 `v: 1` 单状态包和 `v: 2` 多任务列表包。
- ST7701 RGB LCD 初始化、PSRAM framebuffer、主动低电平背光 PWM 和基础 RGB565 绘制。
- 屏幕顶部展示聚合状态，中间展示最多 5 条任务摘要；没有任务时回退显示单条 detail。
- `busy` 状态下运行非阻塞 Codex 吃豆人边缘动画，速度随活跃任务数提升。

## 开发运行

```bash
swift build --package-path projects/macos/desktop
swift test --package-path projects/macos/desktop
./script/build_and_run.sh
```

`./script/build_and_run.sh` 会构建 SwiftPM GUI app，生成本地 `dist/VibeLightApp.app`，再以正常 macOS app bundle 方式启动。Codex 桌面端也已配置 Run action 指向这个脚本。

## 验证

提交涉及 macOS app、BLE 协议或 ESP32 固件的变更前，优先运行统一验证入口：

```bash
./script/verify.sh
```

完整验证会依次运行 Swift 测试、ESP32 状态解析 host-side 测试、ESP32 固件构建和 Git whitespace 检查。只想快速验证协议解析和 desktop 逻辑时，可运行：

```bash
./script/verify.sh --quick
```

## Hook CLI

`vibe-light-hook` 从 stdin 读取 JSON，把事件写入 `~/Library/Application Support/VibeLight/events.jsonl`，并输出将要发送给硬件的 `StatusPacket` JSON。

```bash
printf '{"source":"codex","event":"PreToolUse","detail":"running shell"}' | swift run --package-path projects/macos/desktop vibe-light-hook
```

支持的事件与状态映射见 [架构设计](docs/architecture.md)。

## 项目目录

```text
projects/
  macos/
    desktop/   # macOS SwiftPM 桌面应用、Hook CLI、核心模型和测试
  esp32/       # ESP32-S3 固件工程入口
docs/          # 跨工程架构、协议和硬件记录
script/        # 仓库级开发脚本
```

## 文档

- [架构设计](docs/architecture.md)
- [硬件记录](docs/hardware.md)
- [ESP32 固件说明](projects/esp32/README.md)
- [当前待办](TODO.md)
- [Agent 工作指南](AGENTS.md)
