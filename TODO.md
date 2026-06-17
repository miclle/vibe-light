# Vibe Light 当前待办

这个文件记录项目当前状态下最值得继续推进的工作。README 保持产品概览，架构和协议细节放在 `docs/architecture.md`，硬件事实放在 `docs/hardware.md`。

## 当前状态

- macOS SwiftPM app 已有通用、智能体安装、硬件设备、固件烧录和事件五个主要界面。
- Hook CLI 会把 Codex / Claude 事件写入本地 `events.jsonl`，桌面端轮询事件并通过 `TaskTracker` 聚合多任务状态。
- BLE 协议当前以 `v: 2` 多任务状态包为主，保留 `v: 1` 降级路径；Codex 用量摘要会从 transcript 最新 `token_count` 事件提取，并提供 5h / 7d 剩余百分比、低余量 reset 提示和每条 Codex 任务的上下文已用百分比 / token 摘要。
- ESP32-S3 固件已接入 BLE Peripheral、状态解析、健康读取特征、ST7701 LCD 初始化、RGB565 framebuffer 绘制、Codex 吃豆人 `busy` 迷宫动画和 QMI8658 横竖屏切换。
- 显示模型已从“简单任务列表”推进到 320px 竖屏参考迷宫舞台、横屏整屏截图样式吃豆人 RLE 画面、213 个豆子、4 个能量豆、最多 5 个错相主角、底部贴边任务面板、任务时长 / 新鲜度尾标和渲染签名去重。
- 屏幕任务详情会优先展示当前工具动作，例如 `Bash / TEST make quick`、`Bash / BUILD idf.py`、`Bash / SERIAL read_serial.py`、`Bash / APP quit`、`Bash / SEARCH StatusPacket` 或 `Edit / README.md`，避免只显示泛化任务摘要或完整 shell 命令。
- `waiting` 任务详情会优先展示审批目标，例如 `APPROVE Bash TEST make verify` 或 `ALLOW Edit README.md`，让屏幕直接提示下一步需要处理什么。
- 任务行右侧会展示新鲜度、运行时长和上下文用量，例如 `RUN 03:12`、`WAIT 01:08`、`2m ago`、`CTX xx%` 或 `CTX 4.2K/12K`；活跃任务会在运行时长和 `CTX` 之间低频轮播，80% 及以上高上下文占用时提高 `CTX` 出现频率并用黄色显示，90% 及以上用红色显示；硬件设备页有 `CTX color` 演示包用于实机复核。
- 屏幕页脚会在左下方显示短状态，例如 `CODEX LIVE`；旧协议包显示为 `CODEX LEGACY`，不直接暴露 `v1` / `v2` 这类内部协议版本。活跃/等待/错误计数只保留在迷宫里的 `ACTIVE` / `WAIT` / `ERR` 计数区，避免重复。页脚使用中性灰并与底边保留 12px 余量，避免贴到屏幕最底部；任务状态色块内缩显示，避免在屏幕边缘形成蓝色竖线。
- 固件连接状态已经会主动刷新屏幕：Central 连接时显示 `idle / desktop connected`，断开时显示 `offline / desktop disconnected`。
- 健康状态包已经包含运行时长、BLE 连接状态、最近显示状态、heap 余量、启动后 heap 低水位、渲染 tick、背光状态和最近解析错误；macOS 硬件页会展示这些诊断信息。
- 最新 ESP32 显示路径已拆分竖屏 / 横屏渲染模块，并把竖屏 `busy` 动画提交路径改为 RGB driver 三 framebuffer 轮转；`CODEX: 5H / 7D` 用量信息由 macOS 端优先保留在 compact BLE 包中。当前实机仍观察到轻微屏幕闪烁，而且在没有吃豆人动画时也会出现，下一步应从 ST7701 RGB LCD 时序、PCLK / porch / bounce buffer、PSRAM 带宽、VSYNC 同步、背光 PWM 或硬件供电方向排查，而不是只盯竖屏动画绘制逻辑。
- macOS app 已有独立“固件烧录”页，可枚举常见 ESP32 USB 串口、加载并校验内置 `FirmwareBundle`、调用 helper 执行 `write_flash`，成功后启动 BLE 扫描；`projects/esp32/tools/package_firmware_bundle.py` 可从 ESP-IDF build 产物生成带 SHA-256 的 app resource 固件包，`projects/esp32/tools/package_firmware_tools.py` 可把 `esptool` 依赖 vendor 到 `FirmwareTools/python-packages/`，并生成 GPL source offer / 对应源码归档。
- Vibe Light 自有源码已经切换为 source-available 非商用许可：个人、学习、研究和其他非商业用途可免费使用；商业使用、商业分发或作为商业产品 / 服务的一部分使用，需要原作者单独书面授权；fork、复制、修改和再分发必须保留原作者署名、非商用限制和商业授权要求。
- 当前公开 latest release 为 `v0.1.2`，tag 指向 `ffe505e76e0da0f5b7abcd6c8a22cbb48e7852c6`；release asset 包含 `VibeLightApp-0.1.2-arm64-notarized.zip`、`VibeLightApp-0.1.2-x86_64-notarized.zip`、`desktop-firmware-release-0.1.2-arm64.md`、`desktop-firmware-release-0.1.2-x86_64.md`、`appcast.xml` 和 `appcast-x86_64.xml`。`v0.1.2` 已完成双架构 CI notarized release、latest appcast 匿名下载、下载包签名 / notarization / 架构扫描验证；`v0.1.1` 已完成默认 stable feed Sparkle 更新、下载包启动、USB 固件烧录和 BLE 重连验证。
- 仓库级快速验证会运行 Swift 测试、ESP32 host-side C 测试、校验迷宫预览脚本读取显示模型布局常量、生成竖屏迷宫 / 竖屏全屏 / 横屏全屏 PNG 预览并执行 Git whitespace 检查；ESP32 显示闭环已完成一次实机烧录和屏幕确认。
- 固件版本 `82d2180` 已在目标板完成烧录、串口启动、BLE 连接、健康特征实机读取、肉眼屏幕复核和长时间稳定性观察：LCD 初始化、BLE 广播、Central 连接、连续 `v: 2` 状态写入、token 摘要、页脚、底部余量、任务色块内缩、无边缘蓝线、macOS 硬件页健康读数和稳定性表现均正常；坏状态包后会回传 `lastParseError:"invalid JSON"`。
- 固件版本 `3215f23` 已完成目标板烧录和实机观察，确认结构拆分后的固件启动、屏幕显示和 BLE 链路正常。

