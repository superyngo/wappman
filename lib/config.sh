#!/bin/bash
# lib/config.sh - Configuration loading & validation
#
# Provides: load_config(), create_config_template(), preflight_check()
# Depends on: CONF, SCRIPT_DIR, SERVICE_NAME (globals), log()

load_config() {
  if [ ! -f "$CONF" ]; then
    echo "ERROR: Configuration file not found: $CONF"
    echo "Use '$0 config $SERVICE_NAME' to create it."
    return 1
  fi
  
  source "$CONF"
  
  # Required fields
  : "${APP_EXEC:?ERROR: APP_EXEC is required in $CONF}"
  
  # Optional fields with defaults (paths include SERVICE_NAME for isolation)
  MANAGER_LOG_FILE="${MANAGER_LOG_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/wappman/logs/wappman_${SERVICE_NAME}.log}"
  APP_LOG_FILE="${APP_LOG_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/wappman/logs/app_${SERVICE_NAME}.log}"
  STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/wappman/${SERVICE_NAME}/state}"
  WATCH_FILES="${WATCH_FILES:-}"
  RESTART_FILE="${RESTART_FILE:-}"
  HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-5}"
  RESTART_MIN_INTERVAL="${RESTART_MIN_INTERVAL:-2}"
  RESTART_DELAY="${RESTART_DELAY:-0}"
  STOP_TIMEOUT="${STOP_TIMEOUT:-10}"
  APP_ARGS="${APP_ARGS:-}"
  SUCCESS_CHECK_COMMAND="${SUCCESS_CHECK_COMMAND:-}"
  SUCCESS_CHECK_DELAY="${SUCCESS_CHECK_DELAY:-${RESTART_DELAY}}"
  CRASH_RESTART_MAX="${CRASH_RESTART_MAX:-0}"
  CRASH_COMMAND="${CRASH_COMMAND:-}"
  LOG_RETAIN_DAYS="${LOG_RETAIN_DAYS:-7}"
  
  # Convert relative paths to absolute
  [[ "$MANAGER_LOG_FILE" = /* ]] || MANAGER_LOG_FILE="$SCRIPT_DIR/$MANAGER_LOG_FILE"
  [[ "$STATE_DIR" = /* ]] || STATE_DIR="$SCRIPT_DIR/$STATE_DIR"
  
  # Convert APP_LOG_FILE to absolute if set
  if [ -n "$APP_LOG_FILE" ]; then
    [[ "$APP_LOG_FILE" = /* ]] || APP_LOG_FILE="$SCRIPT_DIR/$APP_LOG_FILE"
  fi
}

create_config_template() {
  mkdir -p "$(dirname "$CONF")"
  cat > "$CONF" << TMPLEOF
# ${SERVICE_NAME}.conf
# wappman configuration for service: ${SERVICE_NAME}

# ===================================================================
# 應用程式基本設定
# ===================================================================

# 應用程式執行檔路徑 (必填)
APP_EXEC="/path/to/your/app"

# 應用程式啟動參數 (選填)
# 範例: APP_ARGS='--port 8080 --name "My App" --flag'
APP_ARGS=""

# 狀態檔案儲存目錄 (存放 PID、state、lock 等檔案)
# 預設使用 XDG Base Directory 規範
STATE_DIR="\${XDG_STATE_HOME:-\$HOME/.local/state}/wappman/${SERVICE_NAME}"

# Manager 自身的運行日誌
# 預設使用 XDG Base Directory 規範
MANAGER_LOG_FILE="\${XDG_STATE_HOME:-\$HOME/.local/state}/wappman/logs/wappman_${SERVICE_NAME}.log"

# 應用程式日誌檔路徑 (選填)
# 預設使用 XDG Base Directory 規範
# 若要與 manager 日誌合併，請設定為空字串: APP_LOG_FILE=""
APP_LOG_FILE="\${XDG_STATE_HOME:-\$HOME/.local/state}/wappman/logs/app_${SERVICE_NAME}.log"

# ===================================================================
# 健康檢查設定
# ===================================================================

# 健康檢查間隔 (秒)，0 表示停用健康檢查
HEALTH_CHECK_INTERVAL=1200

# ===================================================================
# 檔案監控(inotify)設定
# ===================================================================

# 監控檔案列表 (空白分隔，留空表示不監控)
# 範例: WATCH_FILES="/path/to/config.yaml /path/to/another.conf"
WATCH_FILES=""

# 重啟觸發檔案 (此檔案被寫入時觸發重啟，留空表示不使用)
# 範例: RESTART_FILE="/tmp/restart.trigger"
RESTART_FILE=""

# ===================================================================
# 重啟及超時設定
# ===================================================================

# 重啟延遲 (秒，選填，默認為 0)
# 當偵測到需要重啟時（health check 或 inotify），延遲指定時間後才執行重啟
# 設定為 0 表示立即重啟
RESTART_DELAY=10

# 重啟最小間隔 (秒)，防止短時間內重複重啟
RESTART_MIN_INTERVAL=10

# 停止超時時間 (秒)，超時後強制終止
STOP_TIMEOUT=10

# ===================================================================
# 失敗重啟驗證設定
# ===================================================================

# 應用程式啟動成功後執行的驗證命令 (選填，留空表示不執行)
# 此命令在每次啟動（包括首次啟動和重啟）後都會執行
# 用於驗證應用程式是否正常運作（如健康檢查 API 呼叫）
# 範例: SUCCESS_CHECK_COMMAND='curl -f http://localhost:8080/health'
# 若命令執行失敗（返回非零），應用程式將被標記為 crashed
SUCCESS_CHECK_COMMAND=""

# 應用程式啟動成功後等待多久才執行驗證命令 (秒，選填)
# 留空時預設使用 RESTART_DELAY 的值，給予應用程式充足的啟動時間
SUCCESS_CHECK_DELAY=""

# crash嘗試重啟次數 (選填，0 表示無限制)
CRASH_RESTART_MAX=0

# 應用程式被標記為 crash 時執行的命令 (選填，留空表示不執行)
# 此命令會在 app 被標記為 crashed 狀態時執行
# 可用於發送通知、記錄事件、觸發告警等
# 範例: CRASH_COMMAND='curl -X POST https://hooks.slack.com/... -d "wappman crashed"'
# 環境變數可用: WAPPMAN_CRASH_REASON, WAPPMAN_CRASH_COUNT, WAPPMAN_APP_EXEC
CRASH_COMMAND=""

# ===================================================================
# 日誌輪替設定
# ===================================================================

# 日誌保留天數 (預設 7 天)
# log-rotate 命令會刪除超過此天數的舊日誌檔
LOG_RETAIN_DAYS=7

TMPLEOF
}

preflight_check() {
  local errors=0
  
  # Check APP_EXEC exists
  if [ ! -f "$APP_EXEC" ] && [ ! -x "$APP_EXEC" ]; then
    echo "WARNING: APP_EXEC not found or not executable: $APP_EXEC"
  fi
  
  # Check write permissions for log files
  for log_file in "$MANAGER_LOG_FILE" ${APP_LOG_FILE:+"$APP_LOG_FILE"}; do
    if [ -f "$log_file" ]; then
      # File exists, check if writable
      if [ ! -w "$log_file" ]; then
        echo "ERROR: No write permission for log file: $log_file"
        errors=$((errors + 1))
      fi
    fi
  done
  
  # Check write permissions for state directory
  local state_dir_parent
  state_dir_parent="$(dirname "$STATE_DIR")"
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  
  if [ ! -w "$STATE_DIR" ]; then
    echo "ERROR: No write permission for state directory: $STATE_DIR"
    errors=$((errors + 1))
  fi
  
  # Check inotifywait if file watching is configured
  if [ -n "${WATCH_FILES:-}" ] || [ -n "${RESTART_FILE:-}" ]; then
    if ! command -v inotifywait &>/dev/null; then
      echo "ERROR: inotifywait not found. Install it with:"
      echo "  sudo apt install inotify-tools  (Debian/Ubuntu)"
      echo "  sudo yum install inotify-tools  (RHEL/CentOS)"
      errors=$((errors + 1))
    fi
  fi
  
  if [ "$errors" -gt 0 ]; then
    exit 1
  fi
}
