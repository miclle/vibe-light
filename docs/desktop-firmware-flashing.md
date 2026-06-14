# macOS App 固件烧录与发布指南

本文面向维护者和发布执行者，说明如何准备 Vibe Light macOS app 内置固件烧录资源、如何签名和 notarize 发布包、如何验证下载形态 app，以及普通用户在 app 内完成 ESP32-S3 烧录时应走的路径。

目标用户不需要安装 ESP-IDF、`idf.py`、Homebrew `esptool` 或本地 Python。发布包必须自带预编译固件、烧录 helper、bundled Python runtime、`esptool` 依赖、第三方许可证材料和 GPL source offer。

## 当前基线

- 目标硬件：Waveshare `ESP32-S3-LCD-3.16`。
- 固件工程：`projects/esp32`。
- macOS app：`projects/macos/desktop`。
- app 内烧录入口：侧边栏“固件烧录”页面。
- BLE 设备名：`VibeLight-S3`。
- 当前公开 latest release：`v0.1.1`，tag 指向 `2dee78b70fcdc43bd82f4eac64fe02b49804e882`。
- 当前 release assets：`VibeLightApp-0.1.1-notarized.zip`、`desktop-firmware-release-0.1.1.md` 和 `appcast.xml`。后续 release workflow 会生成 `VibeLightApp-<version>-arm64-notarized.zip`、`VibeLightApp-<version>-x86_64-notarized.zip`、对应架构的 checklist 报告，以及 `appcast.xml` / `appcast-x86_64.xml`。
- `v0.1.1` 已验证 GitHub latest appcast 可匿名下载，Sparkle stable feed 可从旧版更新到 `0.1.1`，下载包可启动并完成 USB 固件烧录和 BLE 重连。历史 `v0.1.0` checklist 已通过固件资源、desktop app、bundle icon、third-party notices、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md` 和 `sources/esptool-4.11.0.tar.gz` 检查，但该 checklist 未提供 `--chip-port`，所以只能作为无设备 CI gate 记录。

## 用户烧录流程

发布包里的用户路径应保持简单：

1. 从 GitHub Releases 下载匹配当前 Mac 架构的最新 zip：新双平台 release 中 Apple Silicon 使用 `VibeLightApp-*-arm64-notarized.zip`，Intel 使用 `VibeLightApp-*-x86_64-notarized.zip`；旧 release 若只有 `VibeLightApp-*-notarized.zip`，则使用该单包。
2. 用 Finder 或 Archive Utility 解压；命令行解压建议用 `ditto -x -k`，不要优先用 `unzip`。
3. 打开 `VibeLightApp.app`。
4. 用 USB 数据线连接 Waveshare `ESP32-S3-LCD-3.16`。
5. 进入“固件烧录”页面，刷新并选择串口。
6. 点击“读取芯片”，确认识别到 `ESP32-S3` 和 MAC 后再继续。
7. 点击烧录，等待 bootloader、partition table 和 app firmware 三段写入与 hash 校验完成。
8. 烧录成功后按提示点按 `RST` 正常启动，不要按住 `BOOT`。
9. 在 app 中连接 `VibeLight-S3` 并读取 health packet。

如果读取芯片失败且 app 判断需要进入下载模式，按住 `BOOT`，点按 `RST`，继续按住约 1 秒后松开 `BOOT`，再重新读取芯片。

## 资源结构

发布包内 app resource 需要包含：

```text
FirmwareBundle/
  manifest.json
  bootloader.bin
  partition-table.bin
  vibe_light_esp32.bin

FirmwareTools/
  vibe-light-firmware-flasher
  python/
  python-packages/
  THIRD_PARTY_NOTICES.md
  OPEN_SOURCE_NOTICES.md
  SOURCE_OFFER.md
  sources/esptool-<version>.tar.gz
```

`FirmwareBundle/manifest.json` 必须记录：

- 固件版本和构建 commit。
- 目标芯片 `esp32s3`。
- 目标硬件 Waveshare `ESP32-S3-LCD-3.16`。
- flash mode、freq、size。
- 每个 bin 文件的 offset、文件名和 SHA-256。
- 最低兼容 desktop app 版本。

ESP32 当前写入项来自 `projects/esp32/build/flasher_args.json`：

- `bootloader/bootloader.bin` at `0x0`
- `partition_table/partition-table.bin` at `0x8000`
- `vibe_light_esp32.bin` at `0x10000`

## 本地准备固件资源

准备 release 资源的推荐入口是：

```bash
script/prepare_desktop_firmware_release.sh \
  --version <release-version> \
  --minimum-desktop-version <desktop-version> \
  --python-runtime /path/to/python-runtime \
  --require-bundled-python