## 最近实机验证

- 时间：2026-06-17 CST。
- 端口：`/dev/cu.usbmodem1101`。
- 固件版本：`v0.1.2-25-ge420d99`。
- 验证范围：竖屏 / 横屏渲染拆分、竖屏动画三 framebuffer 隔离、RGB VSYNC restart 配置、macOS compact BLE 包优先保留 `usage`、ESP32 构建和实机烧录。
- 结果确认：`make esp32-build` 通过；Swift 全量测试曾用 scratch path 跑过 85 个测试通过；desktop update release tests、ESP32 parser tests、竖屏 / 横屏预览和 `git diff --check` 通过。`make esp32-flash-only ESP32_PORT=/dev/cu.usbmodem1101` 烧录成功，识别 `ESP32-S3 (QFN56) (revision v0.2)`、8MB PSRAM 和 MAC `1c:db:d4:7b:3f:cc`，三段写入均 `Hash of data verified`。烧录后串口确认连续 `v:2` busy 状态包被接受，包内带 `usage.codex5hRemainingPercent` / `usage.codex7dRemainingPercent`，屏幕可恢复显示 `CODEX: 5H / 7D`。
- 已知问题：用户实机观察到屏幕仍会轻微闪烁，且没有吃豆人动画时也会出现；这更像 LCD/RGB 输出链路或背光 / 供电层面的微闪，不再局限于竖屏 Pac-Man 动画刷新。

