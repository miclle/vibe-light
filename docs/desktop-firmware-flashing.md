# macOS App Integrated Firmware Flashing

本文记录 macOS desktop 应用内集成 ESP32-S3 固件烧录能力的实现路径、当前落地状态和发布前验证重点。

## 目标

普通用户只需要下载安装 Vibe Light desktop 应用，通过 USB 连接 Waveshare `ESP32-S3-LCD-3.16`，就可以在应用内完成固件烧录。用户不需要安装 ESP-IDF、配置 `idf.py` 或理解固件工程目录，从而降低首次上手门槛。

## 当前基础

当前仓库已经具备实现这项能力的主要前置条件：

- 固件工程位于 `projects/esp32`，目标芯片和硬件已经稳定为 ESP32-S3 / Waveshare `ESP32-S3-LCD-3.16`。
- 开发者烧录脚本 `projects/esp32/tools/flash_firmware.sh` 已经封装端口、波特率、占用检测和 `idf.py flash` 调用，但它仍依赖本机 ESP-IDF。
- ESP-IDF 构建产物会生成 `build/flasher_args.json`，其中已经包含目标芯片、flash mode、flash size、flash freq、写入 offset 和需要写入的 bin 文件。
- 当前固件烧录需要的核心产物是：
  - `bootloader/bootloader.bin` at `0x0`
  - `partition_table/partition-table.bin` at `0x8000`
  - `vibe_light_esp32.bin` at `0x10000`
- macOS app 已经有“硬件设备”页，包含 BLE 扫描、连接、状态写入、健康读取和演示包发送能力；固件烧录现在作为独立侧边栏入口，复用同一套 BLE 扫描 / 重连能力完成烧录后的验证。

## 当前实现

当前已经采用“desktop 应用烧录预编译固件”的路线，而不是在用户机器上安装或内置完整 ESP-IDF。

发布流程提前构建并签名一份固件包，desktop app 随包携带该固件包，运行时只负责通过串口把预编译二进制写入设备 flash。已落地的代码边界如下：

- `projects/esp32/tools/package_firmware_bundle.py`：从 `projects/esp32/build/flasher_args.json` 和 bin 产物生成 app resource 使用的 `FirmwareBundle`。
- `projects/esp32/tools/package_firmware_tools.py`：把 `esptool` 及其 Python 依赖 vendor 到 app resource 的 `FirmwareTools/python-packages/`，同时下载 `esptool` 对应源码包并生成 GPL 分发说明。
- `projects/macos/desktop/Sources/VibeLightCore/FirmwareFlashing.swift`：解析 manifest、按 offset 排序写入项、校验每个 bin 的 SHA-256、生成 `esptool chip_id` / `write_flash` 参数、解析芯片读取输出，并枚举 macOS 常见 ESP32 串口。
- `projects/macos/desktop/Sources/VibeLightApp/Models/VibeLightAppModel.swift`：加载内置固件包、刷新串口、先调用 helper 读取芯片信息、确认目标芯片后再允许烧录、记录日志，并在成功后启动 BLE 扫描。
- `projects/macos/desktop/Sources/VibeLightApp/Views/FirmwareFlashPane.swift`：提供独立“固件烧录”侧边栏页面。
- `projects/macos/desktop/Sources/VibeLightApp/Views/FirmwareFlashWizardCard.swift`：提供 step-by-step 向导，覆盖串口选择、刷新、读取芯片、下载模式恢复、烧录、RST 重启、BLE 连接和完成状态。
- `projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareTools/vibe-light-firmware-flasher`：app 内置烧录 helper，接受 `esptool` 兼容参数，优先使用同目录 vendor 的 runtime，开发环境可 fallback 到本机 `esptool`。

2026-06-12 已完成发布形态资源和 UI 路径实机烟测：`dist/VibeLightApp.app` 中的 `FirmwareBundle` 和 `FirmwareTools/vibe-light-firmware-flasher` 可在 `/dev/cu.usbmodem2101` 写入目标 ESP32-S3；默认 PATH 下使用 `esptool.py v4.8.1` 成功，收窄 PATH 到 `/usr/bin:/bin:/usr/sbin:/sbin` 后使用 vendored `python-packages` 的 `esptool.py v4.11.0` 成功。写入均完成 bootloader、partition table 和 app 分区 hash 校验。重启后串口确认 `LCD initialized`、`advertising as VibeLight-S3`、desktop Central connected 和连续 `v:2` 状态写入。同日通过 macOS “硬件设备”页点击“烧录固件”完成一次 UI 路径烧录；UI 展示写入日志和 hash verified，随后自动扫描、重新连接 `VibeLight-S3` 并展示 health packet。

