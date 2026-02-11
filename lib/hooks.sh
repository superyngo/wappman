#!/bin/bash
# lib/hooks.sh - Post-start verification and crash command execution
#
# Provides: export_event_info(), clear_event_info(), execute_restart_command(),
#           execute_post_start_command(), execute_crash_command()
# Depends on: log(), MANAGER_LOG_FILE, SUCCESS_CHECK_COMMAND, SUCCESS_CHECK_DELAY,
#             CRASH_COMMAND, RESTART_COMMAND, STOP_TIMEOUT, APP_EXEC, STATE_DIR,
#             SERVICE_NAME (globals)

# Export event information as environment variables for hook commands
export_event_info() {
  local event_type="$1"     # start, restart, success_check, crash
  local trigger_reason="$2" # manual, health_check, file_change, etc.
  
  export WAPPMAN_EVENT_TIMESTAMP="$(date '+%F %T')"
  export WAPPMAN_EVENT_TIMESTAMP_UNIX="$(date +%s)"
  export WAPPMAN_EVENT_TYPE="$event_type"
  export WAPPMAN_EVENT_TRIGGER="$trigger_reason"
  export WAPPMAN_SERVICE_NAME="${SERVICE_NAME:-unknown}"
  export WAPPMAN_APP_EXEC="$APP_EXEC"
  export WAPPMAN_STATE_DIR="$STATE_DIR"
  export WAPPMAN_MANAGER_LOG="$MANAGER_LOG_FILE"
}

# Clear event information environment variables
clear_event_info() {
  unset WAPPMAN_EVENT_TIMESTAMP WAPPMAN_EVENT_TIMESTAMP_UNIX
  unset WAPPMAN_EVENT_TYPE WAPPMAN_EVENT_TRIGGER
  unset WAPPMAN_SERVICE_NAME WAPPMAN_APP_EXEC WAPPMAN_STATE_DIR WAPPMAN_MANAGER_LOG
}

execute_restart_command() {
  local trigger_reason="${1:-manual}"
  
  # 檢查是否有設定重啟命令
  if [ -z "${RESTART_COMMAND:-}" ]; then
    return 0
  fi
  
  log "restart-hook: executing restart command (trigger=$trigger_reason)"
  
  # 設定事件環境變數
  export_event_info "restart" "$trigger_reason"
  
  # 執行命令並捕獲輸出
  local cmd_start
  cmd_start=$(date '+%F %T')
  local cmd_output
  local cmd_exit_code
  
  # 使用臨時檔案捕獲 stdout 和 stderr
  local temp_output
  temp_output=$(mktemp)
  
  # 使用 timeout 執行命令（使用 STOP_TIMEOUT 作為超時時間）
  if timeout "${STOP_TIMEOUT}s" bash -c "$RESTART_COMMAND" > "$temp_output" 2>&1; then
    cmd_exit_code=0
  else
    cmd_exit_code=$?
  fi
  
  cmd_output=$(cat "$temp_output")
  rm -f "$temp_output"
  
  # 格式化輸出到日誌
  log "restart-hook: command executed at $cmd_start"
  log "restart-hook: exit code: $cmd_exit_code"
  
  # 記錄命令輸出（限制最多 50 行）
  if [ -n "$cmd_output" ]; then
    local line_count
    line_count=$(echo "$cmd_output" | wc -l)
    
    if [ "$line_count" -gt 50 ]; then
      log "restart-hook: command output (first 50 lines of $line_count):"
      echo "$cmd_output" | head -n 50 | while IFS= read -r line; do
        log "  | $line"
      done
      log "  | ... ($(( line_count - 50 )) lines truncated)"
    else
      log "restart-hook: command output:"
      echo "$cmd_output" | while IFS= read -r line; do
        log "  | $line"
      done
    fi
  else
    log "restart-hook: command output: (empty)"
  fi
  
  # 檢查命令結果
  if [ "$cmd_exit_code" -eq 124 ]; then
    log "WARNING: restart command timed out after ${STOP_TIMEOUT}s"
  elif [ "$cmd_exit_code" -ne 0 ]; then
    log "WARNING: restart command failed (exit code: $cmd_exit_code)"
  else
    log "restart-hook: command succeeded"
  fi
  
  # 清理環境變數
  clear_event_info
  
  # 總是返回 0，不影響重啟流程
  return 0
}

