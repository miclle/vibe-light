# vibe-light

Vibe Light 是一个 macOS 原生桌面应用和本地 hook 采集入口，用来把 Codex / Claude 等 AI 编程工具的运行状态同步到 ESP32-S3 硬件显示设备。

当前产品形态是“桌面状态中枢 + BLE 外设 + 竖屏硬件显示”。macOS 侧负责接收 hook、聚合多任务状态并发送 `StatusPacket`；ESP32-S3 侧负责以 `VibeLight-S3` 广播 BLE 服务、解析状态包、驱动 Waveshare `ESP32-S3-LCD-3.16` 的 320 x 820 LCD，并在 `busy` 状态下运行固件本地的 Codex 吃豆人迷宫动画。

## macOS 桌面应用

当前实现包含四个核心界面：

- **通用**：展示当前硬件显示状态、最近事件桥接状态、手动写入调试状态和基础偏好。
- **智能体安装**：安装 / 卸载 Codex 和 Claude 的 Vibe Light hooks。
- **硬件设备**：扫描、连接广播 VibeLight BLE 服务的 ESP32-S3 设备，并发送当前状态包。
- **事件**：读取本机采集到的 hook 事件，按最新优先展示来源、事件类型、状态和诊断信息。

桌面端当前发送 `v: 2` 状态包：除了整体 `source`、`state`、`detail`，还包含 `activeCount`、`waitingCount`、`errorCount` 和最多 5 条任务摘要。整体详情截断到 80 个 UTF-8 字节，任务标题截断到 32 个 UTF-8 字节，任务详情截断到 40 个 UTF-8 字节。BLE 写入长度不足时会降级为兼容旧固件的 `v: 1` 单状态包。

## ESP32-S3 固件

固件位于 `projects/esp32`，当前目标硬件为 Waveshare `ESP32-S3-LCD-3.16`。当前实现已经覆盖：

- BLE Peripheral 广播 `VibeLight-S3`，并暴露状态写入 / 健康读取 GATT 特征。
- `StatusPacket` JSON 解析，兼容 `v: 1` 单状态包和 `v: 2` 多任务列表包。
- ST7701 RGB LCD 初始化、PSRAM framebuffer、主动低电平背光 PWM 和基础 RGB565 绘制。
- Central 连接后显示 `idle / desktop connected`，断开后显示 `offline / desktop disconnected`，避免屏幕停在过期任务上。
- 屏幕顶部用状态色展示聚合状态，中间显示参考迷宫舞台，底部贴边任务面板展示紧凑计数和最多 5 条任务摘要。
- `busy` 状态下运行非阻塞 Codex 吃豆人迷宫动画；角色数量来自任务列表或 `activeCount`，豆子会在约 5 秒后恢复。
- Host-side 测试覆盖状态解析、未知状态降级、重复包去重、任务行格式、迷宫路径、豆子恢复、角色朝向和底部面板布局。

## 开发运行

第一次在本机搭建环境时，先运行：

```bash
make check-env
make setup
```

`make check-env` 只检查环境并提示缺失项；`make setup` 会交互式安装缺失依赖，包括 Homebrew 依赖和默认路径 `~/esp/esp-idf` 下的 ESP-IDF。国内网络下载 ESP-IDF 工具较慢时，可运行：

```bash
script/setup_env.sh --install --china-mirror
```

仓库里的 Make 命令会在需要时自动加载 ESP-IDF。只有手动运行 `idf.py` 时，才需要进入已激活环境：

```bash
make idf-shell
```

```bash
make desktop-build
make desktop-test
make desktop-run
```

`./script/build_and_run.sh` 会构建 SwiftPM GUI app，生成本地 `dist/VibeLightApp.app`，再以正常 macOS app bundle 方式启动。Codex 桌面端也已配置 Run action 指向这个脚本。

常用 ESP32 入口也已整理成 Make 目标：

```bash
make esp32-preview
make esp32-test
make esp32-build
make esp32-flash ESP32_PORT=/dev/cu.usbmodemXXXX
```

## 验证

提交涉及 macOS app、BLE 协议或 ESP32 固件的变更前，优先运行统一验证入口：

```bash
make verify
```

完整验证会依次运行 Swift 测试、ESP32 状态解析 host-side 测试、ESP32 固件构建和 Git whitespace 检查。只想快速验证协议解析和 desktop 逻辑时，可运行：

```bash
make quick
```

快速验证也会生成本地 ESP32 屏幕预览图：

```bash
/tmp/vibe-maze-preview.png
/tmp/vibe-screen-preview.png
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
