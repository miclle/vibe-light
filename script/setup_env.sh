#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDF_VERSION="${IDF_VERSION:-v5.5}"
IDF_PATH="${IDF_PATH:-$HOME/esp/esp-idf}"
RUN_INSTALL=0
ASSUME_YES=0
USE_CHINA_MIRROR=0
SAFE_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

usage() {
  cat <<EOF
usage: script/setup_env.sh [--check|--install] [--yes] [--china-mirror]

Options:
  --check         Only check the local environment. This is the default.
  --install       Install missing dependencies where possible.
  --yes           Do not prompt before install actions.
  --china-mirror  Prefer Espressif China mirror for ESP-IDF tool downloads.
  -h, --help      Show this help.

Environment:
  IDF_PATH     ESP-IDF checkout path. Defaults to $HOME/esp/esp-idf
  IDF_VERSION  ESP-IDF git tag or branch. Defaults to v5.5
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      RUN_INSTALL=0
      shift
      ;;
    --install)
      RUN_INSTALL=1
      shift
      ;;
    --yes|-y)
      ASSUME_YES=1
      shift
      ;;
    --china-mirror)
      USE_CHINA_MIRROR=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

info() {
  printf '==> %s\n' "$1"
}

ok() {
  printf '  OK  %s\n' "$1"
}

warn() {
  printf '  !!  %s\n' "$1"
}

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi

  local answer
  read -r -p "$prompt [y/N] " answer
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

refresh_homebrew_path() {
  local brew_bin
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_bin" ]]; then
      PATH="$(dirname "$brew_bin"):$PATH"
      export PATH
      return 0
    fi
  done
}

first_existing_python() {
  local candidate
  for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  command -v python3 2>/dev/null || true
}

require_macos() {
  info "检查系统"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    warn "当前脚本面向 macOS。其他系统请参考 ESP-IDF 官方安装文档。"
    exit 1
  fi
  ok "macOS"
}

ensure_xcode_cli() {
  info "检查 Xcode Command Line Tools"
  if xcode-select -p >/dev/null 2>&1; then
    ok "Xcode Command Line Tools 已安装"
    return
  fi

  warn "缺少 Xcode Command Line Tools"
  if [[ "$RUN_INSTALL" == "1" ]] && confirm "是否打开 Xcode Command Line Tools 安装器？"; then
    xcode-select --install || true
    warn "安装完成后请重新运行本脚本。"
  else
    warn "可运行: xcode-select --install"
  fi
}

ensure_rosetta() {
  if [[ "$(uname -m)" != "arm64" ]]; then
    return
  fi

  info "检查 Apple Silicon Rosetta"
  if /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    ok "Rosetta 已可用"
    return
  fi

  warn "未检测到 Rosetta。部分旧版 Xtensa 工具链可能需要它。"
  if [[ "$RUN_INSTALL" == "1" ]] && confirm "是否安装 Rosetta？"; then
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
  else
    warn "如遇到 bad CPU type in executable，可运行: /usr/sbin/softwareupdate --install-rosetta --agree-to-license"
  fi
}

ensure_homebrew() {
  info "检查 Homebrew"
  refresh_homebrew_path
  if have_command brew; then
    ok "Homebrew: $(brew --version | head -n 1)"
    return
  fi

  warn "缺少 Homebrew"
  if [[ "$RUN_INSTALL" == "1" ]]; then
    warn "Homebrew 安装脚本需要交互确认。请按官方提示完成。"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    refresh_homebrew_path
    if have_command brew; then
      ok "Homebrew: $(brew --version | head -n 1)"
    else
      warn "Homebrew 已执行安装脚本，但当前脚本仍找不到 brew。请按安装器提示更新 PATH 后重新运行。"
    fi
  else
    warn "可运行: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  fi
}

ensure_brew_packages() {
  info "检查 Homebrew 依赖"
  refresh_homebrew_path
  if ! have_command brew; then
    warn "跳过 Homebrew 依赖检查：brew 不存在"
    return
  fi

  local missing=()
  local spec command_name package_name
  for spec in cmake:cmake ninja:ninja dfu-util:dfu-util ccache:ccache python3:python git:git; do
    command_name="${spec%%:*}"
    package_name="${spec##*:}"
    if have_command "$command_name"; then
      ok "$command_name 已安装"
    else
      warn "$command_name 未安装"
      missing+=("$package_name")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    if [[ "$RUN_INSTALL" == "1" ]] && confirm "是否安装缺失的 Homebrew 依赖：${missing[*]}？"; then
      brew install "${missing[@]}"
    else
      warn "可运行: brew install ${missing[*]}"
    fi
  fi
}

