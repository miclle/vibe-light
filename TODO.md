# Vibe Light 当前待办

这个文件记录项目当前状态下最值得继续推进的工作。README 保持产品概览，架构和协议细节放在 `docs/architecture.md`，硬件事实放在 `docs/hardware.md`。

## 当前状态

- macOS SwiftPM app 已有通用、智能体安装、硬件设备和事件四个主要界面。
- Hook CLI 会把 Codex / Claude 事件写入本地 `events.jsonl`，桌面端轮询事件并通过 `TaskTracker` 聚合多任务状态。
- BLE 协议当前以 `v: 2` 多任务状态包为主，保留 `v: 1` 降级路径；Codex 用量摘要会从 transcript 最新 `token_count` 事件提取，并提供 5h / 7d 剩余百分比、低余量 reset 提示和每条 Codex 任务的上下文已用百分比。
- ESP32-S3 固件已接入 BLE Peripheral、状态解析、健康读取特征、ST7701 LCD 初始化、RGB565 framebuffer 绘制和 Codex 吃豆人 `busy` 迷宫动画。
- 显示模型已从“简单任务列表”推进到 320px 参考迷宫舞台、213 个豆子、4 个能量豆、最多 5 个错相主角、底部贴边任务面板、任务时长 / 新鲜度尾标和渲染签名去重。
- 屏幕任务详情会优先展示当前工具动作，例如 `Bash / TEST make quick`、`Bash / SEARCH StatusPacket` 或 `Edit / README.md`，避免只显示泛化任务摘要。
- `waiting` 任务详情会优先展示审批目标，例如 `APPROVE Bash TEST make verify` 或 `ALLOW Edit README.md`，让屏幕直接提示下一步需要处理什么。
- 任务行右侧会展示新鲜度、运行时长和上下文用量，例如 `RUN 03:12`、`WAIT 01:08`、`2m ago`、`CTX xx%` 或 `CTX 4.2K/12K`；活跃任务会在运行时长和 `CTX` 之间低频轮播，高上下文占用时提高 `CTX` 出现频率。
- 屏幕页脚会在左下方显示短状态，例如 `CODEX LIVE`；旧协议包显示为 `CODEX LEGACY`，不直接暴露 `v1` / `v2` 这类内部协议版本。活跃/等待/错误计数只保留在迷宫里的 `ACTIVE` / `WAIT` / `ERR` 计数区，避免重复。页脚使用中性灰并与底边保留 12px 余量，避免贴到屏幕最底部；任务状态色块内缩显示，避免在屏幕边缘形成蓝色竖线。
- 固件连接状态已经会主动刷新屏幕：Central 连接时显示 `idle / desktop connected`，断开时显示 `offline / desktop disconnected`。
- 仓库级快速验证会运行 Swift 测试、ESP32 host-side C 测试、生成迷宫 / 全屏 PNG 预览并执行 Git whitespace 检查；ESP32 显示闭环已完成一次实机烧录和屏幕确认。
- 实机闭环记录停留在 2026-06-10 的 `353426d` 固件；之后合入的 token 摘要、页脚位置、页脚去重、协议版本隐藏和边缘色块修正已通过本地验证，但还需要下一次刷当前 HEAD 到目标板复核。

## 最近实机验证

- 时间：2026-06-10。
- 端口：`/dev/cu.usbmodem2101`。
- 固件版本：`353426d`。
- ESP-IDF：v5.5。
- 芯片：ESP32-S3，8MB PSRAM。
- 串口日志确认：应用正常启动，LCD 初始化成功，BLE 广播名为 `VibeLight-S3`，macOS 桌面端能连接并写入 `v: 2` 状态包。
- 屏幕确认：high score、顶部 Codex 5H / 7D 用量、底部任务列表显示正常。
- 说明：这是一次历史实机确认，不代表后续显示修正提交都已经重新烧录到板上确认。

## 近期优先级

