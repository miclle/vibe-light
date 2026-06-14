# Vibe Light 当前待办

这个文件记录项目当前状态下最值得继续推进的工作。README 保持产品概览，架构和协议细节放在 `docs/architecture.md`，硬件事实放在 `docs/hardware.md`。

## 当前状态

- macOS SwiftPM app 已有通用、智能体安装、硬件设备、固件烧录和事件五个主要界面。
- Hook CLI 会把 Codex / Claude 事件写入本地 `events.jsonl`，桌面端轮询事件并通过 `TaskTracker` 聚合多任务状态。
- BLE 协议当前以 `v: 2` 多任务状态包为主，保留 `v: 1` 降级路径；Codex 用量摘要会从 transcript 最新 `token_count` 事件提取，并提供 5h / 7d 剩余百分比、低余量 reset 提示和每条 Codex 任务的上下文已用百分比 / token 摘要。
- ESP32-S3 固件已接入 BLE Peripheral、状态解析、健康读取特征、ST7701 LCD 初始化、RGB565 framebuffer 绘制和 Codex 吃豆人 `busy` 迷宫动画。
- 显示模型已从“简单任务列表”推进到 320px 参考迷宫舞台、213 个豆子、4 个能量豆、最多 5 个错相主角、底部贴边任务面板、任务时长 / 新鲜度尾标和渲染签名去重。
- 屏幕任务详情会优先展示当前工具动作，例如 `Bash / TEST make quick`、`Bash / BUILD idf.py`、`Bash / SERIAL read_serial.py`、`Bash / APP quit`、`Bash / SEARCH StatusPacket` 或 `Edit / README.md`，避免只显示泛化任务摘要或完整 shell 命令。
- `waiting` 任务详情会优先展示审批目标，例如 `APPROVE Bash TEST make verify` 或 `ALLOW Edit README.md`，让屏幕直接提示下一步需要处理什么。
- 任务行右侧会展示新鲜度、运行时长和上下文用量，例如 `RUN 03:12`、`WAIT 01:08`、`2m ago`、`CTX xx%` 或 `CTX 4.2K/12K`；活跃任务会在运行时长和 `CTX` 之间低频轮播，80% 及以上高上下文占用时提高 `CTX` 出现频率并用黄色显示，90% 及以上用红色显示；硬件设备页有 `CTX color` 演示包用于实机复核。
- 屏幕页脚会在左下方显示短状态，例如 `CODEX LIVE`；旧协议包显示为 `CODEX LEGACY`，不直接暴露 `v1` / `v2` 这类内部协议版本。活跃/等待/错误计数只保留在迷宫里的 `ACTIVE` / `WAIT` / `ERR` 计数区，避免重复。页脚使用中性灰并与底边保留 12px 余量，避免贴到屏幕最底部；任务状态色块内缩显示，避免在屏幕边缘形成蓝色竖线。
- 固件连接状态已经会主动刷新屏幕：Central 连接时显示 `idle / desktop connected`，断开时显示 `offline / desktop disconnected`。
- 健康状态包已经包含运行时长、BLE 连接状态、最近显示状态、heap 余量、启动后 heap 低水位、渲染 tick、背光状态和最近解析错误；macOS 硬件页会展示这些诊断信息。
- macOS app 已有独立“固件烧录”页，可枚举常见 ESP32 USB 串口、加载并校验内置 `FirmwareBundle`、调用 helper 执行 `write_flash`，成功后启动 BLE 扫描；`projects/esp32/tools/package_firmware_bundle.py` 可从 ESP-IDF build 产物生成带 SHA-256 的 app resource 固件包，`projects/esp32/tools/package_firmware_tools.py` 可把 `esptool` 依赖 vendor 到 `FirmwareTools/python-packages/`，并生成 GPL source offer / 对应源码归档。
- Vibe Light 自有源码已经切换为 source-available 非商用许可：个人、学习、研究和其他非商业用途可免费使用；商业使用、商业分发或作为商业产品 / 服务的一部分使用，需要原作者单独书面授权；fork、复制、修改和再分发必须保留原作者署名、非商用限制和商业授权要求。
- 当前公开 release 为 `v0.1.0`，tag 指向 `7c9781aebdfd02c9be96dc078324599e51a40cd5`；release asset 包含 `VibeLightApp-0.1.0-notarized.zip` 和 `desktop-firmware-release-0.1.0.md`。下一次发布前，release notes / manifest / checklist 继续记录构建 commit、日期、许可边界和第三方许可证材料。
- 仓库级快速验证会运行 Swift 测试、ESP32 host-side C 测试、生成迷宫 / 全屏 PNG 预览并执行 Git whitespace 检查；ESP32 显示闭环已完成一次实机烧录和屏幕确认。
- 固件版本 `82d2180` 已在目标板完成烧录、串口启动、BLE 连接、健康特征实机读取、肉眼屏幕复核和长时间稳定性观察：LCD 初始化、BLE 广播、Central 连接、连续 `v: 2` 状态写入、token 摘要、页脚、底部余量、任务色块内缩、无边缘蓝线、macOS 硬件页健康读数和稳定性表现均正常；坏状态包后会回传 `lastParseError:"invalid JSON"`。
- 固件版本 `3215f23` 已完成目标板烧录和实机观察，确认结构拆分后的固件启动、屏幕显示和 BLE 链路正常。

