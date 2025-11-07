#!/usr/bin/env bash
set -euo pipefail

HOST="23.94.111.42"
PORT="22"
SSH_USER="syncuser"
SSH_PASS="nba0981057309"

APP_ID="com.sftpsync.filebrowser"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
CONF_DIR="$HOME/.sftp_sync"
CONF_FILE="$CONF_DIR/config.env"
PLIST="$HOME/Library/LaunchAgents/${APP_ID}.plist"

MODE="interactive"
CONFIG_JSON_PATH=""
TASK_ID=""
LOG_FILE=""
PYTHON_BIN=""

usage() {
  cat <<'EOF'
用法：
  ./sync.sh                          # 交互式配置并同步
  ./sync.sh --run-from-config        # 使用 env 配置文件（旧模式）
  ./sync.sh --config app.json --task <taskId>  # 使用 JSON 配置执行指定任务

可选参数：
  --config <path>    指定 app.json 路径（需与 --task 同时出现）
  --task <uuid>      指定任务 ID
  --help             显示本帮助
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-from-config)
        MODE="env"
        shift
        ;;
      --config)
        CONFIG_JSON_PATH="${2:-}"
        if [ -z "$CONFIG_JSON_PATH" ]; then
          echo "[-] --config 需要指定文件路径"
          exit 1
        fi
        shift 2
        ;;
      --task)
        TASK_ID="${2:-}"
        if [ -z "$TASK_ID" ]; then
          echo "[-] --task 需要指定任务 ID"
          exit 1
        fi
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "[-] 未知参数：$1"
        usage
        exit 1
        ;;
    esac
  done

  if [ -n "$CONFIG_JSON_PATH" ] || [ -n "$TASK_ID" ]; then
    if [ "$MODE" = "env" ]; then
      echo "[-] --run-from-config 与 --config/--task 不能一起使用"
      exit 1
    fi
    if [ -z "$CONFIG_JSON_PATH" ] || [ -z "$TASK_ID" ]; then
      echo "[-] --config 与 --task 必须同时提供"
      exit 1
    fi
    MODE="json"
  fi
}

ensure_deps() {
  if ! command -v lftp >/dev/null 2>&1; then
    echo "[*] 未检测到 lftp，尝试使用 Homebrew 安装..."
    if ! command -v brew >/dev/null 2>&1; then
      echo "[-] 未安装 Homebrew，请先安装后重试：https://brew.sh"
      exit 1
    fi
    brew install lftp
  fi
}

require_python() {
  PYTHON_BIN="$(command -v python3 || true)"
  if [ -z "$PYTHON_BIN" ]; then
    echo "[-] JSON 模式需要安装 python3"
    exit 1
  fi
}

read_inputs() {
  echo "请选择 FileBrowser 用户名（只能 yachen / xulei）："
  read -r -p "用户名: " FB_USER
  case "$FB_USER" in
    yachen|xulei) ;;
    *) echo "[-] 只能输入 yachen 或 xulei"; exit 1;;
  esac

  read -r -p "请输入需要同步的本地目录路径: " LOCAL_DIR
  LOCAL_DIR="${LOCAL_DIR/#\~/$HOME}" # 支持 ~
  if [ ! -d "$LOCAL_DIR" ]; then
    echo "[-] 本地目录不存在：$LOCAL_DIR"
    exit 1
  fi

  REMOTE_DIR="/data/${FB_USER}"
}

save_config() {
  mkdir -p "$CONF_DIR"
  cat > "$CONF_FILE" <<EOF
FB_USER="$FB_USER"
LOCAL_DIR="$LOCAL_DIR"
REMOTE_DIR="$REMOTE_DIR"
HOST="$HOST"
PORT="$PORT"
SSH_USER="$SSH_USER"
SSH_PASS="$SSH_PASS"
EOF
  echo "[*] 已保存配置到 $CONF_FILE"
}

