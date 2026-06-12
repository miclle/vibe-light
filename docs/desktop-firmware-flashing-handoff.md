# Desktop Firmware Flashing Handoff

本文是 macOS app 内固件烧录能力的交接说明，面向下一位继续推进发布闭环的人。主设计文档见 `docs/desktop-firmware-flashing.md`，当前状态和优先级也同步记录在 `TODO.md`。

## 目标

让普通用户只安装 Vibe Light macOS desktop app，通过 USB 连接 Waveshare `ESP32-S3-LCD-3.16` 后，在应用内完成 ESP32-S3 固件烧录。用户不需要安装 ESP-IDF、执行 `idf.py flash` 或理解固件工程目录。

## 当前结论

macOS app 内烧录的 MVP 已经完成并推送到 `main`。当前已经具备：

- desktop “硬件设备”页中的“固件烧录”入口。
- app resource 内置固件包 `FirmwareBundle`。
- 固件 manifest 解析、offset 排序和 SHA-256 完整性校验。
- macOS 常见 ESP32 串口枚举和手动选择。
- 独立 helper `vibe-light-firmware-flasher` 调用 `esptool write_flash`。
- `esptool` Python 依赖 vendoring 到 app resource。
- 烧录成功后自动启动 BLE 扫描，并可重新连接 `VibeLight-S3` 读取 health packet。

剩余风险主要集中在发布分发层：签名、notarization、sandbox/entitlement、Python runtime 打包策略、第三方许可证材料和失败恢复体验。

## 已完成更改

关键提交已经在 `main`：

- `7da431e feat(macos): 添加应用内固件烧录入口`
- `6c107aa feat(macos): 打包固件烧录 helper`
- `a637c98 fix(macos): 复制 app 资源包`
- `bd8ccc1 docs: 记录固件烧录实机验证`
- `8a3e309 docs: 记录固件烧录 UI 验证`
- `e8adc38 fix(macos): 修复固件烧录 helper 执行风险`

关键文件：

- `projects/esp32/tools/package_firmware_bundle.py`
  - 从 ESP-IDF build 产物和 `flasher_args.json` 生成 app resource 固件包。
  - 输出 `FirmwareBundle/manifest.json`、bootloader、partition table 和 app bin。
  - manifest 记录芯片、硬件、flash 参数、offset、SHA-256、固件版本和最低 desktop 版本。
- `projects/esp32/tools/package_firmware_tools.py`
  - 把 `esptool` 及 Python 依赖 vendor 到 `Resources/FirmwareTools/python-packages/`。
- `projects/macos/desktop/Sources/VibeLightCore/FirmwareFlashing.swift`
  - 解析 manifest。
  - 校验固件文件 SHA-256。
  - 枚举候选串口。
  - 生成烧录命令。
  - 运行 helper 并收集 stdout/stderr。
- `projects/macos/desktop/Sources/VibeLightApp/Models/VibeLightAppModel.swift`
  - 加载内置固件包。
  - 刷新串口。
  - 执行烧录。
  - 维护 UI 状态和日志。
  - 成功后触发 BLE 扫描。
- `projects/macos/desktop/Sources/VibeLightApp/Views/HardwareDevicesPane.swift`
  - 增加“固件烧录”区域。
  - 展示固件版本、目标硬件、串口选择、刷新和烧录状态。
- `projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareTools/vibe-light-firmware-flasher`
  - app 内置 shell helper。
  - 优先使用同目录 vendored `python-packages`，再 fallback 到本机 `esptool` / `esptool.py`。
  - 已修复旧 Homebrew `esptool` 抢先命中导致 vendored 依赖被绕过的风险。
- `projects/macos/desktop/Package.swift`
  - 把 `FirmwareBundle` 和 `FirmwareTools` 作为目录资源复制。
  - 避免 `.process("Resources")` 处理 Python 包时出现重复资源 basename 问题。
- `script/build_and_run.sh`
  - 构建 dev app 后，把 SwiftPM 生成的 `VibeLight_VibeLightApp.bundle` 复制进 `dist/VibeLightApp.app`。
  - 确保 dev app 能找到固件包和 helper resource。
- `projects/macos/desktop/Tests/VibeLightCoreTests/VibeLightCoreTests.swift`
  - 覆盖 manifest decode、checksum、命令生成、串口匹配、helper 可执行性、vendored 依赖优先级和 process runner 大输出场景。

## 已完成验证

自动化验证：

- `make quick` 通过。
  - Swift 测试通过。
  - ESP32 host-side C 测试通过。
  - 预览图生成通过。
  - whitespace 检查通过。