```

如果只想复用现有 `projects/esp32/build` 产物：

```bash
script/prepare_desktop_firmware_release.sh \
  --version <release-version> \
  --minimum-desktop-version <desktop-version> \
  --python-runtime /path/to/python-runtime \
  --require-bundled-python \
  --skip-esp32-build
```

这个脚本会：

1. 构建 ESP32 固件，除非传入 `--skip-esp32-build`。
2. 调用 `projects/esp32/tools/package_firmware_bundle.py` 生成 `FirmwareBundle`。
3. 调用 `projects/esp32/tools/package_firmware_tools.py --clean` vendor `esptool` 和 Python 依赖。
4. 复制 `--python-runtime` 到 `FirmwareTools/python/`。
5. 在收窄 PATH 下运行 helper `--help`，验证不依赖用户 PATH。
6. 在 `--require-bundled-python` 下额外 import `esptool`、`intelhex`、`serial` 和 `yaml`。

只做开发验证时也可以拆开运行：

```bash
make esp32-build
projects/esp32/tools/package_firmware_bundle.py --version dev --minimum-desktop-version dev
projects/esp32/tools/package_firmware_tools.py --clean
```

## 本地签名和 notarization

本地签名需要 Developer ID Application identity。先确认钥匙串里有可用身份：

```bash
security find-identity -p codesigning -v
```

只做 Developer ID 签名和 zip 归档：

```bash
SIGNING_IDENTITY="Developer ID Application: <name> (<team-id>)" \
SPARKLE_PUBLIC_ED_KEY=<sparkle-public-ed-key> \
  script/package_desktop_release.sh \
  --version <release-version> \
  --arch arm64
```

使用已保存的 notarytool profile 进行 notarization：

```bash
SIGNING_IDENTITY="Developer ID Application: <name> (<team-id>)" \
NOTARYTOOL_PROFILE=<notarytool-profile> \
SPARKLE_PUBLIC_ED_KEY=<sparkle-public-ed-key> \
  script/package_desktop_release.sh \
  --version <release-version> \
  --arch arm64 \
  --notarize
```

也可以用 App Store Connect API key 参数：

```bash
SIGNING_IDENTITY="Developer ID Application: <name> (<team-id>)" \
APPLE_API_KEY_PATH=/path/to/AuthKey_KEYID.p8 \
APPLE_API_KEY_ID=KEYID \
APPLE_API_ISSUER=ISSUER_UUID \
SPARKLE_PUBLIC_ED_KEY=<sparkle-public-ed-key> \
  script/package_desktop_release.sh \
  --version <release-version> \
  --arch arm64 \
  --notarize
```

本地 Intel 产物使用 `--arch x86_64`，并需要从 Intel Mac 或 Intel runner 提供匹配的 bundled Python runtime。不要把 arm64 Python runtime 复制进 x86_64 发布包。

`SPARKLE_PUBLIC_ED_KEY` 是 Sparkle EdDSA 公钥，会写入 app `Info.plist` 的 `SUPublicEDKey`。私钥不要写入仓库；本地生成 appcast 时可通过 `SPARKLE_PRIVATE_KEY` 环境变量传给 `script/generate_desktop_appcast.sh`，CI 则从 GitHub secret 注入。

`script/package_desktop_release.sh` 会：

- 构建 `dist/VibeLightApp.app`，除非传入 `--skip-build`。
- 写入 `CFBundleShortVersionString`、`CFBundleVersion`、`SUFeedURL`、`SUPublicEDKey` 和 `SUEnableAutomaticChecks`。
- 清理 app bundle xattrs。
- 对 app bundle 内 nested Mach-O 逐个签名。
- 签 resource bundle 和主 app bundle。
- 运行 `codesign --verify --deep --strict`。
- 在传入 `--arch` 时运行 `script/verify_desktop_release_arch.sh`，确认 bundle 内所有 Mach-O 都包含目标架构 slice。
- 生成 `dist/release/VibeLightApp-<version>-<arch>.zip`；未传 `--arch` 时仍生成旧式 `VibeLightApp-<version>.zip`。
- 在 `--notarize` 下提交 notarytool、等待结果、staple ticket、验证 Gatekeeper，并生成 `VibeLightApp-<version>-<arch>-notarized.zip`。

生成 Sparkle appcast：

```bash
SPARKLE_PRIVATE_KEY=<sparkle-private-ed-key> \
  script/generate_desktop_appcast.sh \
  --version <release-version> \
  --archive dist/release/VibeLightApp-<release-version>-arm64-notarized.zip \
  --release-notes dist/release/desktop-firmware-release-<release-version>-arm64.md \
  --download-url-prefix https://github.com/miclle/vibe-light/releases/download/v<release-version>/ \
  --output dist/release/appcast.xml
