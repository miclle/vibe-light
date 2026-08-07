# Vibe Light

[English README](README.en.md)

Vibe Light 把本机 AI 编程工具的运行状态同步到一块实体桌面屏幕上。

项目由 macOS 原生桌面应用、ESP32-S3 LCD 固件和三色灯固件组成。Codex / Claude 通过本地 hooks 写入事件，macOS app 将事件归一化为紧凑的任务状态，再通过 BLE 同步到所有已连接设备。LCD 展示任务列表和 Codex 吃豆人迷宫动画；红、黄、绿 LED 提供远距离状态提示。

<table>
  <tr>
    <td align="center" width="50%">
      <img src="docs/assets/vibe-light-device-demo.gif" alt="Vibe Light running on ESP32-S3 hardware" width="320">
    </td>
    <td align="center" width="50%">
      <img src="docs/assets/vibe-light-device-running.jpg" alt="Vibe Light task list and maze display on ESP32-S3 hardware" width="320">
    </td>
  </tr>
  <tr>
    <td align="center"><sub>真实 ESP32-S3 设备上的动态运行效果。</sub></td>
    <td align="center"><sub>运行中状态实拍，便于查看任务列表、计时和迷宫细节。</sub></td>
  </tr>
</table>

## 能做什么

- 展示本机 AI 编程工具当前是空闲、运行中、等待用户、成功完成还是发生错误。
- 将多个 Codex / Claude 任务聚合成一个适合硬件显示的状态视图。
- 在屏幕上显示最多 5 条任务摘要、活跃 / 等待 / 错误计数、任务新鲜度、运行时长和 Codex context 用量摘要。
- 驱动竖屏 320 x 820 ESP32-S3 LCD 界面，并在 `busy` 状态下播放 Codex 迷宫动画。
- 同时连接 LCD 与三色灯设备，并把同一状态广播到两者。
- 用黄灯表示执行中、绿灯表示等待人工处理或最近完成、红灯表示错误或 Codex 7D 剩余额度低于可配置阈值。
- 提供 macOS app 内固件烧录流程，测试用户无需安装 ESP-IDF 即可初始化目标 ESP32-S3 设备。

## 当前状态

Vibe Light 目前已有 `v0.1.2` macOS release，核心链路已经具备 macOS app、ESP32-S3 固件、BLE 状态同步、app 内固件烧录和 Sparkle 自动更新闭环。

当前 release 包内置：

- notarized macOS app。
- 面向 Waveshare `ESP32-S3-LCD-3.16` 的预编译固件。
- 固件烧录 helper 和 bundled Python runtime。
- `esptool` 依赖，以及对应的 open-source notices、source offer 和 source archive。
- Sparkle 自动更新入口，Apple Silicon 默认通过 GitHub latest release `appcast.xml` 检查稳定版本，Intel 版本使用 `appcast-x86_64.xml`。

发布流程已经完成 Developer ID 签名、notarization、release checklist、open-source notices、source offer、Sparkle appcast 和双架构产物检查；`v0.1.2` release 已分别发布 `arm64` 和 `x86_64` notarized zip，以匹配 Apple Silicon 和 Intel Mac 的 bundled Python runtime。`v0.1.1` 下载包已覆盖启动 app、从旧版通过默认 stable feed 更新、通过 USB 烧录 ESP32-S3 固件、BLE 重连和读取设备 health 的真实用户路径验证。

## 硬件

源码当前支持两类目标设备：

- Waveshare `ESP32-S3-LCD-3.16`：ESP32-S3、8 MB PSRAM、320 x 820 ST7701 RGB LCD。
- `ESP32-S3-DevKitC-1 N16R8`：GPIO4 / GPIO5 / GPIO6 分别连接红 / 黄 / 绿 LED，每路串联 330Ω 限流电阻。
- USB 用于固件烧录
- BLE 用于状态同步

当前公开 `v0.1.2` release 仍只内置 LCD 固件；三色灯和双固件选择属于下一版待发布能力。

硬件事实和官方资料入口见 [docs/hardware.md](docs/hardware.md)。

## 安装试用

普通测试用户可以直接使用 GitHub release 包，不需要从源码构建固件：