## 最近实机验证

- 时间：2026-06-12。
- 端口：目标板 USB 串口。
- 固件版本：`524c46d`（boot log `App version`；本地 app resource manifest 为 `dev-test` / `27040bf`）。
- 验证范围：`dist/VibeLightApp.app` 携带的 `FirmwareBundle` + `FirmwareTools/vibe-light-firmware-flasher` 发布形态资源烟测。
- 结果确认：helper 在默认 PATH 下通过 `esptool.py v4.8.1` 完成写入；在收窄 PATH `/usr/bin:/bin:/usr/sbin:/sbin` 下通过 vendored `python-packages` 的 `esptool.py v4.11.0` 再次完成写入，均识别 `ESP32-S3 (QFN56)`，bootloader、partition table 和 app 三段写入 hash verified。重启后串口确认 `LCD initialized`、`advertising as VibeLight-S3`、desktop Central connected，并收到连续 `v:2` 状态写入。
- UI 闭环补充：同一天通过 macOS “硬件设备”页点击“烧录固件”完成一次 app UI 路径烧录；UI 展示 `esptool.py v4.8.1` 写入日志、三段 hash verified、自动扫描，随后重新连接 `VibeLight-S3` 并读取 health packet，健康卡显示运行时间、连接、运行中状态、背光开启、heap 余量和渲染 tick。

- 时间：2026-06-12。
- 验证范围：内置 Python runtime 发布资产准备。
- 结果确认：使用本机 PlatformIO portable Python 3.11.7 arm64 候选 runtime 运行 `script/prepare_desktop_firmware_release.sh --skip-esp32-build --version dev-test --minimum-desktop-version dev --python-runtime <python-runtime> --require-bundled-python` 成功；生成 `FirmwareTools/python` 约 105MB、`python-packages` 约 37MB、`FirmwareBundle` 约 1MB；收窄 PATH + strict helper 输出 `esptool.py v4.11.0`，并通过 bundled Python import smoke 覆盖 `esptool`、`pyserial`、`cryptography`、`PyYAML` 和 `cffi`。

- 时间：2026-06-12。
- 验证范围：本地 Developer ID 签名发布包。
- 结果确认：使用 Developer ID Application 签名身份运行 `script/package_desktop_release.sh` 成功生成 `dist/VibeLightApp.app` 和 `dist/release/VibeLightApp-26a8c33.zip`；脚本签名并验证 83 个 nested Mach-O 文件，覆盖 app、hook、内置 Python runtime、Python `lib-dynload` 和 vendored wheel `.so`；主 app 签名显示 hardened runtime、timestamp 和 sealed resources。签名后的 helper 在收窄 PATH + strict 模式下输出 bundled `esptool.py v4.11.0`，签名 app 可短暂启动；未 notarize 时 Gatekeeper 结果为 `Unnotarized Developer ID`。