```

Intel appcast 使用相同命令，但 `--archive` 指向 `VibeLightApp-<release-version>-x86_64-notarized.zip`，`--release-notes` 指向 `desktop-firmware-release-<release-version>-x86_64.md`，并把 `--output` 设为 `dist/release/appcast-x86_64.xml`。

Apple Silicon app 内默认 feed URL 是 `https://github.com/miclle/vibe-light/releases/latest/download/appcast.xml`，Intel app 内默认 feed URL 是 `https://github.com/miclle/vibe-light/releases/latest/download/appcast-x86_64.xml`。这两个 URL 都是稳定发布渠道：GitHub 的 `latest` 下载链接只会解析到当前 latest release，不会自动发现 pre-release。做 beta 自动更新验证时，构建旧版测试 app 要用 `VIBE_LIGHT_SPARKLE_FEED_URL` 显式写入目标 tag 的 appcast URL，例如 Apple Silicon 使用 `https://github.com/miclle/vibe-light/releases/download/v<release-version>/appcast.xml`，Intel 使用 `https://github.com/miclle/vibe-light/releases/download/v<release-version>/appcast-x86_64.xml`。

Sparkle feed 必须能被目标 app 匿名下载。GitHub draft release 的 asset 不适合作为真实 Sparkle feed；如果发布流程先创建 draft，需发布为公开 release / pre-release 后再验证更新链路。若 release 已公开但 `appcast.xml` 短时间 404，优先检查 asset 是否真的上传到对应 tag、release 是否仍是 draft，以及 GitHub asset/CDN 是否需要重新上传或等待缓存刷新。

## 一键发布 checklist

推荐发布时使用 release checklist 脚本，因为它会把固件资源、desktop 打包、签名/notarization、许可证材料和目标板读取结果写入 `dist/release/desktop-firmware-release-<version>-<arch>.md`。未传 `--arch` 时仍使用旧式 `desktop-firmware-release-<version>.md`。

```bash
SIGNING_IDENTITY="Developer ID Application: <name> (<team-id>)" \
NOTARYTOOL_PROFILE=<notarytool-profile> \
  script/desktop_firmware_release_checklist.sh \
  --arch arm64 \
  --version <release-version> \
  --minimum-desktop-version <desktop-version> \
  --python-runtime /path/to/python-runtime \
  --require-bundled-python \
  --notarize \
  --chip-port /dev/cu.usbmodemXXXX
```

Intel checklist 使用 `--arch x86_64`，并应在 Intel Mac 或 `macos-15-intel` runner 上执行，以确保 app、hook、bundled Python runtime 和 native Python packages 都是 x86_64。

如果没有接设备，可以省略 `--chip-port`，但报告会把 Target Chip 标记为 skipped。公开发布前不应把 skipped 当作真实 USB 通过。

checklist 会硬性检查：

- `THIRD_PARTY_NOTICES.md` 存在且包含 `esptool`。
- `--require-bundled-python` 时 notices 包含 bundled Python runtime。
- `OPEN_SOURCE_NOTICES.md` 存在且包含 `esptool` / `GPLv2+`。
- `SOURCE_OFFER.md` 存在且包含 `esptool` / `GPLv2+`。
- `FirmwareTools/sources/esptool-*.tar.*` 或 `.zip` 存在，并记录 SHA-256。
- app bundle icon 存在。
- 传入 `--arch` 时，app bundle 内所有 Mach-O 文件都包含目标架构 slice。
- `--chip-port` 提供时，打包后的 helper 能在 strict 模式和收窄 PATH 下执行 `chip_id`。

## `.env` 和 Make 入口

