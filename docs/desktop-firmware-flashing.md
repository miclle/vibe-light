# macOS App Integrated Firmware Flashing

本文记录在 macOS desktop 应用内集成 ESP32-S3 固件烧录能力的可行性和推荐实现路径。

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

## 推荐方案

推荐走“desktop 应用烧录预编译固件”的路线，而不是在用户机器上安装或内置完整 ESP-IDF。

发布流程提前构建并签名一份固件包，desktop app 随包携带该固件包，运行时只负责通过串口把预编译二进制写入设备 flash。

建议固件包结构：

```text
FirmwareBundle/
  manifest.json
  bootloader.bin
  partition-table.bin
  vibe_light_esp32.bin
```

`manifest.json` 至少记录：

- 固件版本和构建 commit。
- 目标芯片：`esp32s3`。
- 目标硬件：Waveshare `ESP32-S3-LCD-3.16`。
- flash mode / freq / size。
- offset 到 bin 文件的映射。
- 每个 bin 文件的 SHA-256。
- 最低 desktop app 版本。

## macOS 端实现轮廓

desktop app 可新增一个 `FirmwareFlasher` 服务，职责保持独立：

1. 枚举候选串口，例如 `/dev/cu.usbmodem*`、`/dev/cu.wchusbserial*`、`/dev/cu.SLAB_USBtoUART*`。
2. 读取 app bundle 内置的 `FirmwareBundle/manifest.json`。
3. 校验固件包完整性和 SHA-256。
4. 调用烧录 helper 执行 `write_flash`。
5. 将烧录阶段、百分比、日志摘要和失败原因回传给 SwiftUI。
6. 烧录完成后触发硬件页 BLE 扫描，并尝试连接 `VibeLight-S3` 读取 health packet。

UI 建议放在“硬件设备”页，作为独立的“固件烧录”区域：

- 未连接 USB 时提示插入设备。
- 发现多个串口时让用户选择。
- 烧录前显示目标固件版本和硬件型号。
- 烧录中显示进度和当前阶段。
- 如果进入下载模式失败，提示按住 BOOT 后单击 RST，再重试。
- 烧录成功后自动扫描 BLE 并读取设备健康状态。

## 烧录工具选择

最小可行实现可以复用 Espressif `esptool` 的 `write_flash` 能力。`esptool` 支持按 offset 写入多个二进制文件，正好匹配当前 `flasher_args.json` 的信息。

实现时需要重点评估：

- `esptool` 的许可证和分发方式。
- 是否把 Python runtime / esptool 打包进 app bundle。
- 是否改用独立 helper tool，便于签名、权限和日志隔离。
- 是否需要未来替换为更小的原生 Swift / C / Rust 烧录实现。

第一版建议把烧录能力封装成独立 helper，desktop app 只通过受控参数启动 helper 并读取结构化进度。这样主应用 UI、BLE 逻辑和串口烧录边界清晰，后续替换底层烧录实现也更容易。

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

## 分阶段计划

1. **原型阶段**
   - 从当前 `build/flasher_args.json` 和 bin 产物生成本地固件包。
   - 写一个命令行 helper，输入端口和固件包路径，执行免 ESP-IDF 烧录。
   - 在开发机上用目标板验证烧录、重启、BLE 广播和 health 读取。

2. **应用集成阶段**
   - 把固件包作为 app resource 打包。
   - 在“硬件设备”页新增固件烧录区域。
   - 增加串口枚举、端口选择、进度展示、失败提示和成功后 BLE 扫描。

3. **发布阶段**
   - 给固件包增加版本、校验和 release notes。
   - 验证 app bundle 签名、helper 签名、notarization 和 sandbox 权限。
   - 建立发布构建流程，确保 desktop app 和内置固件版本可追踪。

4. **体验优化阶段**
   - 自动识别最可能的 ESP32-S3 端口。
   - 支持从远端下载新版固件包并校验签名。
   - 增加“恢复出厂固件”或“重新烧录当前版本”入口。

## 结论

该功能可行，并且非常符合 Vibe Light 的产品方向。推荐优先实现“应用内烧录预编译固件”，避免让普通用户安装 ESP-IDF。最大的工程风险不在固件本身，而在 macOS 分发权限、helper 签名、烧录工具许可证和失败恢复体验。