- 时间：2026-06-12。
- 验证范围：notarization 凭证预检。
- 结果确认：`script/package_desktop_release.sh --notarize` 已支持 build/sign 前凭证校验和命令行覆盖 `NOTARYTOOL_PROFILE` / Apple API key 参数；初次预检在未配置凭证时会明确失败并提示配置方式，随后已创建 notarytool profile 并完成 notarization 验证。

- 时间：2026-06-12。
- 验证范围：Developer ID notarized desktop app。
- 结果确认：Developer ID signing + notarytool profile 的 `script/package_desktop_release.sh --notarize` 已跑通，Apple Notary submission `d923ce8c-d4f9-4a03-b26b-008a2f5ec9a4` 返回 `Accepted`；`xcrun stapler validate dist/VibeLightApp.app` 通过，`spctl -a -vv --type execute dist/VibeLightApp.app` 返回 `accepted / source=Notarized Developer ID`；`codesign -dvvv` 显示 `Notarization Ticket=stapled`、hardened runtime 和 sealed resources；签名 + notarized app 内 helper 在收窄 PATH + strict 模式下输出 bundled `esptool.py v4.11.0`；notarized app 可短暂启动。继续用 notarized app bundle 内 helper 执行非破坏性 `chip_id` 读取，识别 `ESP32-S3 (QFN56)`、BLE 和 8MB PSRAM。随后在 notarized app UI 点击“烧录固件”，完成 bootloader、partition table 和 app 三段写入，日志显示三段 `Hash of data verified`；烧录后 app 扫描到 `VibeLight-S3`，重新连接并读取 health packet，健康卡显示运行时间、连接已连接、最近状态运行中、背光开启、heap 约 6.7 MB 和 render tick。

- 时间：2026-06-13。
- 验证范围：带 GPL source gate 的完整 desktop firmware release checklist。
- 结果确认：在提交 `ffaf09f` 上运行 `script/desktop_firmware_release_checklist.sh --version 2026.06.13-dev-ffaf09f --minimum-desktop-version dev --python-runtime <python-runtime> --require-bundled-python --notarize --chip-port /dev/cu.usbmodemXXXX` 通过；ESP-IDF 构建生成 app version `ffaf09f`，Developer ID 签名验证 83 个 nested Mach-O，Apple Notary submission `8c39946b-beab-421b-8b1f-48d9bea0b2c0` 返回 `Accepted`，staple / validate 和 Gatekeeper `source=Notarized Developer ID` 通过。release checklist 报告 `dist/release/desktop-firmware-release-2026.06.13-dev-ffaf09f.md` 记录 third-party notice、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md` 和 `sources/esptool-4.11.0.tar.gz`，源码包 SHA-256 为 `496571e4f6e36f7dc9a730dd485c4a9d522c9e7d6bb90ea2fec0a049275fbfad`；notarized zip `dist/release/VibeLightApp-2026.06.13-dev-ffaf09f-notarized.zip` 已抽查包含上述 GPL 材料。notarized app 内 strict helper 读取到 `ESP32-S3 (QFN56) (revision v0.2)`。

- 时间：2026-06-13。
- 验证范围：发布包内 `esptool` GPL gate 工程合规审阅。
- 结果确认：审阅对象为 zip 内实际文件 `dist/release/VibeLightApp-2026.06.13-dev-ffaf09f-notarized.zip`。审阅确认 `THIRD_PARTY_NOTICES.md`、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md`、`python-packages/esptool-4.11.0.dist-info/licenses/LICENSE` 和 `sources/esptool-4.11.0.tar.gz` 均存在；源码包 SHA-256 与 notice 一致，源码包包含 `LICENSE`、`PKG-INFO`、`pyproject.toml`、`setup.py`、`setup.cfg`、`esptool/` 源码和 stub flasher 资源，`PKG-INFO` 标明 `Name: esptool`、`Version: 4.11.0`、`License: GPLv2+`。工程审阅结论为当前 dev release 的 `esptool` GPL gate 可以放行；正式商业发布前仍建议法律 / 合规最终确认。