- 时间：2026-06-16 09:37 CST。
- 端口：`/dev/cu.usbmodem1101`。
- 固件版本：`v0.1.2-12-g7658f67-dirty`（本地工作区含由 `docs/Pac-Man-landscape.png` 生成的横屏整屏截图样式 Pac-Man RLE 画面、去除横屏顶部 / 底部 HUD 覆盖、竖屏同源计分 / 关卡 / high score 推进逻辑和 512 x 200 横屏源数据压缩）。
- 验证范围：本地 ESP-IDF 直接烧录当前工作区固件。
- 结果确认：`make esp32-flash-only ESP32_PORT=/dev/cu.usbmodem1101` 识别 `ESP32-S3 (QFN56) (revision v0.2)`、8MB PSRAM 和 MAC `1c:db:d4:7b:3f:cc`；bootloader、app 和 partition table 三段均写入并 `Hash of data verified`，最后 `Hard resetting via RTS pin`。烧录前 `make quick` 和 `make esp32-build` 通过；固件 app 分区剩余 `0x3f90`，约 2%。当前未做肉眼横放 / 竖立方向切换复核。

- 时间：2026-06-16 08:58 CST。
- 端口：`/dev/cu.usbmodem1101`。
- 固件版本：`v0.1.2-11-g50f0666-dirty`（本地工作区含横屏 layout mode、全宽截图样式 Pac-Man RLE 迷宫、竖直角色 sprite、状态包驱动吃豆人移动、QMI8658 方向切换和关闭 240ms 定时整屏刷新改动）。
- 验证范围：本地 ESP-IDF 直接烧录当前工作区固件。
- 结果确认：`make esp32-flash-only ESP32_PORT=/dev/cu.usbmodem1101` 识别 `ESP32-S3 (QFN56) (revision v0.2)`、8MB PSRAM 和 MAC `1c:db:d4:7b:3f:cc`；bootloader、app 和 partition table 三段均写入并 `Hash of data verified`，最后 `Hard resetting via RTS pin`。烧录后连续 12 秒读取串口，确认桌面端已连接并连续写入 `v:2` busy 状态包，固件日志显示 `status write accepted` 和 `vibe_display` 刷新显示，未出现 `task_wdt`、panic 或重启循环。当前未做肉眼横放 / 竖立方向切换复核；闪屏修复已从策略上移除 `busy` / `waiting` 状态下的 240ms 定时整屏刷新，busy 状态改为随状态包到达推进吃豆人动画。

- 时间：2026-06-16 07:49 CST。
- 端口：`/dev/cu.usbmodem1101`。
- 固件版本：`v0.1.2-11-g50f0666-dirty`（本地工作区含横屏 layout mode、全宽截图样式 Pac-Man RLE 迷宫和 QMI8658 方向切换改动）。
- 验证范围：本地 ESP-IDF 直接烧录当前工作区固件。
- 结果确认：`make esp32-flash-only ESP32_PORT=/dev/cu.usbmodem1101` 识别 `ESP32-S3 (QFN56) (revision v0.2)`、8MB PSRAM 和 MAC `1c:db:d4:7b:3f:cc`；bootloader、app 和 partition table 三段均写入并 `Hash of data verified`，最后 `Hard resetting via RTS pin`。烧录后短读串口确认桌面端已连接并写入 `v:2` 状态包，固件日志显示 `status write accepted` 和 `vibe_display` 以 `state=busy`、`tasks=3` 刷新显示。当前未做肉眼横放 / 竖立方向切换复核。

- 时间：2026-06-15 22:48 CST。
- 端口：`/dev/cu.usbmodem1101`。
- 固件版本：`v0.1.2-7-g2147743-dirty`（本地工作区基于 `2147743`，含未提交显示模型测试 / 预览脚本变更）。
- 验证范围：本地 ESP-IDF 直接烧录当前工作区固件。
- 结果确认：`make esp32-flash-only ESP32_PORT=/dev/cu.usbmodem1101` 识别 `ESP32-S3 (QFN56) (revision v0.2)`、8MB PSRAM 和 MAC `1c:db:d4:7b:3f:cc`；bootloader、app 和 partition table 三段均写入并 `Hash of data verified`，最后 `Hard resetting via RTS pin`。烧录后短读串口确认桌面端已连接并连续写入 `v:2` 状态包，固件日志显示 `status write accepted` 和 `vibe_display` 以 `state=busy`、`tasks=3` 刷新显示。

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

