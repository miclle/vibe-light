# vibe-light

Vibe Light 是一个 macOS 原生桌面应用和本地 hook 采集入口，用来把 Codex / Claude 等 AI 编程工具的运行状态同步到 ESP32-S3 硬件显示设备。

## macOS 桌面应用

当前实现包含三个核心界面：

- **通用**：展示当前硬件显示状态、最近事件桥接状态、手动写入调试状态和基础偏好。
- **安装向导**：跟踪桌面应用、Hooks、设备连接三步安装进度，并给出 hook CLI 输入示例。
- **事件**：读取本机采集到的 hook 事件，按最新优先展示来源、事件类型、状态和诊断信息。

## 开发运行

```bash
swift build --package-path projects/macos/desktop
swift test --package-path projects/macos/desktop
./script/build_and_run.sh
```

`./script/build_and_run.sh` 会构建 SwiftPM GUI app，生成本地 `dist/VibeLightApp.app`，再以正常 macOS app bundle 方式启动。Codex 桌面端也已配置 Run action 指向这个脚本。

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