本地可复制 `.env.example`：

```bash
cp .env.example .env
$EDITOR .env
```

常用变量：

```text
SIGNING_IDENTITY="Developer ID Application: <name> (<team-id>)"
NOTARYTOOL_PROFILE="vibe-light-notary"
APPLE_API_KEY_PATH="$HOME/path/to/AuthKey_KEYID.p8"
APPLE_API_KEY_ID="KEYID"
APPLE_API_ISSUER="ISSUER_UUID"
PYTHON_RUNTIME="$HOME/.platformio/python3"
MINIMUM_DESKTOP_VERSION="dev"
RELEASE_ARCH="arm64"
RELEASE_VERSION=""
ESP32_PORT="/dev/cu.usbmodem1101"
ESP32_BAUD="460800"
```

创建或刷新 notarytool profile：

```bash
make notary-store
make notary-validate
```

读取 `.env` 并运行完整 notarized checklist：

```bash
make desktop-release-notarized
```

`.env`、`.env.local`、`.env.*.local` 和 `AuthKey_*.p8` 已被 `.gitignore` 忽略；不要把真实证书、API key、team 信息或个人路径写入文档。

## GitHub Actions 发布

手动发布 workflow 位于 `.github/workflows/release-desktop.yml`。它会用矩阵在 `macos-15` 上生成 `arm64` 产物，在 `macos-15-intel` 上生成 `x86_64` 产物：

1. 解析 version 和 tag。
2. 在两个 macOS runner 上分别校验 release secrets 和 runner 架构。
3. 为当前 runner 架构准备 bundled Python runtime。
4. 安装 ESP-IDF。
5. 导入 Developer ID 证书。
6. 创建临时 notarytool profile。
7. 运行带 `--arch` 的 notarized release checklist。
8. 解压并验证 notarized zip、Gatekeeper、codesign、strict helper 和 Mach-O 架构。
9. 上传 `VibeLightApp-<version>-arm64-notarized.zip`、`VibeLightApp-<version>-x86_64-notarized.zip` 和对应 checklist 报告。
10. 在发布 job 中生成 Sparkle `appcast.xml` 和 `appcast-x86_64.xml`。
11. 创建 GitHub draft / pre-release / release assets。

仓库需要配置：

- `SIGNING_IDENTITY`
- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `APPLE_API_KEY`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_PRIVATE_KEY`

workflow 当前使用 `actions/checkout@v6`、`actions/setup-python@v6` 和 `espressif/install-esp-idf-action@v1`。`release-desktop.yml` 已设置 `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`；如果 GitHub 仍提示 `espressif/install-esp-idf-action@v1` 声明 Node.js 20，这是上游 action metadata 未更新导致的非阻塞提醒。

CI 可以完成 arm64 / x86_64 可分发包生成、签名、notarization、staple、Gatekeeper / codesign / Mach-O 架构验证和 release asset 上传。真实 USB `chip_id`、UI 烧录、BLE 重连和 health packet 仍需要在本地 Mac + ESP32-S3 上验收；有条件时应分别在 Apple Silicon 和 Intel Mac 下载对应 zip 做启动与 helper 验证。

## 下载包验证

从 GitHub release 下载 zip 后，使用 `ditto` 解压：

```bash
rm -rf /tmp/vibe-light-release-test
mkdir -p /tmp/vibe-light-release-test
ditto -x -k VibeLightApp-<version>-arm64-notarized.zip /tmp/vibe-light-release-test
```

验证 notarization 和签名：

```bash
xcrun stapler validate /tmp/vibe-light-release-test/VibeLightApp.app
syspolicy_check distribution /tmp/vibe-light-release-test/VibeLightApp.app
codesign --verify --deep --strict --verbose=2 /tmp/vibe-light-release-test/VibeLightApp.app
script/verify_desktop_release_arch.sh --arch arm64 /tmp/vibe-light-release-test/VibeLightApp.app
```

验证 helper 在下载形态 app 中不依赖系统环境：

```bash
HELPER="/tmp/vibe-light-release-test/VibeLightApp.app/Contents/Resources/VibeLight_VibeLightApp.bundle/FirmwareTools/vibe-light-firmware-flasher"
PATH=/usr/bin:/bin:/usr/sbin:/sbin \
VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1 \
  "$HELPER" --help
