# Vibe Light 当前待办

这个文件记录项目当前状态下最值得继续推进的工作。README 保持产品概览，架构和协议细节放在 `docs/architecture.md`，硬件事实放在 `docs/hardware.md`。

## 当前状态

- macOS SwiftPM app 已有通用、智能体安装、硬件设备和事件四个主要界面。
- Hook CLI 会把 Codex / Claude 事件写入本地 `events.jsonl`，桌面端轮询事件并通过 `TaskTracker` 聚合多任务状态。
- BLE 协议当前以 `v: 2` 多任务状态包为主，保留 `v: 1` 降级路径。
- ESP32-S3 固件已接入 BLE Peripheral、状态解析、健康读取特征、ST7701 LCD 初始化、RGB565 framebuffer 绘制和 Codex 吃豆人 `busy` 动画。
- 近期源码已包含 ESP32 显示模型和 parser 测试演进，文档应继续以这些源码事实为准。

## 近期优先级

1. **完成 ESP32 显示闭环实机验证**
   - 烧录 `projects/esp32` 固件到 Waveshare `ESP32-S3-LCD-3.16`。
   - 从 macOS “硬件设备”页连接 `VibeLight-S3` 并发送最近状态包。
   - 核对屏幕顶部状态、任务列表、`idle` / `offline` 切换和 `busy` 动画是否与源码一致。

2. **收紧显示模型测试**
   - 继续把动画路径、嘴型方向、重复包去重、任务行格式和未知状态降级保持在 host-side C 测试里。
   - 新增屏幕布局或状态表现时，优先测试 `vibe_display_model.*`，避免让硬件渲染细节变成不可验证的黑盒。

3. **完善硬件实机诊断**
   - 记录实际烧录端口、ESP-IDF 版本和实机验证结果。
   - 确认背光 PWM、LCD 初始化序列和 PSRAM framebuffer 在目标板上的稳定性。
   - 如果需要，将健康状态包扩展到背光、heap、渲染 tick 或最近解析错误。

4. **整理产品化显示方向**
   - 保持 macOS 端只发送状态和任务摘要，不传逐帧动画。
   - ESP32 端继续承担动画 tick、边缘豆子、角色形状和屏幕局部视觉规则。
   - 需要中文字体、复杂布局或设置页时，再评估是否引入 LVGL。
   - 暂时保留竖屏作为默认稳定模式，因为当前设备外观和摆放更适合竖向状态灯。
   - 新增横屏 layout mode 作为实验方向，不改 BLE 协议，先只调整 ESP32 渲染布局。
   - 横屏原型建议采用“左侧状态 / 中间 Codex 动画 / 右侧任务列表 / 顶部或底部统计条”的信息架构。
   - 实机对比竖屏和横屏后，再决定是否产品化为可配置展示模式。

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