固件包结构：

```text
FirmwareBundle/
  manifest.json
  bootloader.bin
  partition-table.bin
  vibe_light_esp32.bin
```

`manifest.json` 记录：

- 固件版本和构建 commit。
- 目标芯片：`esp32s3`。
- 目标硬件：Waveshare `ESP32-S3-LCD-3.16`。
- flash mode / freq / size。
- offset 到 bin 文件的映射。
- 每个 bin 文件的 SHA-256。
- 最低 desktop app 版本。

生成本地固件包：

```bash
make esp32-build
projects/esp32/tools/package_firmware_bundle.py --version dev --minimum-desktop-version dev
projects/esp32/tools/package_firmware_tools.py --clean
```

生成的 `manifest.json` 和 bin 文件会写入 `projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareBundle/`，`esptool` 依赖会写入 `Resources/FirmwareTools/python-packages/`。工具脚本还会生成 `THIRD_PARTY_NOTICES.md`、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md`，并把 `esptool` 对应源码归档放到 `Resources/FirmwareTools/sources/`。这些生成产物被 `.gitignore` 忽略；发布构建应在构建 app 前执行这些步骤。

2026-06-12 本地已用 PlatformIO portable Python 3.11.7 arm64 runtime 跑通自包含 release-prep：`FirmwareTools/python` 约 105MB，`FirmwareTools/python-packages` 约 37MB，`FirmwareBundle` 约 1MB。第一版 Developer ID 发布路线选定该 portable runtime：PlatformIO 官方集成文档明确给自定义应用提供 Portable Python 3 下载 / 解包路径，当前 runtime 随包 `package.json` 记录 `python-portable 1.31107.0`、`darwin_arm64`、`PSF-2.0` 和 Python/CPython 来源，随包 `LICENSE` 保留 Python Software Foundation License 文本。该验证证明当前脚本和 helper 可以脱离系统 Python / PATH 运行；正式发布时仍要在 checklist 中留存 runtime 版本、license 文件和签名结果。

外部依据：

- PlatformIO custom application integration: <https://docs.platformio.org/en/latest/core/installation/integration.html>
- PlatformIO package manifest / included files: <https://docs.platformio.org/en/latest/core/userguide/pkg/cmd_pack.html>
- SPDX `PSF-2.0`: <https://spdx.org/licenses/PSF-2.0.html>

## macOS 端流程

desktop app 的职责保持独立：

1. 枚举候选串口，例如 `/dev/cu.usbmodem*`、`/dev/cu.wchusbserial*`、`/dev/cu.SLAB_USBtoUART*`。
2. 读取 app bundle 内置的 `FirmwareBundle/manifest.json`。
3. 校验固件包完整性和 SHA-256。
4. 先调用烧录 helper 执行非破坏性 `chip_id`，读取并展示芯片型号和 MAC。
5. 确认读取到的芯片匹配固件目标 `esp32s3` 后，才允许继续执行 `write_flash`。
6. 将状态、日志摘要和失败原因回传给 SwiftUI。
7. 烧录完成后触发 BLE 扫描，用户可在向导中连接 `VibeLight-S3` 并读取 health packet。

UI 位于侧边栏的独立“固件烧录”页面。向导按任务阶段展示当前动作，并保留详细 helper 日志折叠入口：

- 连接 USB：提示用户用数据线连接设备，刷新并选择 macOS 识别到的串口。
- 读取芯片：执行非破坏性 `chip_id`，展示 ESP32-S3 芯片型号和 MAC。
- 进入下载模式：当读取失败且判断为 download mode 问题时，分步提示按住 `BOOT`、点按 `RST`、继续按住约 1 秒、松开 `BOOT` 后重新读取。
- 确认并烧录：显示目标固件版本、硬件型号和 flash 参数，芯片确认前不启用烧录。
- 写入固件：解析 esptool 输出显示实时 stage/progress，提示等待 bootloader、partition table 和 app 分区写入 / hash 校验完成，写入期间不要拔线或按 `RST`。
- 重启设备：烧录成功后提示只点按 `RST` 正常启动；如果屏幕没有画面，可再点按一次 `RST`，不要按住 `BOOT`。
- 连接 VibeLight：继续扫描 BLE，发现 `VibeLight-S3` 后可直接连接并读取 health packet。
- 完成：展示健康状态摘要，并保留“开始新的烧录”和刷新健康状态入口。

## 烧录工具选择

最小可行实现复用 Espressif `esptool` 的 `write_flash` 能力。`esptool` 支持按 offset 写入多个二进制文件，正好匹配当前 `flasher_args.json` 的信息。

当前 app 会优先查找 app resource 中的 `FirmwareTools/vibe-light-firmware-flasher`，该 helper 接受 `esptool` 兼容参数。发布路线改为内置完整 Python runtime：`FirmwareTools/python/bin/python3` 加 `FirmwareTools/python-packages/` 中的 `esptool` 依赖。发布验证时使用 strict 模式，禁止 fallback 到系统 Python、Homebrew `esptool` 或用户 PATH。开发环境仍可 fallback 到本机常见的 `python3` / `esptool` 路径，便于验证 UI 和参数生成。

发布前仍需要重点评估：

- `esptool` 的 GPLv2+ 分发材料是否已随包生成并进入 release notes：`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md`、GPL license 文件和 `sources/esptool-<version>.tar.gz`。
- 内置 Python runtime 的体积、架构和签名结果是否符合当次发布目标。
- 独立 helper tool 的签名、权限和日志隔离。
- 是否需要未来替换为更小的原生 Swift / C / Rust 烧录实现。

第一版已经把烧录能力封装在独立 helper 边界后面，desktop app 只通过受控参数启动 helper 并读取输出。这样主应用 UI、BLE 逻辑和串口烧录边界清晰，后续替换底层烧录实现也更容易。

## 签名和权限风险

macOS 分发前必须实测签名、notarization 和 sandbox 行为。

当前仓库新增 `script/package_desktop_release.sh` 作为本地 Developer ID 发布验证入口。它会复用 `script/build_and_run.sh --package` 生成 `dist/VibeLightApp.app`，递归查找 app bundle 内的 Mach-O 文件并逐个用 hardened runtime + timestamp 签名，然后签 resource bundle 和主 app bundle，最后执行 `codesign --verify`、生成 zip，并在未 notarize 时把 `spctl` 结果作为提示而不是硬失败。

2026-06-12 已在本机使用 `Developer ID Application: Miclle Zheng (6UG7DDAY6C)` 跑通本地签名验证。脚本签名并验证了 83 个 nested Mach-O 文件，包括 app 主程序、`vibe-light-hook`、内置 Python runtime、`lib-dynload` 扩展和 vendored wheel 中的 `.so`；主 app 签名显示 Developer ID authority、Team ID `6UG7DDAY6C`、hardened runtime、timestamp 和 sealed resources。签名后的 helper 在收窄 PATH + strict 模式下能从 `Contents/Resources/VibeLight_VibeLightApp.bundle/FirmwareTools/` 加载 bundled `esptool.py v4.11.0`。未 notarize 时 `spctl` 结果为 `Unnotarized Developer ID`，这是下一步 notarization 要解决的 Gatekeeper 状态。

本地签名验证最小命令：

```bash
SIGNING_IDENTITY="Developer ID Application: Miclle Zheng (6UG7DDAY6C)" \
  script/package_desktop_release.sh