- 时间：2026-06-13。
- 验证范围：GitHub pre-release 下载产物回归。
- 结果确认：曾发布 GitHub pre-release `v2026.06.13-dev-ffaf09f`，tag 指向实际构建提交 `ffaf09fec89a13ba26a86f6139255c26d3836d57`。已从 GitHub release 下载 `VibeLightApp-2026.06.13-dev-ffaf09f-notarized.zip` 和 checklist 报告到 `/tmp/vibe-light-release-test-2026.06.13-dev-ffaf09f`，SHA-256 分别为 `260b0b4e30fc44e408cbfd83ef5286802a949523b1fc36f9955c0f1688577f7d` 和 `41a407d026fdbb7502c940f3e55613307417d00ba8cf7035f4210cec5b573737`，与 release notes 一致。用 `ditto -x -k` 解压出的 app 通过 `xcrun stapler validate`、`spctl -a -vv --type execute` 和 `codesign --verify --deep --strict`，zip 内 GPL 材料和 `esptool` 源码包 hash 复核通过，下载 app 可启动并退出。用命令行 `unzip` 解压同一 zip 时出现 sealed resource 校验失败；release notes 已补充建议使用 Finder / Archive Utility 或 `ditto` 解压。手动让目标板进入 ROM download mode 后，下载 app UI 完成“读取芯片 -> 烧录固件 -> BLE 重连 / health packet”闭环：识别 `ESP32-S3 (QFN56)`，UI 烧录 bootloader / partition table / app 三段均 `Hash of data verified`，随后发现 `VibeLight-S3`、连接并读取健康状态，健康卡显示运行时间约 1 分 20 秒、连接已连接、最近状态运行中、背光开启、可用 heap 约 6.7 MB、render tick 9。

- 时间：2026-06-13。
- 验证范围：烧录进度修复后的 GitHub pre-release 发布与下载包回归。
- 结果确认：曾发布 GitHub pre-release `v2026.06.13-dev-98427be`，tag 指向 `98427bee72b1a3249f1b022ee794fefd0cd9cabf`，并在 release notes 标明 supersede `v2026.06.13-dev-ffaf09f`。完整 `script/desktop_firmware_release_checklist.sh --version 2026.06.13-dev-98427be --minimum-desktop-version dev --python-runtime <python-runtime> --require-bundled-python --identity "Developer ID Application: <name> (<team-id>)" --notarize --notarytool-profile <notarytool-profile> --chip-port /dev/cu.usbmodemXXXX` 通过；Apple Notary submission `0fe51533-2c15-493e-809d-07693eb43a2e` 返回 `Accepted`，staple / validate、`syspolicy_check distribution` 和 `codesign --verify --deep --strict` 通过。GitHub asset 重新下载后的 SHA-256 为 `55c31ef27c5a8957b2393d920bd159c8b42bd0840e13d4949b392ac0cae61bfa`（notarized zip）和 `44a0f3881635d2f769bcee7af4cdf25840c169d9213a4ab990638b418c0a2ea9`（checklist），与 release notes / GitHub digest 一致。下载 zip 用 `ditto -x -k` 解压后通过 stapler、distribution policy 和 codesign，manifest 为 `2026.06.13-dev-98427be / 98427be`，GPL 材料和 `sources/esptool-4.11.0.tar.gz` 均存在，源码包 SHA-256 仍为 `496571e4f6e36f7dc9a730dd485c4a9d522c9e7d6bb90ea2fec0a049275fbfad`。同一下载形态 app 内 strict helper 完成完整 `write_flash`，bootloader、partition table 和 app 三段均 `Hash of data verified`，最后 `Hard resetting via RTS pin`。

- 时间：2026-06-13。
- 验证范围：`v2026.06.13-dev-98427be` 下载 app UI 试用和后续修复。
- 结果确认：从下载目录启动下载形态 app 成功；固件烧录页读取芯片识别 `ESP32-S3 (QFN56)`，UI 完成 bootloader、partition table 和 app 三段写入，随后连接 `VibeLight-S3` 并刷新健康状态到运行中、背光开启。试用中发现 UI 会在 app 分区仍写入时提前显示 `校验完成 100%`，原因是累计日志里早期分区的 `Hash of data verified` 优先级高于后续写入行。`68e6244` 已修复为按累计日志里最后出现的 esptool 事件决定当前进度，并增加 Swift 测试；`swift test --package-path projects/macos/desktop` 通过 80 个测试。`v2026.06.13-dev-98427be` release notes 已补充该已知问题。尝试为 `68e6244` 生成本地替换版 notarized dev release 时，checklist 曾在本机 notarytool profile 凭证预检处停止；后续已改用 GitHub Actions 内的 Apple API key 临时 notarytool profile 路线解决。