```

抽查 GPL/source 材料：

```bash
TOOLS="/tmp/vibe-light-release-test/VibeLightApp.app/Contents/Resources/VibeLight_VibeLightApp.bundle/FirmwareTools"
test -f "$TOOLS/THIRD_PARTY_NOTICES.md"
test -f "$TOOLS/OPEN_SOURCE_NOTICES.md"
test -f "$TOOLS/SOURCE_OFFER.md"
ls "$TOOLS"/sources/esptool-*.tar.*
shasum -a 256 "$TOOLS"/sources/esptool-*.tar.*
```

非破坏性读取芯片：

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin \
VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1 \
  "$HELPER" --chip esp32s3 --port /dev/cu.usbmodemXXXX --baud 460800 chip_id
```

真实写入验证只在确认目标板和 release 版本后执行：

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin \
VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1 \
  "$HELPER" --chip esp32s3 --port /dev/cu.usbmodemXXXX --baud 460800 \
  write_flash \
  --flash_mode dio \
  --flash_freq 80m \
  --flash_size 16MB \
  0x0 FirmwareBundle/bootloader.bin \
  0x8000 FirmwareBundle/partition-table.bin \
  0x10000 FirmwareBundle/vibe_light_esp32.bin
```

实际 offset、flash 参数和文件路径应以下载包内 `FirmwareBundle/manifest.json` 为准。优先通过 app UI 完成烧录；手写 `write_flash` 只用于底层 helper 回归。

## 真机验收

每次公开发布前建议至少记录：

- release tag、commit、zip SHA-256 和 checklist SHA-256。
- 解压方式，优先 `ditto -x -k`。
- `xcrun stapler validate`、`syspolicy_check distribution` 和 `codesign --verify --deep --strict` 结果。
- strict helper `--help` 结果。
- `chip_id` 结果，包含 `ESP32-S3`、MAC、flash/PSRAM 信息。
- app UI 烧录是否完成三段 `Hash of data verified`。
- 烧录后串口是否出现 `LCD initialized` 和 `advertising as VibeLight-S3`。
- app 是否能发现并连接 `VibeLight-S3`。
- health packet 是否显示运行时间、连接状态、最近状态、heap、render tick、背光和最近解析错误。

如果 checklist 没有 `--chip-port`，必须明确写出目标芯片读取 skipped，不能把 CI 通过等同于真实设备通过。

## 安全和失败恢复

烧录路径必须保持这些约束：

- 烧录前先执行非破坏性 `chip_id`。
- 只允许目标芯片匹配 `esp32s3` 后继续写入。
- 固件包 manifest 固定目标硬件和目标芯片。
- 只写入 app、bootloader 和 partition table，不默认擦除整片 flash，避免无意清除 NVS 中的 high score 等状态。
- 不使用 `--force` 覆盖 secure boot / flash encryption 保护。
- 下载模式失败时提示 `BOOT` / `RST` 操作。
- 串口占用、写入校验失败、非 ESP32-S3 设备和 helper runtime 缺失要给出可执行恢复提示。
- 烧录成功后通过 BLE 名称和 health packet 做闭环验证。

## 合规边界

发布包会分发 `esptool`，因此必须随包提供 GPLv2+ 相关材料：

- `OPEN_SOURCE_NOTICES.md`
- `SOURCE_OFFER.md`
- `sources/esptool-<version>.tar.gz`
- `esptool` license 文件

`SOURCE_OFFER.md` 需要保留 `any third party` 和费用不超过实际源码分发成本的 wording。未来如果修改 bundled `esptool`，修改后的对应源码也必须按 GPLv2+ 一起提供，并同步更新 notice、source archive 和 hash。

Vibe Light 自有源码使用 source-available 非商用许可，和第三方 GPL/source 材料是两条独立边界。进入商业授权或商业分发前，仍建议做最终法律 / 合规确认。

## 已知后续事项

- 每次 release 前继续保存当次 checklist 报告和下载包验证记录。
- 历史 `v0.1.0` checklist 未做 `--chip-port`；后续 release 应尽量保留真实目标板读取、UI 烧录、BLE 重连和 Sparkle feed 验证记录。
- 持续关注 `espressif/install-esp-idf-action@v1` 是否发布原生 Node 24 版本。
- 如果将来考虑 App Store 分发，需要重新评估 sandbox 串口 / USB 权限；当前第一阶段更适合 Developer ID notarized 直分发。
