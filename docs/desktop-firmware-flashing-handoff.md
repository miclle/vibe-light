# Desktop Firmware Flashing Handoff

本文是 macOS app 内固件烧录能力的交接说明，面向下一位继续推进发布闭环的人。主设计文档见 `docs/desktop-firmware-flashing.md`，当前状态和优先级也同步记录在 `TODO.md`。

## 目标

让普通用户只安装 Vibe Light macOS desktop app，通过 USB 连接 Waveshare `ESP32-S3-LCD-3.16` 后，在应用内完成 ESP32-S3 固件烧录。用户不需要安装 ESP-IDF、执行 `idf.py flash` 或理解固件工程目录。

## 当前结论

macOS app 内烧录的 MVP 已经完成并推送到 `main`。当前已经具备：

- desktop 侧边栏中的独立“固件烧录”入口。
- app resource 内置固件包 `FirmwareBundle`。
- 固件 manifest 解析、offset 排序和 SHA-256 完整性校验。
- macOS 常见 ESP32 串口枚举和手动选择。
- 独立 helper `vibe-light-firmware-flasher` 调用 `esptool write_flash`。
- `esptool` Python 依赖 vendoring 到 app resource，并生成 GPL source offer / 对应源码归档。
- 烧录成功后自动启动 BLE 扫描，并可重新连接 `VibeLight-S3` 读取 health packet。

工程侧当前可用路径已经落到 GitHub Actions 生成的 Developer ID notarized pre-release。剩余事项主要是观察 pre-release 反馈、准备稳定版 release gate、正式发布法律 / 合规确认、发布自动化维护和失败恢复回归；Python runtime、签名 / notarization 和 GPL source gate 不再是当前阻塞点。

## 已完成更改

关键提交已经在 `main`：

- `7da431e feat(macos): 添加应用内固件烧录入口`
- `6c107aa feat(macos): 打包固件烧录 helper`
- `a637c98 fix(macos): 复制 app 资源包`
- `bd8ccc1 docs: 记录固件烧录实机验证`
- `8a3e309 docs: 记录固件烧录 UI 验证`
- `e8adc38 fix(macos): 修复固件烧录 helper 执行风险`
- `68e6244 fix(macos): 修复烧录进度提前完成`

关键文件：

- `projects/esp32/tools/package_firmware_bundle.py`
  - 从 ESP-IDF build 产物和 `flasher_args.json` 生成 app resource 固件包。
  - 输出 `FirmwareBundle/manifest.json`、bootloader、partition table 和 app bin。
  - manifest 记录芯片、硬件、flash 参数、offset、SHA-256、固件版本和最低 desktop 版本。
- `projects/esp32/tools/package_firmware_tools.py`
  - 把 `esptool` 及 Python 依赖 vendor 到 `Resources/FirmwareTools/python-packages/`。
  - 为 GPLv2+ 的 `esptool` 生成 `OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md` 和 `sources/esptool-<version>.tar.gz`。
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
- `projects/macos/desktop/Sources/VibeLightApp/Views/FirmwareFlashPane.swift`
  - 提供侧边栏独立“固件烧录”页面。
