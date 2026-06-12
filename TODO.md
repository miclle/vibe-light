# Vibe Light 当前待办

这个文件记录项目当前状态下最值得继续推进的工作。README 保持产品概览，架构和协议细节放在 `docs/architecture.md`，硬件事实放在 `docs/hardware.md`。

## 当前状态

- macOS SwiftPM app 已有通用、智能体安装、硬件设备和事件四个主要界面。
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
- macOS 硬件页已经有“固件烧录”区域，可枚举常见 ESP32 USB 串口、加载并校验内置 `FirmwareBundle`、调用 helper 执行 `write_flash`，成功后启动 BLE 扫描；`projects/esp32/tools/package_firmware_bundle.py` 可从 ESP-IDF build 产物生成带 SHA-256 的 app resource 固件包，`projects/esp32/tools/package_firmware_tools.py` 可把 `esptool` 依赖 vendor 到 `FirmwareTools/python-packages/`。
- 仓库级快速验证会运行 Swift 测试、ESP32 host-side C 测试、生成迷宫 / 全屏 PNG 预览并执行 Git whitespace 检查；ESP32 显示闭环已完成一次实机烧录和屏幕确认。
- 固件版本 `82d2180` 已在目标板完成烧录、串口启动、BLE 连接、健康特征实机读取、肉眼屏幕复核和长时间稳定性观察：LCD 初始化、BLE 广播、Central 连接、连续 `v: 2` 状态写入、token 摘要、页脚、底部余量、任务色块内缩、无边缘蓝线、macOS 硬件页健康读数和稳定性表现均正常；坏状态包后会回传 `lastParseError:"invalid JSON"`。
- 固件版本 `3215f23` 已完成目标板烧录和实机观察，确认结构拆分后的固件启动、屏幕显示和 BLE 链路正常。

## 最近实机验证

- 时间：2026-06-12。
- 端口：`/dev/cu.usbmodem2101`。
- 固件版本：`524c46d`（boot log `App version`；本地 app resource manifest 为 `dev-test` / `27040bf`）。
- 验证范围：`dist/VibeLightApp.app` 携带的 `FirmwareBundle` + `FirmwareTools/vibe-light-firmware-flasher` 发布形态资源烟测。
- 结果确认：helper 在默认 PATH 下通过 `esptool.py v4.8.1` 完成写入；在收窄 PATH `/usr/bin:/bin:/usr/sbin:/sbin` 下通过 vendored `python-packages` 的 `esptool.py v4.11.0` 再次完成写入，均识别 `ESP32-S3 (QFN56)`，bootloader、partition table 和 app 三段写入 hash verified。重启后串口确认 `LCD initialized`、`advertising as VibeLight-S3`、desktop Central connected，并收到连续 `v:2` 状态写入。
- UI 闭环补充：同一天通过 macOS “硬件设备”页点击“烧录固件”完成一次 app UI 路径烧录；UI 展示 `esptool.py v4.8.1` 写入日志、三段 hash verified、自动扫描，随后重新连接 `VibeLight-S3` 并读取 health packet，健康卡显示运行时间、连接、运行中状态、背光开启、heap 余量和渲染 tick。

- 时间：2026-06-12。
- 验证范围：内置 Python runtime 发布资产准备。
- 结果确认：使用本机 PlatformIO portable Python 3.11.7 arm64 候选 runtime 运行 `script/prepare_desktop_firmware_release.sh --skip-esp32-build --version dev-test --minimum-desktop-version dev --python-runtime /Users/miclle/.platformio/python3 --require-bundled-python` 成功；生成 `FirmwareTools/python` 约 105MB、`python-packages` 约 37MB、`FirmwareBundle` 约 1MB；收窄 PATH + strict helper 输出 `esptool.py v4.11.0`，并通过 bundled Python import smoke 覆盖 `esptool`、`pyserial`、`cryptography`、`PyYAML` 和 `cffi`。