1. 从 [GitHub Releases](https://github.com/miclle/vibe-light/releases) 下载与你的 Mac 匹配的最新发布包：新双平台 release 中 Apple Silicon 使用 `VibeLightApp-*-arm64-notarized.zip`，Intel 使用 `VibeLightApp-*-x86_64-notarized.zip`；旧 release 若只有 `VibeLightApp-*-notarized.zip`，则使用该单包。
2. 用 Finder 或 Archive Utility 解压 zip；如果使用命令行，建议用 `ditto -x -k`。
3. 打开 `VibeLightApp.app`。
4. 用 USB 数据线连接 ESP32-S3 开发板。
5. 在 app 的固件烧录页面读取芯片，并写入内置固件。
6. 烧录完成后按需点按 `RST`，再在 app 中连接 `VibeLight-S3`。
7. 在 app 中安装 Codex / Claude hooks，然后正常使用你的 AI 编程工具。

内置烧录路径不要求用户安装 ESP-IDF、`idf.py`、Homebrew `esptool` 或本地 Python 环境。
后续稳定版本会通过 app 菜单中的“检查更新...”和后台自动检查发现新 release。

## macOS App

桌面端位于 [projects/macos/desktop](projects/macos/desktop)，使用 SwiftPM、SwiftUI 和 CoreBluetooth。

当前包含五个主要界面：

- 通用：查看当前硬件显示状态、最近事件桥接状态、手动调试状态和基础偏好。
- 智能体安装：安装或卸载 Codex / Claude 的 Vibe Light hooks。
- 硬件设备：保持扫描并同时连接多台 Vibe Light 设备，向所有设备发送状态包、读取各设备 health packet，并发送显示演示包。
- 固件烧录：选择 LCD 或三色灯目标，引导用户完成 USB 芯片读取、固件写入、重启、BLE 重连和健康状态验证。
- 事件：查看本机采集到的 hook 事件和诊断信息。

Hook CLI 会保持安静：它从 stdin 读取 JSON，追加写入 `~/Library/Application Support/VibeLight/events.jsonl`；失败时只写 stderr，并以 fail-open 方式退出，避免影响 Codex / Claude 原有工作流。已安装 Vibe Light 管理的 hook 时，应用升级后会在下次启动自动同步新的内置 hook，不需要先卸载再安装。

## ESP32-S3 固件

LCD 固件位于 [projects/esp32](projects/esp32)，三色灯固件位于 [projects/esp32-led](projects/esp32-led)，共享协议组件位于 `projects/esp32-common/vibe_protocol`。两套固件使用相同 GATT UUID 和 `StatusPacket`：

- 以 `VibeLight-S3` 名称广播 BLE Peripheral。
- 接收 macOS app 写入的紧凑 UTF-8 JSON `StatusPacket`。
- 返回包含 uptime、连接状态、最近显示状态、heap、render tick、背光状态和最近解析错误的 health packet。
- 使用轻量 framebuffer renderer 直接驱动 Waveshare LCD。
- 同时兼容当前 `v: 2` 多任务状态包和旧的 `v: 1` 单状态包。
- 三色灯固件以 `VibeLight-LED` 广播；没有 Agent 状态时按红 5 秒、绿 5 秒、黄 2 秒循环模拟交通信号灯，Agent 状态出现后优先用红灯表示告警、黄灯表示执行中、绿灯表示等待人工或最近完成，状态结束后继续当前交通灯相位。对应 Agent 条件存在时以 1 秒周期慢闪，多个条件同时存在时同步闪烁。

协议、状态模型和跨端职责见 [docs/architecture.md](docs/architecture.md)。固件细节见 [projects/esp32/README.md](projects/esp32/README.md)。

## 从源码构建

首次搭建开发环境：

```bash
make check-env
make setup
```

`make setup` 可以交互式安装缺失的 Homebrew 依赖，并在默认路径 `~/esp/esp-idf` 下安装 ESP-IDF。国内网络下载 ESP-IDF 较慢时，可以使用：

```bash
script/setup_env.sh --install --china-mirror
```

构建、测试并启动 macOS app：

```bash
make desktop-build
make desktop-test
make desktop-run
```

运行固件 host-side 测试和屏幕预览生成：

```bash
make esp32-test
make esp32-preview
make esp32-led-test
```

本机有 ESP-IDF 时，从源码构建并烧录固件：

```bash
make esp32-build
make esp32-flash ESP32_PORT=/dev/cu.usbmodemXXXX
make esp32-led-build
make esp32-led-flash-only ESP32_PORT=/dev/cu.usbmodemXXXX
```

只有手动运行 `idf.py` 时，才需要进入已激活的 ESP-IDF shell：

```bash
make idf-shell
```

## 验证

快速验证 desktop 逻辑、协议解析、固件 host-side 测试、屏幕预览和 whitespace：

```bash
make quick
```

包含 ESP32 固件构建的完整验证：

```bash
make verify
```

文档-only 改动至少运行：

```bash
make docs-check
```

固件屏幕预览会生成到：

```text
/tmp/vibe-maze-preview.png
/tmp/vibe-screen-preview.png
```

## 项目结构

```text
projects/
  macos/
    desktop/   # macOS SwiftPM app、Hook CLI、BLE client、测试
  esp32/       # Waveshare LCD 固件和 host-side 测试
  esp32-led/   # ESP32-S3-DevKitC-1 三色灯固件和测试
  esp32-common/# 两套固件共享的 BLE 协议 parser / health formatter
docs/          # 架构、硬件、固件烧录和发布记录
script/        # 环境搭建、验证、打包和发布脚本
```

## 文档

- [架构设计](docs/architecture.md)
- [硬件记录](docs/hardware.md)
- [固件烧录流程](docs/desktop-firmware-flashing.md)
- [ESP32 固件说明](projects/esp32/README.md)
- [路线图和验证记录](TODO.md)
- [Agent 工作指南](AGENTS.md)

## License

Vibe Light 自有源码使用 [Vibe Light Non-Commercial Source License](LICENSE)。第三方组件继续遵循各自的上游许可证。