- `projects/macos/desktop/Sources/VibeLightApp/Views/FirmwareFlashWizardCard.swift`
  - 展示固件版本、目标硬件、串口选择、刷新、芯片确认、download mode 恢复、烧录状态、RST 重启和 BLE 连接步骤。
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
   - 在侧边栏打开“固件烧录”页，看到固件版本和目标 `esp32s3`。
   - 选择 USB `/dev/cu.usbmodem2101`，按向导读取芯片并点击“烧录固件”。
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
   - 2026-06-13 已在提交 `ffaf09f` 上跑通带 GPL source gate 的完整 `script/desktop_firmware_release_checklist.sh`：版本 `2026.06.13-dev-ffaf09f`，Apple Notary submission `8c39946b-beab-421b-8b1f-48d9bea0b2c0` 返回 `Accepted`，staple / Gatekeeper 通过，release 报告为 `dist/release/desktop-firmware-release-2026.06.13-dev-ffaf09f.md`，notarized zip 为 `dist/release/VibeLightApp-2026.06.13-dev-ffaf09f-notarized.zip`。
   - 2026-06-13 曾发布 GitHub pre-release `v2026.06.13-dev-ffaf09f`，tag 指向实际构建提交 `ffaf09fec89a13ba26a86f6139255c26d3836d57`；该 release 后续已清理，不再作为可用入口。
   - 2026-06-13 已从 GitHub pre-release 下载 notarized zip 和 checklist 报告回归验证：SHA-256 与 release notes 一致，`ditto -x -k` 解压出的 app 通过 stapler、Gatekeeper 和 codesign，zip 内 GPL 材料复核通过，下载 app 可启动并退出。
   - 同日已用下载 app 完成完整 UI 闭环：手动让目标板进入 ROM download mode 后，UI 读取芯片识别 `ESP32-S3 (QFN56)` / MAC `1c:db:d4:7b:3f:cc`，UI 烧录 bootloader / partition table / app 三段均 hash verified，随后发现并连接 `VibeLight-S3`，健康状态显示运行中、背光开启、heap 约 6.7 MB 和 render tick。
   - 2026-06-13 曾发布后续 GitHub pre-release `v2026.06.13-dev-98427be`，tag 指向 `98427bee72b1a3249f1b022ee794fefd0cd9cabf`，并在 release notes 标明 supersede `v2026.06.13-dev-ffaf09f`；该 release 后续已清理，不再作为可用入口。
   - 2026-06-13 已在 `98427be` 上重新跑通完整 checklist：版本 `2026.06.13-dev-98427be`，Apple Notary submission `0fe51533-2c15-493e-809d-07693eb43a2e` 返回 `Accepted`，staple / validate、`syspolicy_check distribution` 和 `codesign --verify --deep --strict` 通过；release 报告为 `dist/release/desktop-firmware-release-2026.06.13-dev-98427be.md`，notarized zip 为 `dist/release/VibeLightApp-2026.06.13-dev-98427be-notarized.zip`。
   - 已从 GitHub release 重新下载 `98427be` notarized zip 和 checklist：SHA-256 分别为 `55c31ef27c5a8957b2393d920bd159c8b42bd0840e13d4949b392ac0cae61bfa` 和 `44a0f3881635d2f769bcee7af4cdf25840c169d9213a4ab990638b418c0a2ea9`，与 release notes / GitHub digest 一致。下载 zip 用 `ditto -x -k` 解压后通过 stapler、distribution policy 和 codesign，manifest 为 `2026.06.13-dev-98427be / 98427be`，GPL 材料和 `esptool` 源码包 hash 复核通过。
   - 同一下载形态 app 内 strict helper 已对 `/dev/cu.usbmodem1101` 完成完整 `write_flash`，bootloader、partition table 和 app 三段均 `Hash of data verified`，最后 `Hard resetting via RTS pin`。
   - 同日继续从 `~/Downloads` 启动下载形态的 `98427be` app 进行完整 UI 试用：app 可正常打开，读取芯片识别 `ESP32-S3 (QFN56)` / MAC `1c:db:d4:7b:3f:cc`，UI 完成 bootloader、partition table 和 app 三段写入，随后连接 `VibeLight-S3` 并刷新健康状态到运行中、背光开启。
   - 该 UI 试用发现 `98427be` 有一个非烧录正确性问题：累计日志中早期分区的 `Hash of data verified` 可能让 UI 在后续 app 分区仍写入时提前显示 `校验完成 100%`。已在 `68e6244` 修复，解析逻辑现在按累计日志里最后出现的 esptool 事件决定当前阶段 / 百分比，并新增 Swift 测试覆盖。
   - `v2026.06.13-dev-98427be` release notes 已标记该已知问题；该 release 和旧的 `v2026.06.13-dev-ffaf09f` 后续已从 GitHub release/tag 侧清理。
   - 2026-06-13 尝试为 `68e6244` 生成替换版 notarized dev release 时，完整 checklist 在本地 notarization 凭证预检处停止；后续已改用 GitHub Actions 内的 Apple API key 临时 notarytool profile 路线解决。
   - 2026-06-14 已通过 GitHub Actions 发布当前可用 pre-release `v2026.06.14-dev-d5dd54a`：workflow run `27482909320` 完整通过，release URL 为 `https://github.com/miclle/vibe-light/releases/tag/v2026.06.14-dev-d5dd54a`，tag 指向 `d5dd54ab8a25e79232a18fe4e818482e7b6d2cec`。
   - `v2026.06.14-dev-d5dd54a` 下载 zip SHA-256 为 `023df16bf7710bae338d9ad03e40a4808d402c9416c2803493d11946f851fd83`；用 `ditto -x -k` 解压后通过 `xcrun stapler validate`、`syspolicy_check distribution`、`codesign --verify --deep --strict` 和 strict helper `--help`。
   - 该下载形态 app 已验证可启动并保持运行，修复了此前 draft `v2026.06.14-dev-08c645b` 暴露的 `Bundle.module` resource bundle 启动崩溃。
   - 该下载形态 app 内 helper 已对 `/dev/cu.usbmodem1101` 完成 `chip_id` 和完整 `write_flash`，识别 `ESP32-S3 (QFN56)` / MAC `1c:db:d4:7b:3f:cc`，三段均 `Hash of data verified`；用户随后确认 release 实测正常。
   - 会启动崩溃的 draft `v2026.06.14-dev-08c645b` 已删除且无残留 tag；当前远端只保留可用 tag `v2026.06.14-dev-d5dd54a`。
   - 注意不要在发布说明中建议用户用命令行 `unzip` 解压 macOS app bundle；本地验证发现 `unzip` 解出的 app 会出现 sealed resource 校验失败。建议 Finder / Archive Utility 或 `ditto -x -k`。

