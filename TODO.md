# Vibe Light 当前待办

这个文件记录项目当前状态下最值得继续推进的工作。README 保持产品概览，架构和协议细节放在 `docs/architecture.md`，硬件事实放在 `docs/hardware.md`。

## 当前状态

- macOS SwiftPM app 已有通用、智能体安装、硬件设备和事件四个主要界面。
- Hook CLI 会把 Codex / Claude 事件写入本地 `events.jsonl`，桌面端轮询事件并通过 `TaskTracker` 聚合多任务状态。
- BLE 协议当前以 `v: 2` 多任务状态包为主，保留 `v: 1` 降级路径；Codex 用量摘要会从 transcript 最新 `token_count` 事件提取，并提供 5h / 7d 剩余百分比、低余量 reset 提示和每条 Codex 任务的上下文已用百分比 / token 摘要。
- ESP32-S3 固件已接入 BLE Peripheral、状态解析、健康读取特征、ST7701 LCD 初始化、RGB565 framebuffer 绘制和 Codex 吃豆人 `busy` 迷宫动画。
- 显示模型已从“简单任务列表”推进到 320px 参考迷宫舞台、213 个豆子、4 个能量豆、最多 5 个错相主角、底部贴边任务面板、任务时长 / 新鲜度尾标和渲染签名去重。
- 屏幕任务详情会优先展示当前工具动作，例如 `Bash / TEST make quick`、`Bash / SEARCH StatusPacket` 或 `Edit / README.md`，避免只显示泛化任务摘要。
- `waiting` 任务详情会优先展示审批目标，例如 `APPROVE Bash TEST make verify` 或 `ALLOW Edit README.md`，让屏幕直接提示下一步需要处理什么。
- 任务行右侧会展示新鲜度、运行时长和上下文用量，例如 `RUN 03:12`、`WAIT 01:08`、`2m ago`、`CTX xx%` 或 `CTX 4.2K/12K`；活跃任务会在运行时长和 `CTX` 之间低频轮播，高上下文占用时提高 `CTX` 出现频率。
- 屏幕页脚会在左下方显示短状态，例如 `CODEX LIVE`；旧协议包显示为 `CODEX LEGACY`，不直接暴露 `v1` / `v2` 这类内部协议版本。活跃/等待/错误计数只保留在迷宫里的 `ACTIVE` / `WAIT` / `ERR` 计数区，避免重复。页脚使用中性灰并与底边保留 12px 余量，避免贴到屏幕最底部；任务状态色块内缩显示，避免在屏幕边缘形成蓝色竖线。
- 固件连接状态已经会主动刷新屏幕：Central 连接时显示 `idle / desktop connected`，断开时显示 `offline / desktop disconnected`。
- 健康状态包已经包含运行时长、BLE 连接状态、最近显示状态、heap 余量、启动后 heap 低水位和渲染 tick；macOS 硬件页会展示这些诊断信息。
- 仓库级快速验证会运行 Swift 测试、ESP32 host-side C 测试、生成迷宫 / 全屏 PNG 预览并执行 Git whitespace 检查；ESP32 显示闭环已完成一次实机烧录和屏幕确认。
- 固件版本 `61a603d` 已在目标板完成烧录、串口启动、BLE 连接和短稳定性采样：LCD 初始化、BLE 广播、Central 连接和连续 `v: 2` 状态写入均正常。后续仍需要肉眼复核最近显示修正和健康诊断扩展在屏幕 / macOS 硬件页上的实际观感。

## 最近实机验证

- 时间：2026-06-11。
- 端口：`/dev/cu.usbmodem2101`。
- 固件版本：`61a603d`。
- ESP-IDF：v5.5。
- 芯片：ESP32-S3，8MB PSRAM。
- 串口日志确认：应用正常启动，App version 为 `61a603d`，LCD 初始化成功，BLE 广播名为 `VibeLight-S3`，macOS 桌面端能连接并连续写入 `v: 2` 状态包。
- 短稳定性采样：5 分钟串口观察内 hard error 0、断连 0、状态写入 144 次、显示渲染 147 次；日志保存在本机 `/tmp/vibe-light-stability-clean-61a603d.log`。
- 屏幕确认：未在本轮自动化验证中肉眼复核；下一次需要重点看 token 摘要、`CODEX LIVE` / `CODEX LEGACY` 页脚、12px 底部余量、任务色块内缩、无边缘蓝线和 macOS 硬件页健康读数。

## 历史实机验证

- 时间：2026-06-11。
- 端口：`/dev/cu.usbmodem2101`。
- 固件版本：`090391d`。
- ESP-IDF：v5.5。
- 芯片：ESP32-S3，8MB PSRAM。
- 串口日志确认：应用正常启动，LCD 初始化成功，BLE 广播名为 `VibeLight-S3`，macOS 桌面端能连接并连续写入 `v: 2` 状态包。
- 屏幕确认：未在本轮自动化验证中肉眼复核；后续显示修正提交不能视为已完成实机屏幕确认。