```

如果已经在钥匙串里保存了 notarytool profile，可以继续跑 notarization 和 staple：

```bash
SIGNING_IDENTITY="Developer ID Application: Miclle Zheng (6UG7DDAY6C)" \
  NOTARYTOOL_PROFILE=vibe-light-notary \
  script/package_desktop_release.sh --notarize
```

如果要把固件资源准备、desktop app 打包签名、可选 notarization、第三方 notice 检查和实机芯片读取记录成一份发布 checklist，可以使用：

```bash
SIGNING_IDENTITY="Developer ID Application: Miclle Zheng (6UG7DDAY6C)" \
  NOTARYTOOL_PROFILE=vibe-light-notary \
  script/desktop_firmware_release_checklist.sh \
  --version <release-version> \
  --minimum-desktop-version <desktop-version> \
  --python-runtime /path/to/python-runtime \
  --require-bundled-python \
  --notarize \
  --chip-port /dev/cu.usbmodem1101
```

脚本会在 `dist/release/` 下写入 markdown checklist，并把 prepare、package 和 chip read 日志放到 `dist/release/logs/`。

第一次在本机配置 profile 时可以使用 App Store Connect API key：

```bash
xcrun notarytool store-credentials vibe-light-notary \
  --key /path/to/AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER_UUID \
  --validate
