# Vibe Light Agent Guide

本仓库是 macOS 桌面应用 + ESP32-S3 固件 + BLE 协议的组合项目。Agent 开始工作前先读这个文件，再按需读取 `.agents/rules/` 中的具体规则。

## 项目事实

- macOS 桌面端在 `projects/macos/desktop`，使用 SwiftPM、SwiftUI 和 CoreBluetooth。
- ESP32-S3 固件在 `projects/esp32`，目标硬件是 Waveshare `ESP32-S3-LCD-3.16`，优先使用 ESP-IDF。
- 跨端协议和架构记录在 `docs/architecture.md`。
- 硬件事实和官方资料入口记录在 `docs/hardware.md`。
- 当前待办和近期验证重点记录在 `TODO.md`。

## 必读规则

- `@.agents/rules/project-architecture.md`：跨端架构、协议边界和状态职责。
- `@.agents/rules/macos-desktop.md`：Swift 桌面端、hook、BLE 和测试规则。
- `@.agents/rules/esp32-firmware.md`：ESP32 固件、LCD、动画和 host-side 测试规则。
- `@.agents/rules/docs-workflow.md`：文档同步和提交范围规则。
- `@.agents/skills/docs-refresh.md`：当用户要求“根据项目现状更新文档”时的具体流程。

## 工作约束

- 先用 `git status --short --branch` 看清楚本地分支和已有改动；不要回滚用户未提交的代码。
- 回答架构、协议或硬件能力问题时，优先追源码和当前文档，不凭印象回答。
- README 保持产品和上手视角；实现细节放到 `docs/architecture.md`、`projects/esp32/README.md`、`TODO.md` 或 `.agents/rules/`。
- 跨 macOS / ESP32 协议变更必须同时核对 `StatusModels.swift`、`TaskTracker.swift`、`vibe_status.*`、`vibe_display_model.*` 和协议文档。
- 固件显示逻辑尽量把可测试的状态转换、任务行格式、动画路径和去重判断放在 `vibe_display_model.*`，再由 `vibe_display.c` 做硬件绘制。

## 常用验证

```bash
./script/verify.sh --quick
```

完整验证需要 ESP-IDF：

```bash
./script/verify.sh
```

文档-only 改动至少运行：

```bash
git diff --check
```