2. Python runtime 发布路线已确定并完成本地验证
   - 第一版发布路线改为随 app bundle 内置完整 Python runtime，目标是用户只安装 desktop app 即可烧录。
   - `package_firmware_tools.py --python-runtime <path> --require-python-runtime` 已能把预备好的 runtime 复制到 `FirmwareTools/python/` 并验证 `python/bin/python3`。
   - `VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1` 会禁止 helper fallback 到系统 Python、Homebrew `esptool` 或用户 PATH。
   - 2026-06-12 已用本机 PlatformIO portable Python 3.11.7 arm64 候选跑通 `script/prepare_desktop_firmware_release.sh --skip-esp32-build --version dev-test --minimum-desktop-version dev --python-runtime /Users/miclle/.platformio/python3 --require-bundled-python`；strict helper 输出 `esptool.py v4.11.0`，bundled Python import smoke 覆盖 `esptool`、`pyserial`、`cryptography`、`PyYAML` 和 `cffi`。
   - 第一版 runtime 来源选定为 PlatformIO portable Python；当前随包 `package.json` 记录 `python-portable 1.31107.0`、`darwin_arm64`、`PSF-2.0` 和 Python/CPython 来源，随包 `LICENSE` 保留 Python Software Foundation License 文本。
   - signed/notarized app 已验证 runtime、`lib-dynload` 扩展和 vendored wheel `.so` 可被脚本签名并通过 helper strict 模式加载。