- 时间：2026-06-12。
- 验证范围：本地 Developer ID 签名发布包。
- 结果确认：使用 `SIGNING_IDENTITY="Developer ID Application: Miclle Zheng (6UG7DDAY6C)" script/package_desktop_release.sh` 成功生成 `dist/VibeLightApp.app` 和 `dist/release/VibeLightApp-26a8c33.zip`；脚本签名并验证 83 个 nested Mach-O 文件，覆盖 app、hook、内置 Python runtime、Python `lib-dynload` 和 vendored wheel `.so`；主 app 签名显示 Team ID `6UG7DDAY6C`、hardened runtime、timestamp 和 sealed resources。签名后的 helper 在收窄 PATH + strict 模式下输出 bundled `esptool.py v4.11.0`，签名 app 可短暂启动；未 notarize 时 Gatekeeper 结果为 `Unnotarized Developer ID`。

- 时间：2026-06-12。
- 验证范围：notarization 凭证预检。
- 结果确认：`script/package_desktop_release.sh --notarize` 已支持 build/sign 前凭证校验和命令行覆盖 `NOTARYTOOL_PROFILE` / Apple API key 参数；本机尚未配置 `vibe-light-notary` profile，也未检测到 Apple API key 环境变量，因此 notarization 提交待配置凭证后继续。

- 时间：2026-06-12。
- 验证范围：Developer ID notarized desktop app。
- 结果确认：`SIGNING_IDENTITY="Developer ID Application: Miclle Zheng (6UG7DDAY6C)" NOTARYTOOL_PROFILE=vibe-light-notary script/package_desktop_release.sh --notarize` 已跑通，Apple Notary submission `d923ce8c-d4f9-4a03-b26b-008a2f5ec9a4` 返回 `Accepted`；`xcrun stapler validate dist/VibeLightApp.app` 通过，`spctl -a -vv --type execute dist/VibeLightApp.app` 返回 `accepted / source=Notarized Developer ID`；`codesign -dvvv` 显示 `Notarization Ticket=stapled`、Team ID `6UG7DDAY6C`、hardened runtime 和 sealed resources；签名 + notarized app 内 helper 在收窄 PATH + strict 模式下输出 bundled `esptool.py v4.11.0`；notarized app 可短暂启动。继续用 notarized app bundle 内 helper 对 `/dev/cu.usbmodem1101` 执行非破坏性 `chip_id` 读取，识别 `ESP32-S3 (QFN56)`、BLE、8MB PSRAM 和 MAC `1c:db:d4:7b:3f:cc`。随后在 notarized app UI 点击“烧录固件”，完成 bootloader、partition table 和 app 三段写入，日志显示三段 `Hash of data verified`；烧录后 app 扫描到 `VibeLight-S3`，重新连接并读取 health packet，健康卡显示运行时间、连接已连接、最近状态运行中、背光开启、heap 约 6.7 MB 和 render tick。

- 时间：2026-06-11。
- 端口：`/dev/cu.usbmodem1101`。
- 固件版本：`3215f23`。
- 验证范围：结构治理后的 ESP32 固件烧录和实机观察。
- 结果确认：启动、屏幕显示和 BLE 链路观察正常。

## 历史验证归档

- `524c46d`：已完成目标板烧录；macOS 演示包提交 `939583d` 增加了 `CTX color` 场景，并已通过实机肉眼复核：80% 及以上 `CTX` 黄色提示、90% 及以上红色提示显示正常。
- `82d2180`：已完成串口启动、BLE 连接、连续 `v: 2` 写入、健康特征读取、坏 JSON parse error 回传、屏幕肉眼复核和长时间稳定性观察。
- `61a603d`：5 分钟串口采样内 hard error 0、断连 0、状态写入 144 次、显示渲染 147 次；日志在 `/tmp/vibe-light-stability-clean-61a603d.log`。
- `090391d` / `353426d`：早期实机启动、BLE 写入和基础屏幕显示确认；仅作为历史参考，不代表后续显示修正已重新复核。