1. **继续收紧显示模型测试**
   - 继续把动画路径、嘴型方向、重复包去重、任务行格式、未知状态降级、底部布局和整轮豆子重置保持在 host-side C 测试里。
   - 用量显示和中文任务文本也应继续保持在 Swift 测试与 host-side C 测试的组合覆盖里。
   - 新增屏幕布局或状态表现时，优先测试 `vibe_display_model.*`，避免让硬件渲染细节变成不可验证的黑盒。
   - 修改参考迷宫素材、坐标或缩放规则时，同步更新 `render_maze_preview.py` 和 parser 测试断言。

2. **完善硬件实机诊断**
   - 下一次实机验证优先刷当前 HEAD，重点复核 token 摘要、`CODEX LIVE` / `CODEX LEGACY` 页脚、12px 底部余量、任务色块内缩和无边缘蓝线。
   - 继续记录后续烧录端口、ESP-IDF 版本和实机验证结果。
   - 已确认当前固件可在目标板上启动 ST7701 LCD、BLE 广播和 PSRAM framebuffer；后续仍需在更多运行时长下观察稳定性。
   - 如果需要，将健康状态包扩展到背光、heap、渲染 tick 或最近解析错误。

3. **整理产品化显示方向**
   - 保持 macOS 端只发送状态和任务摘要，不传逐帧动画。
   - ESP32 端继续承担动画 tick、参考迷宫、整轮豆子重置、角色形状和屏幕局部视觉规则。
   - 中文字体已由轻量 framebuffer + GB2312 一级 2-bit 位图 asset 支持；复杂布局或设置页再评估是否引入 LVGL。
   - 暂时保留竖屏作为默认稳定模式，因为当前设备外观和摆放更适合竖向状态灯。
   - 新增横屏 layout mode 作为实验方向，不改 BLE 协议，先只调整 ESP32 渲染布局。
   - 横屏原型建议采用“左侧状态 / 中间 Codex 动画 / 右侧任务列表 / 顶部或底部统计条”的信息架构。
   - 实机对比竖屏和横屏后，再决定是否产品化为可配置展示模式。

4. **评估可追加上屏信息**
   - 当前工具动作已实现基础展示，例如 `Bash / TEST make quick`、`Bash / FLASH make esp32-flash`、`Edit / README.md`、`Read / TaskTracker.swift`。后续可继续优化不同工具的动作摘要规则。
   - 等待态文案已实现基础展示，例如 `APPROVE Bash TEST make verify` 或 `ALLOW Edit README.md`，避免只看到泛化的等待状态。后续可继续细化不同工具的动词和对象摘要。
   - 任务新鲜度、运行时长和上下文用量已实现基础展示，例如 `RUN 03:12`、`WAIT 01:08`、`2m ago`、`CTX xx%` 或 `CTX 4.2K/12K`；活跃任务会在运行时长和 `CTX` 之间低频轮播，高上下文占用时提高 `CTX` 出现频率。
   - 页脚短状态已左对齐显示来源和链路状态，例如 `CODEX LIVE`；旧协议包显示 `CODEX LEGACY`。页脚使用中性灰并与底边保留 12px 余量；任务状态色块内缩显示，任务计数由迷宫里的 `ACTIVE` / `WAIT` / `ERR` 计数区承载。
   - 上下文用量已从单纯 `CTX xx%` 扩展到 token 摘要；后续可继续评估高占用提示阈值和轮播节奏。
   - Codex 5h / 7d reset 时间已在低余量时提示，例如 `CODEX: 5H RESET 45m`；后续可继续评估阈值和轮播节奏。
   - 空闲状态已能显示最近完成或最近失败的任务摘要，例如 `LAST OK vibe-light` 或 `LAST ERR firmware`，让 `NO ACTIVE TASKS` 更有上下文；后续可继续优化摘要来源和保留时长。
   - 诊断模式可显示设备本地健康信息，例如运行时长、BLE 状态、heap、最近解析错误或渲染 tick；默认主屏不常驻，避免变成工程调试面板。
   - 不建议上屏完整 prompt、完整命令输出、raw JSON、长路径、详细 token 分项或复杂多页菜单；屏幕信息应保持短、准、能指导下一步。

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
