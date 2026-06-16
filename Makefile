SHELL := /bin/bash
export PAGER := cat
export GIT_PAGER := cat
export LESS := -FRX

ROOT_DIR := $(CURDIR)
MACOS_DIR := $(ROOT_DIR)/projects/macos/desktop
ESP32_DIR := $(ROOT_DIR)/projects/esp32
IDF_PATH ?= /Users/miclle/esp/esp-idf
ESP32_PORT ?= /dev/cu.usbmodem1101
ESP32_BAUD ?= 460800
IDF_SAFE_PATH := /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$(PATH)

.DEFAULT_GOAL := help

.PHONY: help
help:
	@printf 'Vibe Light 开发命令\n\n'
	@printf '通用:\n'
	@printf '  make check-env         检查本机开发环境和依赖\n'
	@printf '  make setup             交互式安装缺失的开发环境依赖\n'
	@printf '  make quick             运行快速验证，不构建 ESP32 固件\n'
	@printf '  make verify            运行完整验证，包含 ESP32 固件构建\n'
	@printf '  make docs-context      汇总文档刷新所需的当前项目事实\n'
	@printf '  make docs-check        检查文档改动、agent 引用和兼容 symlink\n'
	@printf '  make whitespace        用 git diff --check 检查空白字符问题\n'
	@printf '  make clean             删除本地构建产物\n\n'
	@printf 'macOS 桌面端:\n'
	@printf '  make desktop-build     构建 SwiftPM 桌面端 package\n'
	@printf '  make desktop-test      运行 Swift 测试\n'
	@printf '  make desktop-run       构建并启动 app bundle\n'
	@printf '  make desktop-debug     构建并用 lldb 启动 app\n'
	@printf '  make desktop-logs      启动 app 并监听进程日志\n'
	@printf '  make desktop-telemetry 启动 app 并监听应用 telemetry 日志\n'
	@printf '  make desktop-verify    启动 app 并验证进程已运行\n'
	@printf '  make notary-store      从 .env 创建/刷新 notarytool Keychain profile\n'
	@printf '  make notary-validate   验证 .env 中的 notarization 凭证\n'
	@printf '  make firmware-release  准备 desktop app 内置固件烧录发布资源\n'
	@printf '  make desktop-release   运行 desktop 固件烧录发布 checklist\n'
	@printf '  make desktop-release-notarized 读取 .env 并运行 notarized checklist\n'
	@printf '  make hook-sample       发送一条 Codex hook 示例事件\n\n'
	@printf 'ESP32 固件:\n'
	@printf '  make idf-shell         进入已激活 ESP-IDF 的 shell\n'
	@printf '  make esp32-test        运行 host-side parser/display-model 测试\n'
	@printf '  make esp32-preview     生成 /tmp 下的迷宫和整屏预览 PNG\n'
	@printf '  make esp32-build       使用 ESP-IDF 构建固件\n'
	@printf '  make esp32-flash       烧录固件并打开串口 monitor\n'
	@printf '  make esp32-flash-only  只烧录固件，不打开串口 monitor\n\n'
	@printf '变量:\n'
	@printf '  IDF_PATH=%s\n' '$(IDF_PATH)'
	@printf '  ESP32_PORT=%s\n' '$(ESP32_PORT)'
	@printf '  ESP32_BAUD=%s\n' '$(ESP32_BAUD)'

.PHONY: check-env setup quick verify docs-context docs-check whitespace clean
check-env:
	$(ROOT_DIR)/script/setup_env.sh --check

setup:
	$(ROOT_DIR)/script/setup_env.sh --install

quick:
	$(ROOT_DIR)/script/verify.sh --quick

verify:
	$(ROOT_DIR)/script/verify.sh --full

docs-context:
	$(ROOT_DIR)/script/docs_refresh_context.sh

docs-check:
	$(ROOT_DIR)/script/docs_check.sh

whitespace:
	git -C $(ROOT_DIR) diff --check

clean:
	rm -rf $(ROOT_DIR)/dist
	rm -rf $(MACOS_DIR)/.build
	rm -rf $(ESP32_DIR)/build

.PHONY: desktop-build desktop-test desktop-run desktop-debug desktop-logs desktop-telemetry desktop-verify notary-store notary-validate firmware-release desktop-release desktop-release-notarized hook-sample
desktop-build:
	swift build --package-path $(MACOS_DIR)

desktop-test:
	swift test --package-path $(MACOS_DIR)

desktop-run:
	$(ROOT_DIR)/script/build_and_run.sh run

desktop-debug:
	$(ROOT_DIR)/script/build_and_run.sh --debug

desktop-logs:
	$(ROOT_DIR)/script/build_and_run.sh --logs

desktop-telemetry:
	$(ROOT_DIR)/script/build_and_run.sh --telemetry

desktop-verify:
	$(ROOT_DIR)/script/build_and_run.sh --verify

notary-store:
	$(ROOT_DIR)/script/notary_credentials.sh store

notary-validate:
	$(ROOT_DIR)/script/notary_credentials.sh validate

firmware-release:
	$(ROOT_DIR)/script/prepare_desktop_firmware_release.sh

desktop-release:
	$(ROOT_DIR)/script/desktop_firmware_release_checklist.sh

desktop-release-notarized:
	$(ROOT_DIR)/script/desktop_release_notarized.sh

hook-sample:
	printf '%s\n' '{"source":"codex","event":"PreToolUse","detail":"running shell"}' | swift run --package-path $(MACOS_DIR) vibe-light-hook

.PHONY: check-idf idf-shell esp32-test esp32-preview esp32-build esp32-flash esp32-flash-only
check-idf:
	@test -f "$(IDF_PATH)/export.sh" || { \
		echo "ESP-IDF export.sh not found at $(IDF_PATH)/export.sh. Set IDF_PATH to an ESP-IDF checkout." >&2; \
		exit 1; \
	}

idf-shell: check-idf
	export PATH="$(IDF_SAFE_PATH)" && source "$(IDF_PATH)/export.sh" >/tmp/vibe-idf-export.log && cd "$(ESP32_DIR)" && exec "$${SHELL:-/bin/zsh}"

esp32-test:
	IDF_PATH="$(IDF_PATH)" $(ESP32_DIR)/tests/run_status_parser_tests.sh

esp32-preview:
	$(ESP32_DIR)/tools/render_maze_preview.py /tmp/vibe-maze-preview.png
	$(ESP32_DIR)/tools/render_maze_preview.py --full-screen /tmp/vibe-screen-preview.png
	$(ESP32_DIR)/tools/render_maze_preview.py --landscape-screen /tmp/vibe-landscape-preview.png

esp32-build: check-idf
	export PATH="$(IDF_SAFE_PATH)" && source "$(IDF_PATH)/export.sh" >/tmp/vibe-idf-export.log && cd "$(ESP32_DIR)" && idf.py build

esp32-flash:
	IDF_PATH="$(IDF_PATH)" ESP32_PORT="$(ESP32_PORT)" ESP32_BAUD="$(ESP32_BAUD)" $(ESP32_DIR)/tools/flash_firmware.sh "$(ESP32_PORT)"

esp32-flash-only:
	IDF_PATH="$(IDF_PATH)" ESP32_PORT="$(ESP32_PORT)" ESP32_BAUD="$(ESP32_BAUD)" $(ESP32_DIR)/tools/flash_firmware.sh --flash-only "$(ESP32_PORT)"