- 时间：2026-06-14。
- 验证范围：Sparkle 自动更新 beta 链路。
- 结果确认：`release-desktop.yml` 在提交 `2a026786ad691676e36b85f4fb51e11755896341` 上通过并发布公开 pre-release `v2026.06.14-dev-2a02678`，包含 `VibeLightApp-2026.06.14-dev-2a02678-notarized.zip`、`desktop-firmware-release-2026.06.14-dev-2a02678.md` 和 `appcast.xml`。下载资产 SHA-256 分别为 `05a77f47c7ba4c56149a2d72c8d85a65c590b8754c4c29ba1f5f1e35fdeabb34`、`80443291396742d5929caa7e77b20bf0aa2c7c41c965ce5346135a6875fd567d` 和 `e24e38b037ca496272ee5f1c6e706b06516b9b04a6b573b3e3d257df2b635691`；下载 zip 用 `ditto -x -k` 解压后通过 bundle icon、Sparkle metadata、`xcrun stapler validate`、`syspolicy_check distribution`、`codesign --verify --deep --strict` 和启动验证。用本地旧版测试 app（`CFBundleVersion=182`，`SUFeedURL` 指向该 pre-release `appcast.xml`）点击“检查更新...”，Sparkle 显示 `Vibe Light 2026.6.14 is now available—you have 2026.6.13`，随后完成下载、`Install and Relaunch`、替换安装和重启；替换后的 app 为 `CFBundleShortVersionString=2026.6.14`、`CFBundleVersion=183`，并再次通过 Sparkle metadata、stapler、distribution policy 和 codesign 验证。

- 时间：2026-06-14。
- 验证范围：Sparkle 自动更新 stable 链路和 `v0.1.1` 下载包真实用户路径。
- 结果确认：`release-desktop.yml` 在提交 `2dee78b70fcdc43bd82f4eac64fe02b49804e882` 上通过并发布正式非 draft / 非 pre-release `v0.1.1`，该 release 已成为 GitHub Latest，包含 `VibeLightApp-0.1.1-notarized.zip`、`desktop-firmware-release-0.1.1.md` 和 `appcast.xml`。下载资产 SHA-256 分别为 `9d36726c3a41f62167f44083b9da406bfcaa5e923f24ffe5affc778c5d11966d`、`256b52b6ac3216978153da9b7514632d051163ffbbc3dd95bbe90a48070fc16f` 和 `e70a19af5d066a944973cbf30448f6846b97593d8b82c019ad09ba5c2243208a`；`https://github.com/miclle/vibe-light/releases/latest/download/appcast.xml` 可匿名下载，内容与 tag appcast 一致，指向 `VibeLightApp-0.1.1-notarized.zip`，Sparkle 版本为 `185 / 0.1.1` 并带 EdDSA 签名。下载 zip 用 `ditto -x -k` 解压后通过 bundle icon、Sparkle metadata、`xcrun stapler validate`、`syspolicy_check distribution`、`codesign --verify --deep --strict` 和启动验证；用户随后手动确认旧版 app 通过默认 stable feed 完成 Sparkle 检查更新、安装并重启到 `0.1.1`，并确认 `v0.1.1` 下载 app 完成 USB 固件烧录和 BLE 重连。

- 时间：2026-06-14。
- 验证范围：`arm64` / `x86_64` 双平台 desktop release workflow draft 验证。
- 结果确认：提交 `1ab4e886a693b61e287ddc2b97cc75c7b15bb447` 上的 `release-desktop.yml` workflow run `27495566412` 通过，创建 draft / pre-release `v2026.06.14-dev-1ab4e88-dualarch`。CI 在 `macos-15` 上生成 `VibeLightApp-2026.06.14-dev-1ab4e88-dualarch-arm64-notarized.zip`，在 `macos-15-intel` 上生成 `VibeLightApp-2026.06.14-dev-1ab4e88-dualarch-x86_64-notarized.zip`，并分别通过 bundled Python runtime 架构检查、ESP-IDF 固件构建、Developer ID 签名、Apple notarization、staple、`syspolicy_check distribution`、`codesign --verify --deep --strict`、strict helper `--help` 和 release log 凭证泄漏检查。draft release asset 包含两个 notarized zip、两个架构 checklist、`appcast.xml` 和 `appcast-x86_64.xml`；SHA-256 分别为 arm64 zip `3e342a77ceaa83ce89b9dcc27212d1a044117d719df9711077da0281da891adb`、x86_64 zip `001d2265a276b37de331b482f55fbe904312c825cff8d4defaf1eca20a767c19`、arm64 checklist `688570291c35d56ccb490b7b045bc15c87364bc2a43d9b55a02a5408931770e7`、x86_64 checklist `606d15c373bacea98b664e5501c65eefecd455374ab0142177c0b8b7a97d9852`、arm64 appcast `448a98217e9d1c1e0f10a0e6be5b0d4e1b2f2d842bbd9aca00f5e8871f044691`、x86_64 appcast `7c0448b069d8a1c08e3249688a4baa2624ec870694e08f87a2839878399f8a0a`。本地重新下载两个 zip 后，`ditto` 解压、`xcrun stapler validate`、`codesign --verify --deep --strict` 和 `script/verify_desktop_release_arch.sh --arch arm64|x86_64` 均通过；两个 app bundle 内各有 86 个 Mach-O 文件包含目标架构 slice。

