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
  - 生成非破坏性芯片读取命令并解析 `chip_id` 输出。
  - 生成烧录命令。
  - 运行 helper 并收集 stdout/stderr。
- `projects/macos/desktop/Sources/VibeLightApp/Models/VibeLightAppModel.swift`
  - 加载内置固件包。
  - 刷新串口。
  - 烧录前读取芯片信息并确认目标芯片。
  - 执行烧录。
  - 维护 UI 状态和日志。
  - 成功后触发 BLE 扫描。
- `projects/macos/desktop/Sources/VibeLightApp/Views/HardwareDevicesPane.swift`
  - 增加“固件烧录”区域。
  - 展示固件版本、目标硬件、串口选择、刷新、芯片确认和烧录状态。
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

## 状态与剩余 gate

1. 发布签名、notarization 和烧录前芯片确认已完成验证
   - 已新增 `script/package_desktop_release.sh` 作为本地 Developer ID 签名验证入口，负责 build/stage app、签名 app bundle 内 nested Mach-O、签 resource bundle / 主 app、执行 `codesign --verify` 并生成 zip。
   - 2026-06-12 已用 `Developer ID Application: Miclle Zheng (6UG7DDAY6C)` 跑通本地签名验证：83 个 nested Mach-O 文件完成签名和 `codesign --verify`，主 app 显示 hardened runtime、timestamp、sealed resources 和 Team ID `6UG7DDAY6C`；签名后 helper 在 strict 模式下可加载 bundled `esptool.py v4.11.0`；签名 app 可短暂启动。
   - `script/package_desktop_release.sh --notarize` 已增加 build/sign 前凭证预检，支持 `NOTARYTOOL_PROFILE` 或 App Store Connect API key 参数 / 环境变量。
   - 2026-06-12 已创建 `vibe-light-notary` profile 并跑通 notarization：submission `d923ce8c-d4f9-4a03-b26b-008a2f5ec9a4` 返回 `Accepted`，staple / validate 成功，Gatekeeper 返回 `accepted / source=Notarized Developer ID`，`codesign -dvvv` 显示 `Notarization Ticket=stapled`。
   - 已验证 helper 在签名 + notarized app 中可用：收窄 PATH + strict 模式输出 bundled `esptool.py v4.11.0`。
   - 已验证 notarized app bundle 内 helper 可访问 `/dev/cu.usbmodem1101` 并非破坏性读取 `ESP32-S3 (QFN56)` 芯片信息。
   - 已通过 notarized app UI 点击“烧录固件”完成完整写入：bootloader、partition table 和 app 三段均 hash verified；烧录后 app 扫描到 `VibeLight-S3`，重新连接并读取 health packet。
   - dev app UI 已补齐烧录前芯片确认：读取前“烧录固件”禁用，点击“读取芯片”确认 `ESP32-S3 (QFN56)` 和 MAC 后才启用写入入口。

2. Python runtime 发布路线已确定并完成本地验证
   - 第一版发布路线改为随 app bundle 内置完整 Python runtime，目标是用户只安装 desktop app 即可烧录。
   - `package_firmware_tools.py --python-runtime <path> --require-python-runtime` 已能把预备好的 runtime 复制到 `FirmwareTools/python/` 并验证 `python/bin/python3`。
   - `VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1` 会禁止 helper fallback 到系统 Python、Homebrew `esptool` 或用户 PATH。
   - 2026-06-12 已用本机 PlatformIO portable Python 3.11.7 arm64 候选跑通 `script/prepare_desktop_firmware_release.sh --skip-esp32-build --version dev-test --minimum-desktop-version dev --python-runtime /Users/miclle/.platformio/python3 --require-bundled-python`；strict helper 输出 `esptool.py v4.11.0`，bundled Python import smoke 覆盖 `esptool`、`pyserial`、`cryptography`、`PyYAML` 和 `cffi`。
   - 第一版 runtime 来源选定为 PlatformIO portable Python；当前随包 `package.json` 记录 `python-portable 1.31107.0`、`darwin_arm64`、`PSF-2.0` 和 Python/CPython 来源，随包 `LICENSE` 保留 Python Software Foundation License 文本。
   - signed/notarized app 已验证 runtime、`lib-dynload` 扩展和 vendored wheel `.so` 可被脚本签名并通过 helper strict 模式加载。

3. 第三方许可证材料已生成，正式发布仍需人工审阅
   - `package_firmware_tools.py` 已能根据 vendored Python package metadata 生成 `FirmwareTools/THIRD_PARTY_NOTICES.md`。
   - `script/desktop_firmware_release_checklist.sh` 会检查 `THIRD_PARTY_NOTICES.md` 存在 `esptool` 条目；启用 `--require-bundled-python` 时也会检查 `python-portable` 条目。
   - 正式发布前仍需人工审阅生成内容，确认 `esptool` GPLv2+ 和间接依赖的许可证材料符合发布要求。

4. 失败恢复体验仍偏基础
   - UI 当前记录 helper 日志，但没有把 esptool 进度解析成 progress bar。
   - 常见失败已经有明确提示：下载模式、串口占用、写入校验失败、非 ESP32-S3 设备和 helper runtime 缺失。
   - app 已在写入前单独执行 `chip_id` pre-read 并展示确认，写入入口会等确认后才启用。

5. 发布自动化已有 checklist 入口，正式 release 参数仍需确定
   - `script/prepare_desktop_firmware_release.sh` 已串起 ESP32 构建、固件包生成、工具 vendoring 和 helper 收窄 PATH 验证。
   - `script/desktop_firmware_release_checklist.sh` 已把固件资源准备、desktop app 打包签名、可选 notarization、third-party notice 检查和目标板 `chip_id` 读取串成 markdown checklist，日志写入 `dist/release/logs/`。
   - 当前 `manifest.json` 版本仍以 `dev-test` / 本地 commit 为主，正式 release 前需要明确 release version、desktop version、runtime 来源和 checklist 归档规则。

## 建议下一步

推荐按以下顺序处理正式发布 gate：

1. 跑正式 release checklist
   - 选定 release version 和 desktop version。
   - 用 `script/desktop_firmware_release_checklist.sh --python-runtime <path> --require-bundled-python --notarize --chip-port <port>` 生成自包含资源、签名/notarize app、检查 notice 并记录目标板 `chip_id`。
   - 保留 `dist/release/desktop-firmware-release-<version>.md` 和 `dist/release/logs/` 作为发布证据。

2. 人工审阅 license / notice
   - 审阅生成的 `FirmwareTools/THIRD_PARTY_NOTICES.md`。
   - 重点确认 `esptool` GPLv2+ 和 Python runtime / 间接依赖 notice 是否满足当次分发要求。

3. 继续体验优化
   - 如需要更细的用户反馈，再解析 esptool 输出显示 stage/progress。
   - 如果 Developer ID 路线稳定，再评估 App Store sandbox 可行性。

4. 保持失败恢复测试
   - 保持 download mode、串口占用、checksum mismatch、非 ESP32-S3 设备和 helper runtime 缺失提示的测试覆盖。
   - 烧录前芯片读取和硬件确认已落地，后续继续补进度展示。

## 常用命令

生成固件包和工具包：

```bash
make esp32-build
script/prepare_desktop_firmware_release.sh --version dev --minimum-desktop-version dev
script/prepare_desktop_firmware_release.sh --version dev --minimum-desktop-version dev --python-runtime /path/to/python-runtime --require-bundled-python
script/desktop_firmware_release_checklist.sh --version dev --minimum-desktop-version dev --skip-esp32-build --skip-package
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