3. 第三方许可证材料和 GPL source gate 已自动化，正式发布仍需人工审阅
   - `package_firmware_tools.py` 已能根据 vendored Python package metadata 生成 `FirmwareTools/THIRD_PARTY_NOTICES.md`。
   - `package_firmware_tools.py` 会下载 `esptool` 对应源码归档，生成 `OPEN_SOURCE_NOTICES.md` 和 `SOURCE_OFFER.md`，并记录 GPL license 文件、源码路径和 SHA-256。
   - `script/desktop_firmware_release_checklist.sh` 会检查 `THIRD_PARTY_NOTICES.md` 存在 `esptool` 条目、`OPEN_SOURCE_NOTICES.md` / `SOURCE_OFFER.md` 存在 GPLv2+ 元数据、`sources/esptool-*.tar.*` 存在并把 SHA-256 写入 release 报告；启用 `--require-bundled-python` 时也会检查 `python-portable` 条目。
   - 2026-06-13 完整 checklist 已确认 notarized zip 内包含 `THIRD_PARTY_NOTICES.md`、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md` 和 `sources/esptool-4.11.0.tar.gz`；源码包 SHA-256 为 `496571e4f6e36f7dc9a730dd485c4a9d522c9e7d6bb90ea2fec0a049275fbfad`。
   - 2026-06-13 已完成 zip 内实际文件的工程合规审阅：`esptool` GPL gate 对当前 dev release 可以放行；正式商业发布前仍建议法律 / 合规最终确认。
   - 后续非阻塞优化：把 `SOURCE_OFFER.md` fallback wording 写得更贴近 GPLv2 3(b)，明确 `any third party`、费用不超过实际源码分发成本和稳定联系渠道；补齐 `pyserial 3.5` 等间接依赖的独立 license 文本归档。

4. 固件烧录向导和进度展示已落地
   - 侧边栏已经有独立“固件烧录”入口；“硬件设备”页保留 BLE 发现、连接、health 和演示包，不再混入烧录流程。
   - 固件烧录页使用 step-by-step 向导：连接 USB、读取芯片、按需进入下载模式、确认并烧录、写入固件、RST 重启、BLE 连接和完成状态。
   - 向导会在 download mode 失败时分步提示 `BOOT` / `RST` 操作，并在烧录成功后提示只点按 `RST` 正常启动，避免用户继续按住 `BOOT`。
   - UI 会解析 esptool 输出显示实时 stage/progress，并保留完整 helper 日志。
   - 常见失败已经有明确提示：下载模式、串口占用、写入校验失败、非 ESP32-S3 设备和 helper runtime 缺失。
   - app 已在写入前单独执行 `chip_id` pre-read 并展示确认，写入入口会等确认后才启用。

5. 发布自动化已有 checklist 和 GitHub pre-release 入口
   - `script/prepare_desktop_firmware_release.sh` 已串起 ESP32 构建、固件包生成、工具 vendoring 和 helper 收窄 PATH 验证。
   - `script/desktop_firmware_release_checklist.sh` 已把固件资源准备、desktop app 打包签名、可选 notarization、third-party notice 检查和目标板 `chip_id` 读取串成 markdown checklist，日志写入 `dist/release/logs/`。
   - `.github/workflows/release-desktop.yml` 已提供手动触发的 GitHub draft / pre-release 自动化：在 macOS runner 上构建固件和 app，导入 Developer ID 证书，使用 Apple API key 建立临时 `notarytool` profile，执行 notarized checklist，验证 zip 解压形态，并上传 release assets。
   - 当前 dev pre-release `v2026.06.14-dev-d5dd54a` 已发布并完成下载包实机验证；正式公开 / 稳定 release 前需要明确 stable release version、desktop version、runtime 来源和 checklist 归档规则。
   - 当前 workflow 可用，但 GitHub Actions 已提示 `actions/checkout@v4`、`actions/setup-python@v5` 和 `espressif/install-esp-idf-action@v1` 仍使用 Node.js 20 runtime；后续需要关注上游 Node.js 24 兼容版本并重新跑完整 release workflow。

## 建议下一步

推荐按以下顺序继续推进：

1. 观察 dev pre-release 反馈
   - 当前版本为 `v2026.06.14-dev-d5dd54a`。
   - Release URL：`https://github.com/miclle/vibe-light/releases/tag/v2026.06.14-dev-d5dd54a`。
   - 重点关注下载解压、首次启动、蓝牙授权、USB 串口识别、BOOT/RST 指引、烧录日志感知和 BLE 重连反馈。

2. 准备后续稳定 release gate
   - 正式公开 / 商业发布前完成法律 / 合规最终确认。
   - 选定 stable release version 和 desktop version。
   - 复用 checklist 重新生成并归档正式 release 报告。

3. 继续体验优化
   - 如需要更细的用户反馈，可继续把 progress 拆成 bootloader、partition table 和 app 分区级别的阶段展示。
   - 如果 Developer ID 路线稳定，再评估 App Store sandbox 可行性。

4. 跟进发布自动化维护
   - 关注 GitHub Actions Node.js 20 runtime 弃用提醒，等待上游 action 支持 Node.js 24 后升级并跑完整 release workflow。
   - 保持 `release-desktop.yml` 生成 draft / pre-release 后的下载包本地实机验收流程。

5. 保持失败恢复测试
   - 保持 download mode、串口占用、checksum mismatch、非 ESP32-S3 设备和 helper runtime 缺失提示的测试覆盖。
   - 烧录前芯片读取、硬件确认、step-by-step 向导和 esptool 进度展示已落地，后续继续保持失败恢复覆盖。

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

本地恢复 notarization profile 并运行 notarized release checklist（可选；常规预发布优先走 GitHub Actions workflow）：

```bash
cp .env.example .env
$EDITOR .env
make notary-store
make notary-validate
make desktop-release-notarized
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
5. 如果手边有设备，启动 `script/build_and_run.sh run`，在“固件烧录”页复测一次 UI 烧录闭环。
6. 继续处理当前剩余项：观察 `v2026.06.14-dev-d5dd54a` 反馈、准备稳定版 release gate、跟进 GitHub Actions runtime 升级、维护 GPL/license 材料和失败恢复测试。