execute_post_start_command() {
  local trigger_reason="${1:-start}"
  local trigger_reason="${1:-start}"
  
  # 檢查是否有設定驗證命令
  if [ -z "${SUCCESS_CHECK_COMMAND:-}" ]; then
    return 0
  fi
  
  # 等待 SUCCESS_CHECK_DELAY 秒
  if [ "${SUCCESS_CHECK_DELAY:-0}" -gt 0 ]; then
    log "post-start: waiting ${SUCCESS_CHECK_DELAY}s before executing verification command"
    sleep "$SUCCESS_CHECK_DELAY"
  fi
  
  # 記錄即將執行的命令
  log "post-start: executing verification command: $SUCCESS_CHECK_COMMAND (trigger=$trigger_reason)"
  
  # 設定事件環境變數
  export_event_info "success_check" "$trigger_reason"
  
  # 執行命令並捕獲輸出
  local cmd_start
  cmd_start=$(date '+%F %T')
  local cmd_output
  local cmd_exit_code
  
  # 使用臨時檔案捕獲 stdout 和 stderr
  local temp_output
  temp_output=$(mktemp)
  
  eval "$SUCCESS_CHECK_COMMAND" > "$temp_output" 2>&1
  cmd_exit_code=$?
  
  cmd_output=$(cat "$temp_output")
  rm -f "$temp_output"
  
  # 格式化輸出到日誌
  log "post-start: command executed at $cmd_start"
  log "post-start: exit code: $cmd_exit_code"
  
  # 記錄命令輸出（限制最多 50 行）
  if [ -n "$cmd_output" ]; then
    local line_count
    line_count=$(echo "$cmd_output" | wc -l)
    
    if [ "$line_count" -gt 50 ]; then
      log "post-start: command output (first 50 lines of $line_count):"
      echo "$cmd_output" | head -n 50 | while IFS= read -r line; do
        log "  | $line"
      done
      log "  | ... ($(( line_count - 50 )) lines truncated)"
    else
      log "post-start: command output:"
      echo "$cmd_output" | while IFS= read -r line; do
        log "  | $line"
      done
    fi
  else
    log "post-start: command output: (empty)"
  fi
  
  # 清理環境變數
  clear_event_info
  
  # 檢查命令是否成功
  if [ "$cmd_exit_code" -ne 0 ]; then
    log "ERROR: post-start verification command failed (exit code: $cmd_exit_code)"
    return 1
  fi
  
  log "post-start: verification command succeeded"
  return 0
}

execute_crash_command() {
  local reason="${1:-unknown}"
  local crash_count="${2:-0}"
  
  # 檢查是否有設定 crash 命令
  if [ -z "${CRASH_COMMAND:-}" ]; then
    return 0
  fi
  
  log "crash-handler: executing crash command (reason=$reason, count=$crash_count)"
  
  # 設定事件環境變數
  export_event_info "crash" "$reason"
  
  # 設定 crash 特定環境變數
  export WAPPMAN_CRASH_REASON="$reason"
  export WAPPMAN_CRASH_COUNT="$crash_count"
  
  # 執行命令並捕獲輸出，使用 timeout 防止卡住
  local cmd_start
  cmd_start=$(date '+%F %T')
  local cmd_output
  local cmd_exit_code
  
  # 使用臨時檔案捕獲 stdout 和 stderr
  local temp_output
  temp_output=$(mktemp)
  
  # 使用 timeout 執行命令（使用 STOP_TIMEOUT 作為超時時間）
  if timeout "${STOP_TIMEOUT}s" bash -c "$CRASH_COMMAND" > "$temp_output" 2>&1; then
    cmd_exit_code=0
  else
    cmd_exit_code=$?
  fi
  
  cmd_output=$(cat "$temp_output")
  rm -f "$temp_output"
  
  # 格式化輸出到日誌
  log "crash-handler: command executed at $cmd_start"
  log "crash-handler: exit code: $cmd_exit_code"
  
  # 記錄命令輸出（限制最多 50 行）
  if [ -n "$cmd_output" ]; then
    local line_count
    line_count=$(echo "$cmd_output" | wc -l)
    
    if [ "$line_count" -gt 50 ]; then
      log "crash-handler: command output (first 50 lines of $line_count):"
      echo "$cmd_output" | head -n 50 | while IFS= read -r line; do
        log "  | $line"
      done
      log "  | ... ($(( line_count - 50 )) lines truncated)"
    else
      log "crash-handler: command output:"
      echo "$cmd_output" | while IFS= read -r line; do
        log "  | $line"
      done
    fi
  else
    log "crash-handler: command output: (empty)"
  fi
  
  # 檢查命令結果
  if [ "$cmd_exit_code" -eq 124 ]; then
    log "WARNING: crash command timed out after ${STOP_TIMEOUT}s"
  elif [ "$cmd_exit_code" -ne 0 ]; then
    log "WARNING: crash command failed (exit code: $cmd_exit_code)"
  else
    log "crash-handler: command succeeded"
  fi
  
  # 清理環境變數
  clear_event_info
  unset WAPPMAN_CRASH_REASON WAPPMAN_CRASH_COUNT
  
  # 總是返回 0，不影響主流程
  return 0
}