load_config() {
  if [ ! -f "$CONF_FILE" ]; then
    echo "[-] 找不到配置文件：$CONF_FILE"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$CONF_FILE"
  # 兜底校验
  if [ ! -d "$LOCAL_DIR" ]; then
    echo "[-] 配置中的本地目录不存在：$LOCAL_DIR"
    exit 1
  fi
}

load_task_from_json() {
  local config_path="$1"
  local task_id="$2"
  if [ ! -f "$config_path" ]; then
    echo "[-] 找不到配置文件：$config_path"
    exit 1
  fi

  local parsed
  if ! parsed="$("$PYTHON_BIN" - "$config_path" "$task_id" <<'PY'
import json
import shlex
import sys
from pathlib import Path

if len(sys.argv) < 3:
    print("python 参数不足", file=sys.stderr)
    sys.exit(1)

config_path = sys.argv[1]
task_id = sys.argv[2]

with open(config_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

server = data.get("server") or {}
tasks = data.get("tasks") or []
task = next((t for t in tasks if t.get("id") == task_id), None)
if not server:
    print("配置中缺少 server 节点", file=sys.stderr)
    sys.exit(2)
if task is None:
    print(f"未找到任务 {task_id}", file=sys.stderr)
    sys.exit(3)

def emit(key, value):
    if value is None:
        return
    if isinstance(value, bool):
        value = "1" if value else "0"
    print(f'{key}={shlex.quote(str(value))}')

remote_base = server.get("remoteBaseDir") or "/"
remote_base = remote_base if remote_base.startswith("/") else f"/{remote_base}"
remote_base = "/" if remote_base == "" else remote_base.rstrip("/") or "/"

remote_rel = task.get("remoteDir") or ""
if remote_rel in (".", "/"):
    remote_rel = ""
remote_rel = remote_rel.strip("/")
if remote_rel:
    remote_full = f"{remote_base.rstrip('/')}/{remote_rel}".replace("//", "/")
else:
    remote_full = remote_base

local_dir = task.get("localDir") or server.get("defaultLocalDir") or ""
local_dir = str(Path(local_dir).expanduser())

emit("HOST", server.get("host", ""))
emit("PORT", server.get("port", 22))
emit("SSH_USER", server.get("username", ""))
emit("SSH_PASS", server.get("password", ""))
emit("REMOTE_BASE_DIR", remote_base)
emit("REMOTE_RELATIVE_DIR", remote_rel)
emit("REMOTE_DIR", remote_full)
emit("LOCAL_DIR", local_dir)
emit("TASK_INTERVAL", task.get("intervalMinutes", 60))
emit("TASK_ENABLED", task.get("enabled", False))
emit("TASK_NAME", task.get("name", ""))
emit("TASK_ID", task_id)
emit("CONFIG_JSON_PATH", config_path)
PY
)"; then
    echo "[-] 解析 JSON 配置失败"
    exit 1
  fi

  eval "$parsed"
  CONFIG_JSON_PATH="$config_path"
  TASK_ID="$task_id"

  LOCAL_DIR="${LOCAL_DIR/#\~/$HOME}"
  if [ -z "$LOCAL_DIR" ] || [ ! -d "$LOCAL_DIR" ]; then
    echo "[-] JSON 配置中的本地目录不存在：$LOCAL_DIR"
    exit 1
  fi
}

prepare_logging() {
  if [ -z "${CONFIG_JSON_PATH:-}" ] || [ -z "${TASK_ID:-}" ]; then
    return
  fi

  local config_dir
  config_dir="$(cd "$(dirname "$CONFIG_JSON_PATH")" && pwd)"
  local log_dir="$config_dir/logs"
  mkdir -p "$log_dir"
  LOG_FILE="$log_dir/${TASK_ID}-$(date +%Y%m%d-%H%M%S).log"
}

