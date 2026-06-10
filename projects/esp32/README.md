# ESP32 Firmware

这里是 Vibe Light 的 ESP32-S3 固件工程。

目标硬件为 Waveshare `ESP32-S3-LCD-3.16`，固件负责：

- 作为 BLE Peripheral 广播 `VibeLight-S3` 设备。
- 暴露 Vibe Light GATT service 和状态写入 / 健康状态特征。
- 接收 macOS 应用写入的 `StatusPacket`。
- 驱动 LCD 或 LED 输出 `idle`、`busy`、`waiting`、`success`、`error`、`offline` 等状态。

协议和硬件约束见：

- [架构设计](../../docs/architecture.md)
- [硬件记录](../../docs/hardware.md)

## 当前阶段

当前固件已经实现通信、解析、健康读取和竖屏显示的源码闭环：

- 广播设备名：`VibeLight-S3`
- GATT service：`7d8f0001-7b9a-4f0b-9e8a-8b4c2c7f1000`
- 状态写入 characteristic：`7d8f0002-7b9a-4f0b-9e8a-8b4c2c7f1000`
- 健康读取 characteristic：`7d8f0003-7b9a-4f0b-9e8a-8b4c2c7f1000`
- 状态包格式：UTF-8 JSON `StatusPacket`

屏幕驱动当前已接入 Waveshare `ESP32-S3-LCD-3.16` 的 ST7701 RGB LCD 初始化、主动低电平背光 PWM 和基础 RGB565 绘制。RGB panel 当前使用 16-bit data width、18MHz PCLK、PSRAM framebuffer、2 个 framebuffer 和 10 行 bounce buffer。`vibe_display_show_status` 会把状态写入串口日志，并在 LCD 上渲染顶部状态色、参考迷宫、任务计数和任务列表。

BLE Central 连接后，屏幕会显示 `idle / desktop connected`；断开后会显示 `offline / desktop disconnected`，避免设备停留在过期的任务状态上。

当前没有引入完整 LVGL，先用轻量 framebuffer 绘制确认 LCD 链路稳定。任务列表文字支持 ASCII 和 GB2312 一级常用中文及常用中文标点混排；构建时会生成 18x18、2-bit 抗锯齿中文字体 asset 并嵌入固件。

## 当前屏幕行为

固件当前支持 `v: 1` 单状态包和 `v: 2` 多任务列表包：

- 顶部色条居中显示 `VIBE LIGHT`，颜色来自整体 `state`；如果状态包带有 Codex 用量，会同时显示 `CODEX: 5H ... 7D ...` 剩余百分比。
- 中间面板显示 Codex 吃豆人参考迷宫任务舞台，不再重复显示 `source` 或 `x running` 调试文字。
- `tasks[]` 非空时，底部贴边任务面板显示紧凑的 `A`、`W`、`E` 计数和最多 5 条任务行；任务标题右侧会显示 `CTX` 上下文已用百分比。
- `tasks[]` 为空时显示 `NO ACTIVE TASKS` 和整体状态标题。
- 未知顶层状态或任务状态降级为 `idle`；缺少必需 `state` 或非法 JSON 时拒绝包，并保持旧显示状态。
- 状态写入长度达到 1024 字节及以上时会被拒绝；桌面端会按 BLE `maximumWriteLength` 尝试把过大的 `v: 2` 包降级为 `v: 1`。
- 重复包通过 `vibe_display_model` 的渲染签名去重，减少静态界面重复重绘；签名包含版本、来源、状态、详情、计数、Codex 用量和最多 5 条任务文本。

`busy` 状态会启动 Codex 吃豆人中部迷宫动画：

- 动画由 `esp_timer` 周期 tick 驱动，周期为 240ms。
- 任务列表里有几个任务，就显示几个主角；没有任务列表时回退到 `activeCount`。
- 主角沿参考迷宫路径移动，本轮已经吃过的豆子保持隐藏，等所有豆子都被吃完后再一次性重置，嘴型随 tick 开合。
- 主角数量限制在 1 到 5 个；当前路径步进保持离散节点和中点插值，不再按 `activeCount` 加速。
- 切换到非 `busy` 状态后停止 timer，避免动画占用 BLE 或解析路径。

## 关键模块

| 文件 | 职责 |
| --- | --- |
| `main/vibe_ble.*` | BLE Peripheral、GATT service、状态写入特征和健康读取特征。 |
| `main/vibe_status.*` | `StatusPacket` JSON 解析、状态枚举和未知状态降级。 |
| `main/vibe_cjk_font.*` | 嵌入式 GB2312 一级中文字体查找和 UTF-8 解码。 |
| `main/vibe_display_model.*` | 渲染签名、任务行格式、紧凑计数、参考迷宫坐标、本轮已吃豆子隐藏、角色数量和角色嘴型。 |
| `main/vibe_display.*` | ST7701 LCD 初始化、PSRAM framebuffer、背光 PWM、RGB565 绘制和动画 timer。 |
| `tests/vibe_status_parser_test.c` | host-side parser 与 display-model 回归测试。 |

## 构建

仓库根目录的 Makefile 已封装常用命令：

```bash
make esp32-test
make esp32-preview
make esp32-build
make esp32-flash ESP32_PORT=/dev/cu.usbmodemXXXX
```

安装并启用 ESP-IDF 后，也可以在本目录直接执行：

```bash
get_idf
idf.py set-target esp32s3
idf.py build
```

当前本机使用 ESP-IDF v5.5.1 构建通过。`get_idf` 会先避开 PlatformIO 的 Python 环境，再加载 `/Users/miclle/esp/esp-idf/export.sh`。

中文字体 asset 由 `tools/generate_cjk_font.py` 在构建期生成。生成脚本需要可 `import PIL` 的 Python 解释器；CMake 会优先使用 `VIBE_CJK_FONT_PYTHON` 指定的解释器，再查找本机常见 Python 路径。字体源可用 `VIBE_CJK_FONT=/path/to/font.ttf` 覆盖，默认优先使用 macOS 系统中文字体。

固件使用 `partitions.csv` 自定义分区表，当前 `factory` app 分区为 4MB，适配中文字体 asset 后的固件体积增长。

烧录和串口监视：

```bash
projects/esp32/tools/flash_firmware.sh /dev/cu.usbmodemXXXX
```

进入 `esp_idf_monitor` 后，按 `Ctrl+]` 退出串口监视；按 `Ctrl+T` 后再按 `Ctrl+H` 可查看 monitor 快捷键帮助。

只烧录、不进入串口监视：

```bash
projects/esp32/tools/flash_firmware.sh --flash-only /dev/cu.usbmodemXXXX
```

如果无法进入下载模式，按住 BOOT 后单击 RST，再重新执行烧录命令。

Host-side 快速测试：

```bash
projects/esp32/tests/run_status_parser_tests.sh
```

本地生成吃豆人迷宫和全屏布局预览：

```bash
projects/esp32/tools/render_maze_preview.py /tmp/vibe-maze-preview.png
projects/esp32/tools/render_maze_preview.py --full-screen /tmp/vibe-screen-preview.png
```

仓库级快速验证：

```bash
./script/verify.sh --quick
```

## 联调

1. 烧录固件并打开串口日志。
2. 启动 macOS app。
3. 在“硬件设备”中扫描并连接 `VibeLight-S3`。
4. 点击发送最近状态包。
5. LCD 应显示顶部状态色、参考迷宫、底部任务计数和任务摘要；串口也会输出类似内容：

   ```text
   Vibe Light | source=codex state=busy detail=running shell ts=...
   ```