```

仓库也提供了 `.env.example` 和 Make 入口封装这一步，避免每次手写 `xcrun notarytool` 参数。先复制模板并填入真实值：

```bash
cp .env.example .env
$EDITOR .env
```

然后创建 / 刷新 Keychain profile 并验证：

```bash
make notary-store
make notary-validate
```

恢复 profile 后可以直接运行完整 notarized desktop firmware release checklist：

```bash
make desktop-release-notarized
```

`.env`、`.env.local`、`.env.*.local` 和 `AuthKey_*.p8` 已被 `.gitignore` 忽略；`.env.example` 只保留占位变量，可以提交。

`script/package_desktop_release.sh --notarize` 会在 build/sign 前校验 notarization 凭证；如果没有 `NOTARYTOOL_PROFILE` 或 Apple API key 参数，会在打包前失败并提示配置方式。

2026-06-12 后续已创建并验证 `vibe-light-notary` profile，并跑通完整 notarization：Apple Notary submission `d923ce8c-d4f9-4a03-b26b-008a2f5ec9a4` 返回 `Accepted`，`xcrun stapler validate dist/VibeLightApp.app` 通过，`spctl -a -vv --type execute dist/VibeLightApp.app` 返回 `accepted / source=Notarized Developer ID`，`codesign -dvvv` 显示 `Notarization Ticket=stapled`。签名 + notarized app 内 helper 在收窄 PATH + strict 模式下仍能加载 bundled `esptool.py v4.11.0`，notarized app 可短暂启动。继续用 notarized app bundle 内 helper 对 `/dev/cu.usbmodem1101` 执行非破坏性 `chip_id` 读取，已识别 `ESP32-S3 (QFN56)`、BLE、8MB PSRAM 和目标 MAC。随后在 notarized app UI 点击“烧录固件”，完成三段写入和 hash verification，烧录后 app 扫描到设备、重新连接并读取 health packet。dev app UI 已补齐烧录前芯片确认：读取前“烧录固件”禁用，读取 `/dev/cu.usbmodem1101` 确认 `ESP32-S3 (QFN56)` 和 MAC `1c:db:d4:7b:3f:cc` 后才启用写入入口。

2026-06-13 已在提交 `ffaf09f` 上跑通带 GPL source gate 的完整 release checklist：`script/desktop_firmware_release_checklist.sh --version 2026.06.13-dev-ffaf09f --minimum-desktop-version dev --python-runtime /Users/miclle/.platformio/python3 --require-bundled-python --notarize --chip-port /dev/cu.usbmodem1101`。Apple Notary submission `8c39946b-beab-421b-8b1f-48d9bea0b2c0` 返回 `Accepted`，staple / validate / Gatekeeper 通过，报告写入 `dist/release/desktop-firmware-release-2026.06.13-dev-ffaf09f.md`，notarized zip 写入 `dist/release/VibeLightApp-2026.06.13-dev-ffaf09f-notarized.zip`。报告记录了 `THIRD_PARTY_NOTICES.md`、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md` 和 `sources/esptool-4.11.0.tar.gz`；源码包 SHA-256 为 `496571e4f6e36f7dc9a730dd485c4a9d522c9e7d6bb90ea2fec0a049275fbfad`。已抽查 notarized zip 包含这些 GPL 材料，strict helper 读取 `/dev/cu.usbmodem1101` 识别 `ESP32-S3 (QFN56) (revision v0.2)` 和 MAC `1c:db:d4:7b:3f:cc`。

