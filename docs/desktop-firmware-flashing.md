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
- macOS app 已经有“硬件设备”页，包含 BLE 扫描、连接、状态写入、健康读取和演示包发送能力，适合作为固件烧录入口。

## 当前实现

当前已经采用“desktop 应用烧录预编译固件”的路线，而不是在用户机器上安装或内置完整 ESP-IDF。

发布流程提前构建并签名一份固件包，desktop app 随包携带该固件包，运行时只负责通过串口把预编译二进制写入设备 flash。已落地的代码边界如下：

- `projects/esp32/tools/package_firmware_bundle.py`：从 `projects/esp32/build/flasher_args.json` 和 bin 产物生成 app resource 使用的 `FirmwareBundle`。
- `projects/esp32/tools/package_firmware_tools.py`：把 `esptool` 及其 Python 依赖 vendor 到 app resource 的 `FirmwareTools/python-packages/`。
- `projects/macos/desktop/Sources/VibeLightCore/FirmwareFlashing.swift`：解析 manifest、按 offset 排序写入项、校验每个 bin 的 SHA-256、生成 `esptool write_flash` 参数，并枚举 macOS 常见 ESP32 串口。
- `projects/macos/desktop/Sources/VibeLightApp/Models/VibeLightAppModel.swift`：加载内置固件包、刷新串口、调用烧录 helper、记录日志，并在成功后启动 BLE 扫描。
- `projects/macos/desktop/Sources/VibeLightApp/Views/HardwareDevicesPane.swift`：在“硬件设备”页新增“固件烧录”区域，提供串口选择、刷新、烧录按钮、状态文本和 helper 日志摘要。
- `projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareTools/vibe-light-firmware-flasher`：app 内置烧录 helper，接受 `esptool` 兼容参数，优先使用同目录 vendor 的 runtime，开发环境可 fallback 到本机 `esptool`。

2026-06-12 已完成一次发布形态资源实机烟测：`dist/VibeLightApp.app` 中的 `FirmwareBundle` 和 `FirmwareTools/vibe-light-firmware-flasher` 可在 `/dev/cu.usbmodem2101` 写入目标 ESP32-S3；默认 PATH 下使用 `esptool.py v4.8.1` 成功，收窄 PATH 到 `/usr/bin:/bin:/usr/sbin:/sbin` 后使用 vendored `python-packages` 的 `esptool.py v4.11.0` 成功。两次写入均完成 bootloader、partition table 和 app 分区 hash 校验。重启后串口确认 `LCD initialized`、`advertising as VibeLight-S3`、desktop Central connected 和连续 `v:2` 状态写入。

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

生成的 `manifest.json` 和 bin 文件会写入 `projects/macos/desktop/Sources/VibeLightApp/Resources/FirmwareBundle/`，`esptool` 依赖会写入 `Resources/FirmwareTools/python-packages/`，这些生成产物被 `.gitignore` 忽略；发布构建应在构建 app 前执行这些步骤。

## macOS 端流程

desktop app 的职责保持独立：

1. 枚举候选串口，例如 `/dev/cu.usbmodem*`、`/dev/cu.wchusbserial*`、`/dev/cu.SLAB_USBtoUART*`。
2. 读取 app bundle 内置的 `FirmwareBundle/manifest.json`。
3. 校验固件包完整性和 SHA-256。
4. 调用烧录 helper 执行 `write_flash`。
5. 将状态、日志摘要和失败原因回传给 SwiftUI。
6. 烧录完成后触发硬件页 BLE 扫描，用户可连接 `VibeLight-S3` 并读取 health packet。

UI 位于“硬件设备”页的独立“固件烧录”区域：

- 未连接 USB 时提示插入设备。
- 发现多个串口时让用户选择。
- 烧录前显示目标固件版本和硬件型号。
- 烧录中显示当前状态和 helper 输出摘要。
- 如果进入下载模式失败，提示按住 BOOT 后单击 RST，再重试。
- 烧录成功后自动扫描 BLE 并读取设备健康状态。

## 烧录工具选择

最小可行实现复用 Espressif `esptool` 的 `write_flash` 能力。`esptool` 支持按 offset 写入多个二进制文件，正好匹配当前 `flasher_args.json` 的信息。

当前 app 会优先查找 app resource 中的 `FirmwareTools/vibe-light-firmware-flasher`，该 helper 接受 `esptool` 兼容参数。helper 会优先使用同目录的 `python/bin/python3` + `esptool.py` / `esptool/` / `python-packages/`，开发环境下也会尝试本机常见的 `esptool` / `esptool.py` 路径，便于验证 UI 和参数生成。发布前仍需要重点评估：

- `esptool` 的许可证和分发方式。
- 是否把 Python runtime 也打包进 app bundle，或限制第一版 Developer ID 包依赖系统 `/usr/bin/python3`。
- 独立 helper tool 的签名、权限和日志隔离。
- 是否需要未来替换为更小的原生 Swift / C / Rust 烧录实现。

第一版已经把烧录能力封装在独立 helper 边界后面，desktop app 只通过受控参数启动 helper 并读取输出。这样主应用 UI、BLE 逻辑和串口烧录边界清晰，后续替换底层烧录实现也更容易。

## 签名和权限风险

macOS 分发前必须实测签名、notarization 和 sandbox 行为。

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

## 发布前剩余工作

1. **helper 打包**
   - 当前已在 `Resources/FirmwareTools/` 放入可签名的 `vibe-light-firmware-flasher` wrapper，并能通过 vendored `python-packages` 加载 `esptool`。
   - 明确 helper 是否继续依赖系统 `/usr/bin/python3`，还是内置 Python runtime 或改为更小的原生烧录实现。
   - 记录 `esptool` 许可证和随包分发材料。

2. **真实应用闭环验证**
   - 已用 `dist/VibeLightApp.app` resource 通过 USB 烧录目标板，并验证重启、BLE 广播、desktop 连接和状态写入。
   - 仍需在 SwiftUI 内点击“烧录固件”完成同一路径，并读取 health packet 展示结果。
   - 每次发布前记录实测端口、固件版本、app 版本和 helper 版本。

3. **发布签名**
   - 给固件包增加版本、校验和 release notes。
   - 验证 app bundle 签名、helper 签名、notarization 和 sandbox 权限。
   - 建立发布构建流程，确保 desktop app 和内置固件版本可追踪。

4. **体验优化**
   - 自动识别最可能的 ESP32-S3 端口。
   - 支持从远端下载新版固件包并校验签名。
   - 增加“恢复出厂固件”或“重新烧录当前版本”入口。

## 结论

该功能已经具备 app 内入口、固件包校验、串口发现、helper 调用和成功后 BLE 扫描的最小闭环。最大的剩余工程风险不在固件本身，而在 macOS 分发权限、helper 签名、烧录工具许可证和真实发布包的失败恢复体验。