- 时间：2026-06-14。
- 验证范围：`v0.1.2` 正式双架构 desktop release。
- 结果确认：`release-desktop.yml` workflow run `27496496725` 在提交 `ffe505e76e0da0f5b7abcd6c8a22cbb48e7852c6` 上通过，并发布正式非 draft / 非 pre-release `v0.1.2`，该 release 已成为 GitHub Latest。CI 在 `macos-15` 上生成 `VibeLightApp-0.1.2-arm64-notarized.zip`，在 `macos-15-intel` 上生成 `VibeLightApp-0.1.2-x86_64-notarized.zip`，release asset 还包含 `desktop-firmware-release-0.1.2-arm64.md`、`desktop-firmware-release-0.1.2-x86_64.md`、`appcast.xml` 和 `appcast-x86_64.xml`；SHA-256 分别为 arm64 zip `b9055b3f00d2435955328d3239d5d22ba322f105c4a74121aa921e751adec980`、x86_64 zip `84f1b18e4d7057373e6bdd5a79c36b1bbd947b598af7c5d3c338ee73fef4a987`、arm64 checklist `80e0c65fc1afd67aa2f8c330e250e2b9f548e921e205ed5a3bf68c0934d4869e`、x86_64 checklist `cb2e6dbb2fb82bf8858e1d214eed2feafcd339f7a82fb908a9817fe22aba542a`、arm64 appcast `5918863125a56427f0706884be7a44a3f69f41b79d3096565a24a7a94358c3cc`、x86_64 appcast `c848e69abadbef8d912d1f8ca251bd0762bf368dca80552680ec7ab5b24db34c`。`https://github.com/miclle/vibe-light/releases/latest/download/appcast.xml` 和 `https://github.com/miclle/vibe-light/releases/latest/download/appcast-x86_64.xml` 均可匿名下载并指向 `v0.1.2` 对应架构 zip；本地重新下载两个 zip 后，`ditto` 解压、`xcrun stapler validate`、`codesign --verify --deep --strict` 和 `script/verify_desktop_release_arch.sh --arch arm64|x86_64` 均通过；两个 app bundle 内各有 86 个 Mach-O 文件包含目标架构 slice。

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

## 已完成发布闭环基线