2026-06-13 已在提交 `98427be` 上重新跑通烧录进度修复后的 dev release：`script/desktop_firmware_release_checklist.sh --version 2026.06.13-dev-98427be --minimum-desktop-version dev --python-runtime /Users/miclle/.platformio/python3 --require-bundled-python --identity "Developer ID Application: Miclle Zheng (6UG7DDAY6C)" --notarize --notarytool-profile vibe-light-notary --chip-port /dev/cu.usbmodem1101`。Apple Notary submission `0fe51533-2c15-493e-809d-07693eb43a2e` 返回 `Accepted`，staple / validate、`syspolicy_check distribution` 和 `codesign --verify --deep --strict` 通过，报告写入 `dist/release/desktop-firmware-release-2026.06.13-dev-98427be.md`，notarized zip 写入 `dist/release/VibeLightApp-2026.06.13-dev-98427be-notarized.zip`。曾发布 GitHub pre-release `v2026.06.13-dev-98427be`，后续已清理，不再作为可用入口；发布后曾从 GitHub asset 重新下载 zip / checklist，SHA-256 分别为 `55c31ef27c5a8957b2393d920bd159c8b42bd0840e13d4949b392ac0cae61bfa` 和 `44a0f3881635d2f769bcee7af4cdf25840c169d9213a4ab990638b418c0a2ea9`，与 release notes / GitHub digest 一致。下载 zip 用 `ditto -x -k` 解压后通过 stapler、distribution policy 和 codesign，manifest 为 `2026.06.13-dev-98427be / 98427be`，GPL 材料和 `sources/esptool-4.11.0.tar.gz` 复核通过；同一下载形态 app 内 strict helper 已完成完整 `write_flash`，三段均 `Hash of data verified`。

继续从 `~/Downloads` 启动下载形态的 `98427be` app 进行完整 UI 试用时，确认 app 可正常打开、读取芯片识别 `ESP32-S3 (QFN56)` / MAC `1c:db:d4:7b:3f:cc`、UI 烧录三段均完成 hash 校验，并可连接 `VibeLight-S3` 刷新健康状态到运行中、背光开启。该试用同时发现一个 UI 进度显示问题：累计日志里早期分区的 `Hash of data verified` 会让 UI 在后续 app 分区仍写入时提前显示 `校验完成 100%`。`68e6244` 已修复该问题，进度解析现在按累计日志中最后出现的 esptool 事件决定当前 stage / percent，并增加 Swift 测试覆盖。`v2026.06.13-dev-98427be` release notes 已标记该已知问题；随后尝试生成本地替换版 notarized pre-release 时，checklist 曾在本机 `vibe-light-notary` Keychain profile 凭证预检处停止，后续已改用 GitHub Actions 内的 Apple API key 临时 notarytool profile 路线解决。

2026-06-14 已通过 GitHub Actions 生成并发布当前可用 pre-release `v2026.06.14-dev-d5dd54a`。workflow run `27482909320` 完整通过：准备 bundled Python runtime、安装 ESP-IDF、导入 Developer ID 证书、创建临时 notarytool profile、运行 notarized release checklist、解压验证 zip、检查 release 日志并上传 GitHub release assets。下载 asset `VibeLightApp-2026.06.14-dev-d5dd54a-notarized.zip` 后，SHA-256 为 `023df16bf7710bae338d9ad03e40a4808d402c9416c2803493d11946f851fd83`；`ditto -x -k` 解压出的 app 通过 `xcrun stapler validate`、`syspolicy_check distribution`、`codesign --verify --deep --strict` 和 strict helper `--help`。下载形态 app 可启动并保持运行，修复了此前 draft `v2026.06.14-dev-08c645b` 暴露的 `Bundle.module` resource bundle 启动崩溃。包内 helper 已对 `/dev/cu.usbmodem1101` 完成 `chip_id` 和完整 `write_flash`，三段均 `Hash of data verified`，用户随后确认该 release 实测正常。

发布清理状态：旧的 `v2026.06.13-dev-ffaf09f`、`v2026.06.13-dev-98427be` 和会启动崩溃的 draft `v2026.06.14-dev-08c645b` 已从 GitHub release/tag 侧清理；当前远端只保留可用 tag `v2026.06.14-dev-d5dd54a`。