- 时间：2026-06-14。
- 验证范围：GitHub Actions 生成的 Developer ID notarized pre-release 和真实用户路径。
- 结果确认：`release-desktop.yml` 已在提交 `d5dd54a` 上完整跑通，发布 `v2026.06.14-dev-d5dd54a` pre-release；GitHub asset `VibeLightApp-2026.06.14-dev-d5dd54a-notarized.zip` 的 SHA-256 为 `023df16bf7710bae338d9ad03e40a4808d402c9416c2803493d11946f851fd83`。下载 zip 用 `ditto -x -k` 解压后通过 `xcrun stapler validate`、`syspolicy_check distribution`、`codesign --verify --deep --strict` 和 strict helper `--help` 验证；下载形态 `.app` 可启动并保持运行，不再复现 `Bundle.module` resource bundle 启动崩溃。包内 helper 完成 `chip_id` 和完整 `write_flash`，识别 `ESP32-S3 (QFN56)`，bootloader、partition table 和 app 三段均 `Hash of data verified`，最后 `Hard resetting via RTS pin`。用户随后确认该 release 实测正常。

- 时间：2026-06-14。
- 验证范围：`v0.1.0` release 远端发布状态和 checklist 资产。
- 结果确认：GitHub 当前公开 release 为 `v0.1.0`，tag 指向 `7c9781aebdfd02c9be96dc078324599e51a40cd5`，发布时间为 `2026-06-14T04:32:31Z`；asset `VibeLightApp-0.1.0-notarized.zip` 的 GitHub digest 为 `sha256:27e570b66fb3e7e33da4474a0436b7f1d21e53711216c3b986a181cf76f974a6`，checklist asset `desktop-firmware-release-0.1.0.md` 的 digest 为 `sha256:0f73df1b82e27ac3cdfb350aef325b83c105a2186148d6b87516eb1a8019dc6e`。下载 checklist 显示 CI release flow 在 commit `7c9781aebdfd02c9be96dc078324599e51a40cd5` 上通过：固件资源、desktop app、bundle icon、third-party notices、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md` 和 `sources/esptool-4.11.0.tar.gz` 均通过检查，`esptool` 源码包 SHA-256 为 `496571e4f6e36f7dc9a730dd485c4a9d522c9e7d6bb90ea2fec0a049275fbfad`；该 checklist 未提供 `--chip-port`，所以目标芯片读取为 skipped，真实 USB 烧录仍以历史下载包回归记录为准。

- 时间：2026-06-11。
- 端口：目标板 USB 串口。
- 固件版本：`3215f23`。
- 验证范围：结构治理后的 ESP32 固件烧录和实机观察。
- 结果确认：启动、屏幕显示和 BLE 链路观察正常。

## 历史验证归档

- `524c46d`：已完成目标板烧录；macOS 演示包提交 `939583d` 增加了 `CTX color` 场景，并已通过实机肉眼复核：80% 及以上 `CTX` 黄色提示、90% 及以上红色提示显示正常。
- `82d2180`：已完成串口启动、BLE 连接、连续 `v: 2` 写入、健康特征读取、坏 JSON parse error 回传、屏幕肉眼复核和长时间稳定性观察。
- `61a603d`：5 分钟串口采样内 hard error 0、断连 0、状态写入 144 次、显示渲染 147 次；日志在 `/tmp/vibe-light-stability-clean-61a603d.log`。
- `090391d` / `353426d`：早期实机启动、BLE 写入和基础屏幕显示确认；仅作为历史参考，不代表后续显示修正已重新复核。

## 未完成事项

1. **维护 app 内固件烧录的发布闭环**
   - 当前已完成 desktop 入口、固件包生成、manifest 校验、串口枚举、helper 参数生成、`vibe-light-firmware-flasher` wrapper、esptool 依赖 vendoring 和成功后 BLE 扫描。
   - 发布形态资源已完成实机烟测：dist app resource 中的 helper 和固件包可通过 USB 写入目标板，vendored `python-packages` 路径可在无 Homebrew esptool 的 PATH 下工作，重启后 BLE 广播和 desktop 连接 / 状态写入正常；macOS UI 点击“烧录固件”也已完成烧录、扫描、连接和 health packet 展示闭环。
   - `script/prepare_desktop_firmware_release.sh` 已提供发布资产准备入口，串起 ESP32 构建、固件包生成、esptool vendoring 和 helper 收窄 PATH 验证；`package_firmware_tools.py` 会生成 `FirmwareTools/THIRD_PARTY_NOTICES.md`、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md` 和 `sources/esptool-<version>.tar.gz` 供发布审阅。
   - 第一版发布路线已切到内置 Python runtime：`package_firmware_tools.py --python-runtime <path> --require-python-runtime` 可复制 runtime 到 `FirmwareTools/python/`，`VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1` 可验证 helper 不依赖系统 Python、Homebrew `esptool` 或用户 PATH；本地 PlatformIO portable Python 3.11.7 arm64 runtime 已完成 release-prep 和 import smoke，随包 `package.json` 记录 `python-portable 1.31107.0`、`darwin_arm64`、`PSF-2.0` 和 Python/CPython 来源。
   - `script/package_desktop_release.sh` 已提供本地 Developer ID 签名验证入口，可生成 `dist/VibeLightApp.app`、签名 bundle 内 nested Mach-O、签 resource bundle / 主 app、执行 `codesign --verify`、归档 zip，并支持显式 `--notarize` 后先校验凭证再提交、staple 和 Gatekeeper 校验。
   - `script/desktop_firmware_release_checklist.sh` 已把固件资源准备、desktop app 打包签名、可选 notarization、third-party notice / GPL source gate 检查和目标板 `chip_id` 读取串成 markdown checklist，日志写入 `dist/release/logs/`。
   - UI 已把固件烧录改成独立侧边栏入口和 step-by-step 向导，覆盖连接 USB、读取芯片、按需进入下载模式、确认并烧录、写入固件、RST 正常启动、BLE 连接和完成状态；download mode 失败会分步提示 `BOOT` / `RST` 操作，烧录成功后会提示只点按 `RST` 正常启动。
   - UI 已能针对下载模式、串口占用、写入校验失败、非 ESP32-S3 设备和 helper runtime 缺失给出明确恢复提示。
   - 带 GPL source gate 的完整 release checklist 已通过；下一次公开发布前仍需人工审阅生成的 esptool/Python 许可证材料，尤其确认 `esptool` GPLv2+ source offer、源码归档和间接依赖 notice。
   - 2026-06-14 已补强生成脚本：`SOURCE_OFFER.md` fallback wording 明确 `any third party`、费用不超过实际源码分发成本和 GitHub 仓库联系入口；`package_firmware_tools.py` 会为 `pyserial 3.5` 补齐独立 `LICENSE.txt`，让生成的 `THIRD_PARTY_NOTICES.md` 能记录该 license 文件，减少长期审计摩擦。
   - Vibe Light 自有源码已经切换为 source-available 非商用许可；继续保留 GPL/source 材料即可。如果未来修改 bundled `esptool`，修改后的对应源码也必须按 GPLv2+ 提供，并同步更新 notice、source archive 和 hash。
   - notarized app bundle 内 helper 已能访问目标板 USB 串口并读取 `ESP32-S3 (QFN56)` 芯片信息；notarized app UI 已完成完整串口烧录、BLE 扫描 / 连接和 health packet 展示闭环。
   - GitHub Actions 生成的 Developer ID notarized release 包已经覆盖 hash、notarization/Gatekeeper、codesign、GPL/source 材料和 checklist gate；真实 USB 烧录、BLE 重连和 health packet 仍需要按下载包形态做人工回归。
   - `v0.1.0` 当前公开 release 的 checklist 资产已确认固件资源、desktop app、bundle icon、third-party notices、GPL source offer 和 `esptool` 源码包检查通过；该 release checklist 没有提供 `--chip-port`，目标芯片读取为 skipped。
   - dev app UI 已补齐烧录前芯片确认：读取前“烧录固件”禁用，点击“读取芯片”确认 `ESP32-S3 (QFN56)` 和 MAC 后才启用写入入口，避免直接进入写入；写入阶段会解析 esptool 输出显示实时 stage/progress，并保留完整实时日志。
   - 方案细节见 `docs/desktop-firmware-flashing.md`。