## 未完成事项

1. **完成 app 内固件烧录的发布闭环**
   - 当前已完成 desktop 入口、固件包生成、manifest 校验、串口枚举、helper 参数生成、`vibe-light-firmware-flasher` wrapper、esptool 依赖 vendoring 和成功后 BLE 扫描。
   - 发布形态资源已完成实机烟测：dist app resource 中的 helper 和固件包可通过 USB 写入目标板，vendored `python-packages` 路径可在无 Homebrew esptool 的 PATH 下工作，重启后 BLE 广播和 desktop 连接 / 状态写入正常；macOS UI 点击“烧录固件”也已完成烧录、扫描、连接和 health packet 展示闭环。
   - `script/prepare_desktop_firmware_release.sh` 已提供发布资产准备入口，串起 ESP32 构建、固件包生成、esptool vendoring 和 helper 收窄 PATH 验证；`package_firmware_tools.py` 会生成 `FirmwareTools/THIRD_PARTY_NOTICES.md` 供发布审阅。
   - 第一版发布路线已切到内置 Python runtime：`package_firmware_tools.py --python-runtime <path> --require-python-runtime` 可复制 runtime 到 `FirmwareTools/python/`，`VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1` 可验证 helper 不依赖系统 Python、Homebrew `esptool` 或用户 PATH；本地 PlatformIO portable Python 3.11.7 arm64 候选已完成 release-prep 和 import smoke。
   - `script/package_desktop_release.sh` 已提供本地 Developer ID 签名验证入口，可生成 `dist/VibeLightApp.app`、签名 bundle 内 nested Mach-O、签 resource bundle / 主 app、执行 `codesign --verify`、归档 zip，并支持显式 `--notarize` 后先校验凭证再提交、staple 和 Gatekeeper 校验。
   - UI 已能针对下载模式、串口占用、写入校验失败、非 ESP32-S3 设备和 helper runtime 缺失给出明确恢复提示。
   - 下一步需要确认可分发 Python runtime 的正式来源和许可证，并完整审阅生成的 esptool/Python 许可证材料。
   - notarized app bundle 内 helper 已能访问 `/dev/cu.usbmodem1101` 并读取 `ESP32-S3 (QFN56)` 芯片信息；notarized app UI 已完成完整串口烧录、BLE 扫描 / 连接和 health packet 展示闭环。
   - dev app UI 已补齐烧录前芯片确认：读取前“烧录固件”禁用，点击“读取芯片”确认 `ESP32-S3 (QFN56)` 和 MAC 后才启用写入入口，避免直接进入写入。
   - 方案细节见 `docs/desktop-firmware-flashing.md`。

2. **保持显示模型测试随功能演进收紧**
   - 已有 host-side C 测试覆盖动画路径、重复包去重、任务行格式、未知状态降级、底部布局、整轮豆子重置、用量显示和中文任务文本。
   - 新增屏幕布局、状态表现、迷宫素材、坐标或缩放规则时，仍需同步更新 `vibe_display_model.*`、`render_maze_preview.py` 和 parser 测试断言。

3. **横屏 layout mode 仍是实验方向**
   - 暂时保留竖屏作为默认稳定模式，因为当前设备外观和摆放更适合竖向状态灯。
   - 横屏原型不需要改 BLE 协议，先只调整 ESP32 渲染布局。
   - 建议原型信息架构为“左侧状态 / 中间 Codex 动画 / 右侧任务列表 / 顶部或底部统计条”。
   - 实机对比竖屏和横屏后，再决定是否产品化为可配置展示模式。

## 推荐推进顺序

1. **先守住现有竖屏闭环**
   - 后续协议、任务摘要或硬件页改动优先补测试和实机回归，不再为已确认显示项保留单独待办。

2. **再评估横屏原型**
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