同日已对 `dist/release/VibeLightApp-2026.06.13-dev-ffaf09f-notarized.zip` 内的实际文件完成 `esptool` GPL gate 工程合规审阅。审阅确认 `THIRD_PARTY_NOTICES.md`、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md`、GPLv2 license 文件和 `sources/esptool-4.11.0.tar.gz` 均存在，源码包 SHA-256 与 notice 一致，源码包包含 `LICENSE`、`PKG-INFO`、构建配置、`esptool/` 源码和 stub flasher 资源，`PKG-INFO` 标明 `esptool 4.11.0 / GPLv2+`。该 gate 对当前 dev release 可以放行；正式商业发布前仍建议法律 / 合规最终确认。

CI 后续可以复用同一个脚本，但需要额外把 Developer ID Application 证书和私钥导入临时 keychain，再提供 `SIGNING_IDENTITY`。Notarization 可以使用 `NOTARYTOOL_PROFILE`，也可以使用 `APPLE_API_KEY` / `APPLE_API_KEY_PATH`、`APPLE_API_KEY_ID` 和 `APPLE_API_ISSUER`。

2026-06-13 已新增手动触发的 GitHub Actions workflow：`.github/workflows/release-desktop.yml`。该 workflow 在 macOS runner 上安装 ESP-IDF、准备 bundled Python runtime、导入 Developer ID 证书、把 Apple API key 存成临时 `notarytool` profile、运行 `desktop_firmware_release_checklist.sh --notarize`、验证解压后的 notarized app，并创建 GitHub draft / pre-release。仓库需要配置以下 GitHub Secrets：

- `SIGNING_IDENTITY`
- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `APPLE_API_KEY`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER`

CI 可以完成可分发包生成、签名、notarization、staple、Gatekeeper / codesign 验证和 release asset 上传；真实 USB `chip_id`、UI 烧录、BLE 重连和 health packet 仍需要从 GitHub release 下载后在本地 Mac + ESP32-S3 上验收。`v2026.06.14-dev-d5dd54a` 已完成这条本地下载包验收路径。

GitHub Actions runtime 维护状态：`release-desktop.yml` 已升级到 `actions/checkout@v6` 和 `actions/setup-python@v6`，两者上游 `action.yml` 已声明 `node24`。`espressif/install-esp-idf-action` 当前默认分支仍是 `v1`，没有可升级 tag，且上游 `action.yml` 仍声明 `node20`；workflow 已设置 `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` 提前使用 Node 24 runtime，后续仍需关注 Espressif 是否发布原生 Node 24 版本。

2026-06-14 已用 draft 验证版 `v2026.06.14-dev-d3cf90c-node24` 跑通 `release-desktop.yml`：workflow run `27484068864` 完成 ESP-IDF 安装、Developer ID 签名、notarization、archive 验证和 release asset 创建；验证 draft 已删除，远端仍只保留当前可用 tag `v2026.06.14-dev-d5dd54a`。GitHub 仍会提示 `espressif/install-esp-idf-action@v1` 声明 Node.js 20 但被强制运行在 Node.js 24，这是上游 metadata 未更新导致的非阻塞提醒。

需要重点验证：

- 沙盒环境下访问串口设备是否需要 `com.apple.security.device.serial`。
- 直接 USB 访问是否涉及 `com.apple.security.device.usb`。
- helper process 是否继承主 app sandbox，或是否需要单独签名/entitlement。
- App Store 分发是否接受相关 entitlement 和外部设备烧录行为。
- Developer ID 直分发是否比 App Store 更适合第一阶段。

如果 App Store 审核或 sandbox 权限不稳定，第一阶段可以优先选择 Developer ID notarized 分发，把功能做成“连接 USB 后本地烧录”的桌面能力。

## 设备安全和失败恢复

烧录能力要避免误刷和半刷后无法恢复：

- 烧录前读取并展示芯片类型，拒绝非 `ESP32-S3`。
- 固件包 manifest 固定目标硬件和目标芯片。
- 烧录时只写入 app、bootloader 和 partition table，不默认擦除整片 flash，避免无意清除 NVS 中的 high score 等状态。
- 不使用 `--force` 覆盖 secure boot / flash encryption 保护。
- 失败时保留清晰错误原因和重试按钮。
- 烧录成功后通过 BLE 名称和 health packet 做闭环验证。

## 发布前 checklist