2. **保持显示模型测试随功能演进收紧**
   - 已有 host-side C 测试覆盖动画路径、重复包去重、任务行格式、未知状态降级、底部布局、整轮豆子重置、用量显示和中文任务文本。
   - 新增屏幕布局、状态表现、迷宫素材、坐标或缩放规则时，仍需同步更新 `vibe_display_model.*`、`render_maze_preview.py` 和 parser 测试断言。

3. **横屏 layout mode 仍是实验方向**
   - 暂时保留竖屏作为默认稳定模式，因为当前设备外观和摆放更适合竖向状态灯。
   - 横屏原型不需要改 BLE 协议，先只调整 ESP32 渲染布局。
   - 建议原型信息架构为“左侧状态 / 中间 Codex 动画 / 右侧任务列表 / 顶部或底部统计条”。
   - 实机对比竖屏和横屏后，再决定是否产品化为可配置展示模式。

4. **跟进 GitHub Actions Node.js 20 弃用提醒**
   - `release-desktop.yml` 已升级到 `actions/checkout@v6` 和 `actions/setup-python@v6`，两者上游 `action.yml` 已声明 `node24`。
   - `espressif/install-esp-idf-action` 当前默认分支仍是 `v1`，没有可升级 tag，且上游 `action.yml` 仍声明 `node20`；workflow 已设置 `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` 提前使用 Node 24 runtime，后续仍需关注 Espressif 是否发布原生 Node 24 版本。
   - 2026-06-14 已用 draft 验证版 `v2026.06.14-dev-d3cf90c-node24` 跑通 `release-desktop.yml`，workflow run `27484068864` 完成 ESP-IDF 安装、Developer ID 签名、notarization、archive 验证和 release asset 创建；验证 draft 已删除。GitHub 仍会提示 `espressif/install-esp-idf-action@v1` 声明 Node.js 20 但被强制运行在 Node.js 24，这是上游 metadata 未更新导致的非阻塞提醒。