## 更早实机验证

- 时间：2026-06-10。
- 端口：`/dev/cu.usbmodem2101`。
- 固件版本：`353426d`。
- ESP-IDF：v5.5。
- 芯片：ESP32-S3，8MB PSRAM。
- 串口日志确认：应用正常启动，LCD 初始化成功，BLE 广播名为 `VibeLight-S3`，macOS 桌面端能连接并写入 `v: 2` 状态包。
- 屏幕确认：high score、顶部 Codex 5H / 7D 用量、底部任务列表显示正常。
- 说明：这是一次历史实机确认，不代表后续显示修正提交都已经重新烧录到板上确认。

## 未完成事项

1. **烧录并肉眼复核最近显示修正**
   - `61a603d` 已完成烧录、串口启动、BLE 连接和连续 `v: 2` 写入确认。
   - 下一步优先肉眼复核 token 摘要、`CODEX LIVE` / `CODEX LEGACY` 页脚、12px 底部余量、任务色块内缩、无边缘蓝线和健康诊断扩展后的硬件页读数。
   - 继续记录后续屏幕观察结果；2026-06-10 的 `353426d` 屏幕确认不能代表后续提交。

2. **做一轮长时间运行稳定性观察**
   - `61a603d` 已完成 5 分钟短采样，未发现 hard error 或断连；这只是冒烟检查，不替代 30-60 分钟观察。
   - 观察 PSRAM framebuffer、ST7701 刷新、BLE 重连、动画 timer、主动低电平背光 PWM 和健康特征读取是否稳定。
   - 建议至少覆盖空闲、busy 动画、waiting、错误包恢复、重复包去重、低余量 reset 提示和任务尾标轮播。
   - 如果稳定性观察暴露问题，优先把可复现判断沉到 `vibe_display_model.*` 或 parser 测试，再处理硬件绘制层。

3. **补充硬件诊断字段**
   - 健康状态包已有 uptime、connected、lastState、heap 和 animationTick；后续可继续补背光状态和最近解析错误。
   - macOS 硬件页应继续保持为诊断视图，不把这些工程信息常驻到默认主屏。

4. **保持显示模型测试随功能演进收紧**
   - 已有 host-side C 测试覆盖动画路径、重复包去重、任务行格式、未知状态降级、底部布局、整轮豆子重置、用量显示和中文任务文本。
   - 新增屏幕布局、状态表现、迷宫素材、坐标或缩放规则时，仍需同步更新 `vibe_display_model.*`、`render_maze_preview.py` 和 parser 测试断言。

5. **优化上屏摘要规则**
   - 当前工具动作、等待态审批文案、任务新鲜度 / 运行时长 / `CTX`、token 摘要、低余量 reset 提示、footer 和 `LAST OK` / `LAST ERR` 都已实现基础展示。
   - 后续可继续基于实机可读性微调不同工具的动词和对象摘要、高上下文占用提示阈值、轮播节奏、最近结果摘要来源和保留时长。
   - 仍不建议上屏完整 prompt、完整命令输出、raw JSON、长路径、详细 token 分项或复杂多页菜单。

6. **横屏 layout mode 仍是实验方向**
   - 暂时保留竖屏作为默认稳定模式，因为当前设备外观和摆放更适合竖向状态灯。
   - 横屏原型不需要改 BLE 协议，先只调整 ESP32 渲染布局。
   - 建议原型信息架构为“左侧状态 / 中间 Codex 动画 / 右侧任务列表 / 顶部或底部统计条”。
   - 实机对比竖屏和横屏后，再决定是否产品化为可配置展示模式。

## 推荐推进顺序

1. **先做实机闭环**
   - 价值最高，能验证最近几次显示修正是否真的在屏幕上成立。
   - 建议命令顺序：`make quick`、`make esp32-flash`、启动 macOS app 连接 `VibeLight-S3`、发送真实或演示 `v: 2` 包、肉眼检查屏幕和硬件页健康读数。

2. **再做 30-60 分钟稳定性观察**
   - 实机视觉正确后再观察长时间运行，避免把布局问题和稳定性问题混在一起。
   - 重点看动画是否卡住、BLE 是否断连后恢复、heap 低水位是否持续下降、footer 和任务尾标是否有残影或遮挡。

3. **随后补背光状态和最近解析错误**
   - 这是诊断面的自然下一步，范围小，能提升后续实机排查效率。
   - 推荐同时更新 `HealthPacket`、固件 health JSON、macOS 硬件页、Swift 测试、协议文档和硬件文档。

4. **最后再评估横屏原型**
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