1. **helper 打包**
   - 当前已在 `Resources/FirmwareTools/` 放入可签名的 `vibe-light-firmware-flasher` wrapper，并能通过 vendored `python-packages` 加载 `esptool`。
   - `script/prepare_desktop_firmware_release.sh` 已串起固件包生成、`esptool` 依赖 vendoring 和收窄 PATH helper 验证，可作为发布资产准备入口。
   - `projects/esp32/tools/package_firmware_tools.py --python-runtime <path> --require-python-runtime` 可把预备好的独立 Python runtime 复制到 `FirmwareTools/python/`，并验证 `python/bin/python3` 可执行。
   - `VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1` 会让 helper 只使用 bundled Python runtime 和 bundled `esptool`，用于证明发布包不依赖用户系统环境；release-prep 还会用 bundled Python import `esptool`、`pyserial`、`cryptography`、`PyYAML` 和 `cffi`，避免二进制依赖 ABI 问题漏过。
   - `projects/esp32/tools/package_firmware_tools.py` 会从 vendored Python package metadata 生成 `FirmwareTools/THIRD_PARTY_NOTICES.md`，为 GPLv2+ 的 `esptool` 生成 `OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md` 和 `sources/esptool-<version>.tar.gz`，并为缺少独立 license 文件的 `pyserial 3.5` 自动补齐 `LICENSE.txt`，让许可证材料跟实际依赖版本保持一致。
   - 第一版 runtime 来源已选定为 PlatformIO portable Python；正式 release 前按 checklist 完整跑通工具 vendoring，并审阅生成的第三方 notices、GPL source offer 和源码归档。

2. **真实应用闭环验证**
   - 已用 `dist/VibeLightApp.app` resource 通过 USB 烧录目标板，并验证重启、BLE 广播、desktop 连接和状态写入。
   - 已在 SwiftUI 内点击“烧录固件”完成同一路径，并读取 health packet 展示结果。
   - 每次发布前记录实测端口、固件版本、app 版本和 helper 版本。

3. **发布签名**
   - 给固件包增加版本、校验和 release notes。
   - `script/package_desktop_release.sh` 已串接 desktop build、Developer ID signing、nested Mach-O signing、zip 归档和可选 notarization / staple。
   - `script/desktop_firmware_release_checklist.sh` 已把固件资源准备、desktop 打包签名、可选 notarization、third-party notice 检查和目标板 `chip_id` 读取串成 release checklist 报告；notice 检查会要求存在 `esptool` 条目、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md` 和 `sources/esptool-*.tar.*`，启用 `--require-bundled-python` 时也要求存在 `python-portable` 条目。
   - 已用真实 Apple notarization profile 验证 notarized app、staple、Gatekeeper 和 helper strict 模式。
   - 已用 notarized app bundle 内 helper 验证目标板串口握手和芯片读取。
   - 已通过 notarized app UI 验证完整烧录、BLE 扫描 / 连接和 health packet。
   - dev app UI 已补齐烧录前芯片确认，写入入口会等 `chip_id` 读取并匹配目标芯片后才启用。
   - 已用带 GPL source gate 的完整 checklist 验证 Developer ID notarized 包和 `esptool` 源码材料随包存在。
   - 已完成 zip 内实际文件的工程合规审阅，当前 dev release 的 `esptool` GPL gate 可以放行。
   - 已补强 `SOURCE_OFFER.md` fallback wording，明确 `any third party`、费用不超过实际源码分发成本和 GitHub 仓库联系入口；`THIRD_PARTY_NOTICES.md` 会记录补齐后的 `pyserial 3.5` license 文件。
   - GitHub Actions 生成的 `v2026.06.14-dev-d5dd54a` 已通过下载包 hash、stapler、distribution policy、codesign、strict helper、app 启动和真实 USB 烧录验证，并已作为当前唯一可用 pre-release 发布。
   - 正式 release 前选定 release version 和 desktop version，并保存 checklist 结果。

4. **体验优化**
   - UI 已能把常见 helper 失败分类成可执行提示：下载模式、串口占用、写入校验失败、非 ESP32-S3 设备和 helper runtime 缺失。
   - UI 已解析 esptool 输出显示实时 stage/progress，并保留完整 helper 日志。
   - 自动识别最可能的 ESP32-S3 端口。
   - 支持从远端下载新版固件包并校验签名。
   - 增加“恢复出厂固件”或“重新烧录当前版本”入口。

## 结论

该功能已经具备 app 内入口、固件包校验、串口发现、helper 调用和成功后 BLE 扫描的最小闭环。发布流程已经把 Developer ID 签名、notarization、`esptool` GPLv2+ 源码归档、source offer 和第三方 notices 纳入自动生成与 checklist gate；最大的剩余工程风险不在固件本身，而在稳定版发布节奏、正式发布的法律 / 合规审阅和真实发布包的失败恢复回归。