## 推荐推进顺序

1. **准备下一版公开发布入口**
   - 基于当前非商用许可准备下一版 release 或 beta。
   - 继续用真实用户路径重点观察首次打开、蓝牙授权、固件烧录向导、USB 串口识别、RST / BOOT 指引、烧录日志感知和 BLE 重连体验。

2. **守住现有竖屏和发布闭环**
   - 后续协议、任务摘要、硬件页或烧录页改动优先补测试和实机回归。
   - 每次发布前继续重复 GitHub release asset 下载、Gatekeeper / codesign、strict helper 和真机烧录验证。

3. **处理非阻塞发布治理**
   - 持续关注 `espressif/install-esp-idf-action` 是否发布原生 Node 24 版本。
   - 自有源码非商用许可和第三方 GPL/source 材料需要分开审阅；如果进入商业授权或商业分发，仍建议做最终法律 / 合规确认，重点复核 bundled `esptool` GPLv2+ source offer、源码归档和第三方 notices 的最终发布形态。

4. **再评估横屏原型**
   - 横屏是产品方向探索，不是当前链路可靠性的前置条件。
   - 建议在竖屏实机闭环稳定后，用 host-side preview 先做布局草图，再决定是否投入固件实现。

## 验证命令

快速验证协议和桌面逻辑：

```bash
./script/verify.sh --quick
```

完整验证：

```bash
./script/verify.sh
```

完整验证会尝试 ESP32 固件构建，需要本机 `IDF_PATH` 指向 ESP-IDF checkout。