- app 内固件烧录的首个发布闭环已完成：desktop 入口、固件包生成、manifest 校验、串口枚举、helper 参数生成、`vibe-light-firmware-flasher` wrapper、esptool 依赖 vendoring、内置 Python runtime、成功后 BLE 扫描和 health packet 展示都已落地。
- 发布形态资源已完成实机烟测：dist app resource 中的 helper 和固件包可通过 USB 写入目标板，vendored `python-packages` 路径可在无 Homebrew esptool 的 PATH 下工作，重启后 BLE 广播和 desktop 连接 / 状态写入正常；notarized app UI 已完成“读取芯片 -> 烧录固件 -> BLE 扫描 / 连接 -> health packet 展示”闭环。
- `script/prepare_desktop_firmware_release.sh`、`script/package_desktop_release.sh` 和 `script/desktop_firmware_release_checklist.sh` 已串起 ESP32 构建、固件包生成、esptool vendoring、helper 收窄 PATH 验证、Developer ID 签名、可选 notarization、Gatekeeper / codesign / Mach-O 架构检查、GPL/source gate 和 checklist 产出。
- macOS app 已接入 Sparkle 自动更新；默认 stable feed 已按架构拆分，Apple Silicon 指向 `releases/latest/download/appcast.xml`，Intel 指向 `releases/latest/download/appcast-x86_64.xml`。`v0.1.2` 已发布 Apple Silicon / Intel 分架构下载包并确认 latest appcast、下载包签名、notarization 和架构扫描通过；`v0.1.1` 下载包形态已人工确认 Sparkle stable feed、USB 固件烧录和 BLE 重连通过。
- 固件烧录 UI 已改成独立侧边栏入口和 step-by-step 向导，覆盖连接 USB、读取芯片、按需进入下载模式、确认并烧录、写入固件、RST 正常启动、BLE 连接和完成状态；读取前“烧录固件”禁用，确认 `ESP32-S3 (QFN56)` 和 MAC 后才启用写入入口，写入阶段会解析 esptool 输出显示实时 stage/progress，并保留完整实时日志。
- 发布合规基线已落地：`package_firmware_tools.py` 会生成 `FirmwareTools/THIRD_PARTY_NOTICES.md`、`OPEN_SOURCE_NOTICES.md`、`SOURCE_OFFER.md` 和 `sources/esptool-<version>.tar.gz`；Vibe Light 自有源码为 source-available 非商用许可，继续保留 GPL/source 材料即可。如果未来修改 bundled `esptool`，修改后的对应源码也必须按 GPLv2+ 提供，并同步更新 notice、source archive 和 hash。
- 方案细节和每次发布前的复核清单见 `docs/desktop-firmware-flashing.md`。后续 release 仍需重复下载包验证、真实芯片读取、UI 烧录、BLE 重连、Sparkle feed 检查和 GPL/source 材料人工审阅。

## 未完成事项

1. **ESP32 屏幕轻微闪烁需要底层排查**
   - 当前已知现象：即使没有竖屏吃豆人动画，屏幕也会有轻微闪烁。
   - 已尝试方向：停用 / 恢复竖屏动画 timer、局部迷宫刷新、双 framebuffer、减少动画重绘带宽、RGB VSYNC restart、三 framebuffer 轮转，以及 macOS 端 compact 包保留 `usage`。
   - 下一步建议优先复核 ST7701 初始化参数、RGB PCLK / hsync / vsync porch、bounce buffer、PSRAM 带宽、LCD driver VSYNC / DMA 生命周期、背光 PWM 频率和硬件供电稳定性；不要把问题只归因于 Pac-Man 动画。

2. **横屏 layout mode 需要实机复核**
   - 固件已用 QMI8658 加速度方向在竖屏 / 横屏之间切换；IMU 不可用时保持竖屏。
   - 横屏原型不改 BLE 协议，整屏展示由 `docs/Pac-Man-landscape.png` 生成的截图样式吃豆人画面，不额外叠加顶部或底部状态栏；`busy` 时计分、关卡和 `HIGH SCORE` 推进仍沿用竖屏同一套显示模型规则。
   - 下一步需要肉眼确认横放方向、旋转方向、整屏截图样式画面清晰度和 QMI8658 读数稳定性。

## 推荐推进顺序

1. **准备下一版公开发布入口**
   - 基于当前非商用许可准备下一版 release 或 beta。
   - 继续用真实用户路径重点观察首次打开、蓝牙授权、固件烧录向导、USB 串口识别、RST / BOOT 指引、烧录日志感知和 BLE 重连体验。

2. **守住现有竖屏和发布闭环**
   - 后续协议、任务摘要、硬件页或烧录页改动优先补测试和实机回归。
   - 每次发布前继续重复 GitHub release asset 下载、Gatekeeper / codesign、strict helper 和真机烧录验证。

3. **处理非阻塞发布治理**
   - 自有源码非商用许可和第三方 GPL/source 材料需要分开审阅；如果进入商业授权或商业分发，仍建议做最终法律 / 合规确认，重点复核 bundled `esptool` GPLv2+ source offer、源码归档和第三方 notices 的最终发布形态。

4. **实机确认横屏原型**
   - 横屏是产品方向探索，不是当前链路可靠性的前置条件。
   - 先用 host-side preview 快速确认布局，再通过目标板横放 / 竖立观察决定是否继续产品化为可配置展示模式。

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