ensure_swift() {
  info "检查 Swift"
  if have_command swift; then
    local swift_output swift_version
    swift_output="$(swift --version 2>&1)"
    swift_version="$(printf '%s\n' "$swift_output" | grep -m 1 'Swift version' || true)"
    if [[ -z "$swift_version" ]]; then
      swift_version="$(printf '%s\n' "$swift_output" | head -n 1)"
    fi
    ok "$swift_version"
  else
    warn "缺少 swift。通常安装 Xcode Command Line Tools 后会提供。"
  fi
}

ensure_python_for_esp_idf() {
  info "检查 ESP-IDF 安装用 Python"
  local current_python selected_python
  current_python="$(command -v python3 2>/dev/null || true)"
  selected_python="$(first_existing_python)"

  if [[ -z "$selected_python" ]]; then
    warn "未找到 python3。可运行: brew install python"
    return
  fi

  if [[ "$current_python" == *"/.platformio/"* ]]; then
    warn "当前 shell 的 python3 来自 PlatformIO: $current_python"
    warn "安装 ESP-IDF 时将临时优先使用: $selected_python"
  else
    ok "python3: $current_python"
  fi
}

clone_or_update_esp_idf() {
  info "检查 ESP-IDF"
  if [[ -f "$IDF_PATH/export.sh" ]]; then
    ok "ESP-IDF: $IDF_PATH"
    return
  fi

  warn "未找到 ESP-IDF: ${IDF_PATH}"
  if [[ "$RUN_INSTALL" != "1" ]]; then
    warn "可运行: script/setup_env.sh --install"
    return
  fi

  if ! have_command git; then
    warn "缺少 git，无法下载 ESP-IDF。"
    return
  fi

  if [[ -e "$IDF_PATH" ]]; then
    warn "${IDF_PATH} 已存在但没有 export.sh，请检查目录或设置 IDF_PATH。"
    return
  fi

  if confirm "是否下载 ESP-IDF ${IDF_VERSION} 到 ${IDF_PATH}？"; then
    mkdir -p "$(dirname "$IDF_PATH")"
    git clone -b "$IDF_VERSION" --recursive https://github.com/espressif/esp-idf.git "$IDF_PATH"
  fi
}

install_esp_idf_tools() {
  info "检查 ESP-IDF 工具链"
  if [[ ! -f "$IDF_PATH/install.sh" ]]; then
    warn "跳过 ESP-IDF 工具链安装：${IDF_PATH}/install.sh 不存在"
    return
  fi

  local has_tools=0
  if [[ -d "$HOME/.espressif/tools" ]]; then
    has_tools=1
    ok "已检测到 $HOME/.espressif/tools"
  else
    warn "未检测到 $HOME/.espressif/tools"
  fi

  if [[ "$RUN_INSTALL" == "1" ]] && confirm "是否安装 ESP32-S3 工具链和 Python 依赖？"; then
    if [[ "$USE_CHINA_MIRROR" == "1" ]]; then
      export IDF_GITHUB_ASSETS="dl.espressif.cn/github_assets"
    fi
    (cd "$IDF_PATH" && PATH="$SAFE_PATH:$PATH" ./install.sh esp32s3)
  elif [[ "$has_tools" != "1" ]]; then
    warn "可运行: cd \"${IDF_PATH}\" && ./install.sh esp32s3"
  fi
}

check_project_commands() {
  info "检查项目命令"
  if [[ -f "$IDF_PATH/export.sh" ]]; then
    ok "可运行: IDF_PATH=\"${IDF_PATH}\" make quick"
    ok "可运行: IDF_PATH=\"${IDF_PATH}\" make esp32-build"
    ok "可运行: IDF_PATH=\"${IDF_PATH}\" make idf-shell"
  else
    warn "ESP-IDF 未就绪，make quick / make esp32-build 的 ESP32 部分会失败。"
  fi

  if [[ -f "$ROOT_DIR/Makefile" ]]; then
    ok "可运行: make help"
  fi
}

print_next_steps() {
  cat <<EOF

完成后建议执行：
  cd "$ROOT_DIR"
  make quick
  make esp32-build

项目的 Make 命令会自动加载 ESP-IDF。只有需要手动运行 idf.py 时，才需要：
  make idf-shell

如果 ESP-IDF 安装在非默认路径：
  IDF_PATH="/path/to/esp-idf" make quick
EOF
}

require_macos
ensure_xcode_cli
ensure_rosetta
ensure_homebrew
ensure_brew_packages
ensure_swift
ensure_python_for_esp_idf
clone_or_update_esp_idf
install_esp_idf_tools
check_project_commands
print_next_steps