sync_once() {
  echo "[*] 开始同步：$LOCAL_DIR -> sftp://$HOST:$PORT$REMOTE_DIR"

  # 生成一个临时 lftp 脚本文件，避免 -e 字符串转义问题
  TMPFILE="$(mktemp /tmp/lftp_sync.XXXXXX)"
  trap 'rm -f "$TMPFILE"' EXIT

  # 用占位符写入脚本（单引号保留字面量）
  cat > "$TMPFILE" <<'LFTPEOF'
set sftp:auto-confirm yes
set net:max-retries 2
set net:timeout 20
open -u __SSH_USER__,__SSH_PASS__ sftp://__HOST__:__PORT__
lcd __LOCAL_DIR__
# 本地 -> 远程：使用当前目录点号，避免在 lftp 命令中直接引用长路径
mirror -R --continue --parallel=4 --delete --verbose . "__REMOTE_DIR__"
bye
LFTPEOF

  # macOS 的 sed -i 需要空备份后缀；对斜杠和 & 做转义
  _ESC_LOCAL=$(printf '%s' "$LOCAL_DIR" | sed 's/[\/&]/\\&/g')
  _ESC_REMOTE=$(printf '%s' "$REMOTE_DIR" | sed 's/[\/&]/\\&/g')

  sed -i '' \
    -e "s/__SSH_USER__/$SSH_USER/g" \
    -e "s/__SSH_PASS__/$SSH_PASS/g" \
    -e "s/__HOST__/$HOST/g" \
    -e "s/__PORT__/$PORT/g" \
    -e "s/__LOCAL_DIR__/$_ESC_LOCAL/g" \
    -e "s/__REMOTE_DIR__/$_ESC_REMOTE/g" \
    "$TMPFILE"

  lftp -f "$TMPFILE"
  echo "[*] 同步完成。"
  if [ -n "${LOG_FILE:-}" ]; then
    echo "[*] 日志文件：$LOG_FILE"
  fi
}

run_sync() {
  if [ -n "${LOG_FILE:-}" ]; then
    set +e
    sync_once 2>&1 | tee -a "$LOG_FILE"
    local status=${PIPESTATUS[0]}
    set -e
    return "$status"
  else
    sync_once
  fi
}

setup_launchd() {
  read -r -p "是否设置为自动同步？(y/N): " yn
  case "$yn" in
    [Yy]*)
      read -r -p "请填写同步间隔（分钟，>=1）: " MINUTES
      if ! [[ "$MINUTES" =~ ^[0-9]+$ ]] || [ "$MINUTES" -lt 1 ]; then
        echo "[-] 无效的分钟数"; exit 1
      fi
      mkdir -p "$CONF_DIR"
      cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>${APP_ID}</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${SCRIPT_PATH}</string>
      <string>--run-from-config</string>
    </array>
    <key>StartInterval</key><integer>$(( MINUTES * 60 ))</integer>
    <key>StandardOutPath</key><string>$CONF_DIR/launchd.out.log</string>
    <key>StandardErrorPath</key><string>$CONF_DIR/launchd.err.log</string>
    <key>RunAtLoad</key><true/>
  </dict>
</plist>
EOF
      launchctl unload "$PLIST" >/dev/null 2>&1 || true
      launchctl load "$PLIST"
      echo "[*] 已创建 LaunchAgent（每 ${MINUTES} 分钟执行一次）：$PLIST"
      ;;
    *) echo "[*] 跳过自动同步设置。";;
  esac
}

parse_args "$@"

case "$MODE" in
  env)
    ensure_deps
    load_config
    run_sync
    ;;
  json)
    ensure_deps
    require_python
    load_task_from_json "$CONFIG_JSON_PATH" "$TASK_ID"
    prepare_logging
    run_sync
    ;;
  interactive)
    ensure_deps
    read_inputs
    save_config
    run_sync
    setup_launchd
    ;;
  *)
    echo "[-] 未知运行模式：$MODE"
    exit 1
    ;;
esac