- `make docs-check` 通过。
- `git diff --check` 通过。
- 收窄 PATH 验证 helper 不依赖 Homebrew `esptool`：

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareTools/vibe-light-firmware-flasher --help
```

该命令输出过 `esptool.py v4.11.0`，证明 vendored `python-packages` 路径可工作。

实机验证：

- 时间：2026-06-12。
- 端口：`/dev/cu.usbmodem2101`。
- 目标芯片：`ESP32-S3 (QFN56)`。
- MAC：`1c:db:d4:7b:3f:cc`。
- 固件 boot log app version：`524c46d`。
- 本地 app resource manifest：`dev-test / 27040bf`。

已完成两类实机烟测：

1. 直接 helper 路径：
   - 使用 `dist/VibeLightApp.app` 中的 resource helper。
   - 写入 bootloader、partition table 和 app。
   - 三段写入均 hash verified。
   - reset 后串口确认 `LCD initialized`、`advertising as VibeLight-S3`、Central connected 和连续 `v:2` 状态写入。
   - 收窄 PATH 后，使用 vendored `esptool.py v4.11.0` 再次烧录成功。

2. SwiftUI app 路径：
   - 通过 `script/build_and_run.sh run` 启动 app。
   - 在“硬件设备”页看到 `固件烧录 dev-test / esp32s3 / 16MB`。
   - 选择 USB `/dev/cu.usbmodem2101` 并点击“烧录固件”。
   - UI log 显示 esptool 写入和 hash verified。
   - 成功后 app 自动扫描 BLE，重新连接 `VibeLight-S3`。
   - health packet UI 展示 runtime、connected、running、backlight on、heap 余量和 render tick。

## 未完成事项

1. 发布签名和 notarization 未验证
   - 尚未验证 Developer ID signed app。
   - 尚未验证 notarized app。
   - 尚未验证 helper 在签名 / notarization 后是否能正常执行。
   - 尚未验证 signed/notarized app 下串口访问是否需要额外 entitlement。

2. Python runtime 策略未定
   - 当前 helper 可以使用系统 `/usr/bin/python3` 加 vendored Python packages。
   - 还没有决定是否随 app bundle 内置完整 Python runtime。
   - 第一版如果继续使用系统 Python，需要在 clean macOS 上验证，并明确最低系统要求。

3. 第三方许可证材料未整理
   - `package_firmware_tools.py` 已能根据 vendored Python package metadata 生成 `FirmwareTools/THIRD_PARTY_NOTICES.md`。
   - 仍需在完整 vendor 成功后审阅生成内容，确认 `esptool` 和间接依赖的许可证材料符合发布要求。

4. 失败恢复体验仍偏基础
   - UI 当前记录 helper 日志，但没有把 esptool 进度解析成 progress bar。
   - 常见失败已经有明确提示：下载模式、串口占用、写入校验失败、非 ESP32-S3 设备和 helper runtime 缺失。
   - 当前依赖 `--chip esp32s3` 和 esptool 芯片校验拒绝非 S3；app 还没有单独 pre-read 芯片信息并在写入前展示确认。

5. 发布自动化未串起来
   - `script/prepare_desktop_firmware_release.sh` 已串起 ESP32 构建、固件包生成、工具 vendoring 和 helper 收窄 PATH 验证。
   - 还没有继续串起 desktop build、签名、notarization 和实机 smoke checklist。
   - 当前 `manifest.json` 版本仍以 `dev-test` / 本地 commit 为主，发布前需要明确 release version 和 commit 追踪规则。

## 建议下一步

推荐按以下顺序继续：

1. 先决定 Python runtime 策略
   - 方案 A：第一版继续使用系统 `/usr/bin/python3` + vendored packages。最快，但必须 clean macOS 验证。
   - 方案 B：随 app bundle 内置完整 Python runtime。体积更大，但发布可控性更强。
   - 方案 C：后续改为 Swift / Rust / C 原生烧录实现。长期更干净，但不是当前最快发布路径。

2. 补齐 license / notice
   - 完整运行 `package_firmware_tools.py --clean`。
   - 审阅生成的 `FirmwareTools/THIRD_PARTY_NOTICES.md`，必要时补充上游许可证全文或发布说明。

3. 做 signed Developer ID app 验证
   - 先用 Developer ID 路线验证 app bundle、helper、串口访问和 BLE 扫描。
   - 如果 Developer ID 路线稳定，再评估 App Store sandbox 可行性。

4. 建立 release 构建脚本
   - 基于 `script/prepare_desktop_firmware_release.sh` 继续串接 desktop build、签名、notarization 和 smoke test。
   - 每次 release 记录固件 version、build commit、desktop version、端口、目标芯片和验证结果。

5. 改进 UI 失败恢复
   - 解析 esptool 输出，显示 stage/progress。
   - 保持 download mode、串口占用、checksum mismatch、非 ESP32-S3 设备和 helper runtime 缺失提示的测试覆盖。
   - 烧录前可增加芯片读取和硬件确认。

## 常用命令

生成固件包和工具包：

```bash
make esp32-build
script/prepare_desktop_firmware_release.sh --version dev --minimum-desktop-version dev
```

构建和运行 dev app：

```bash
script/build_and_run.sh --verify
script/build_and_run.sh run
```

验证 helper vendored 依赖路径：

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareTools/vibe-light-firmware-flasher --help
```

仓库快速验证：

```bash
make quick
```

文档验证：

```bash
make docs-check
git diff --check
```

## 接手检查清单

接手后建议先做这几步：

1. `git status --short --branch` 确认工作区状态。
2. 阅读 `docs/desktop-firmware-flashing.md` 和本文。
3. 运行 `make quick`，确认本地基线仍通过。
4. 运行 helper `--help` 的收窄 PATH 验证，确认 vendored path 没被本机环境掩盖。
5. 如果手边有设备，启动 `script/build_and_run.sh run`，在“硬件设备”页复测一次 UI 烧录闭环。
6. 开始处理 Python runtime、签名/notarization 和 license/notice 三个发布阻塞点。
