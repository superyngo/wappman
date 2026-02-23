#!/bin/bash
# lib/app.sh - Application lifecycle management
#
# Provides: get_args_array(), start_app(), stop_app(), restart_app(),
#           handle_failed_app_start(), ensure_monitors_running(),
#           ensure_inotify_running(), shutdown_on_crash(), shutdown_all()
# Depends on: log(), read_state(), write_state(), init_state_dir(),
#             execute_post_start_command(), execute_crash_command(),
#             start_health_checker(), start_inotify_watcher(), build_watch_paths(),
#             APP_EXEC, APP_ARGS, APP_LOG_FILE, MANAGER_LOG_FILE,
#             STATE_DIR, STOP_TIMEOUT, RESTART_DELAY, RESTART_MIN_INTERVAL,
#             CRASH_RESTART_MAX, HEALTH_CHECK_INTERVAL (globals)

get_args_array() {
  eval "$1=()"
  if [ -n "${APP_ARGS:-}" ]; then
    eval "$1=($APP_ARGS)"
  fi
}

# Unified failure restart handler (completely independent of health check)
# This function handles all restart attempts within CRASH_RESTART_MAX limit
# Health check only monitors successfully started apps, not failed ones
# Returns 0 if app started successfully, 1 if all attempts failed
handle_failed_app_start() {
  local reason="${1:-unknown}"
  local initial_crash_count="${2:-0}"
  
  log "failure-restart: entering failure restart flow (reason=$reason, initial_crash_count=$initial_crash_count)"
  log "failure-restart: this flow is independent of health check"
  
  local crash_count=$initial_crash_count
  local max_attempts=$CRASH_RESTART_MAX
  
  # If CRASH_RESTART_MAX is 0 (unlimited), try once in this flow
  # Health check won't help since we only attach it to successful apps
  if [ "$max_attempts" -eq 0 ]; then
    max_attempts=$((initial_crash_count + 1))
    log "failure-restart: CRASH_RESTART_MAX=0, attempting 1 retry in this flow"
  fi
  
  # Attempt restarts within the limit
  while [ "$crash_count" -lt "$max_attempts" ]; do
    crash_count=$((crash_count + 1))
    
    log "failure-restart: attempt $crash_count/$max_attempts"
    
    # Apply restart delay if configured
    if [ "${RESTART_DELAY:-0}" -gt 0 ]; then
      log "failure-restart: waiting ${RESTART_DELAY}s before attempt"
      sleep "$RESTART_DELAY"
    fi
    
    # Stop any existing app process
    stop_app
    
    # Try to start app (raw start without using start_app to avoid recursion)
    local -a args_array=()
    get_args_array args_array
    
    log "failure-restart: starting app: $APP_EXEC ${args_array[*]:-}"
    
    local app_output_log
    if [ -n "$APP_LOG_FILE" ]; then
      app_output_log="$APP_LOG_FILE"
    else
      app_output_log="$MANAGER_LOG_FILE"
    fi
    
    mkdir -p "$(dirname "$app_output_log")"
    
    if [ "${#args_array[@]}" -gt 0 ]; then
      "$APP_EXEC" "${args_array[@]}" >> "$app_output_log" 2>&1 &
    else
      "$APP_EXEC" >> "$app_output_log" 2>&1 &
    fi
    
    local app_pid=$!
    echo "$app_pid" > "$STATE_DIR/app.pid"
    
    # Sanity check
    sleep 0.2
    if ! kill -0 "$app_pid" 2>/dev/null; then
      log "failure-restart: app failed to start (pid=$app_pid exited immediately)"
      rm -f "$STATE_DIR/app.pid" 2>/dev/null || true
      write_state app "STATUS=crashed" "CRASH_RESTART_COUNT=$crash_count"
      continue
    fi
    
    local now
    now=$(date +%s)
    write_state app \
      "STATUS=running" \
      "PID=$app_pid" \
      "START_TIME=$now" \
      "LAST_START_TIME=$now" \
      "CRASH_RESTART_COUNT=$crash_count"
    
    log "failure-restart: app process started (pid=$app_pid)"
    
    # Execute post-start verification (success check)
    # Pass the original reason as the trigger for the success check
    if ! execute_post_start_command "${reason}_restart_attempt"; then
      log "failure-restart: post-start verification failed on attempt $crash_count"
      write_state app "STATUS=crashed" "CRASH_RESTART_COUNT=$crash_count"
      continue
    fi
    
    # Success!
    log "failure-restart: app started successfully after $crash_count attempt(s)"
    write_state app "CRASH_RESTART_COUNT=0"  # Reset on success
    return 0
  done
  
  # All attempts failed
  log "failure-restart: all restart attempts exhausted (tried $crash_count times)"
  write_state app "STATUS=crashed" "CRASH_RESTART_COUNT=$crash_count"
  return 1
}

start_app() {
  local -a args_array=()
  get_args_array args_array
  
  # Log app file info before starting
  if [ -f "$APP_EXEC" ]; then
    local app_size
    local app_atime
    local app_mtime
    local app_ctime
    
    # Get file size (in bytes)
    app_size=$(stat -c%s "$APP_EXEC" 2>/dev/null || stat -f%z "$APP_EXEC" 2>/dev/null || echo "unknown")
    
    # Get access time
    app_atime=$(stat -c%x "$APP_EXEC" 2>/dev/null || stat -f%Sa -t "%Y-%m-%d %H:%M:%S" "$APP_EXEC" 2>/dev/null || echo "unknown")
    
    # Get modification time
    app_mtime=$(stat -c%y "$APP_EXEC" 2>/dev/null || stat -f%Sm -t "%Y-%m-%d %H:%M:%S" "$APP_EXEC" 2>/dev/null || echo "unknown")
    
    # Get change time
    app_ctime=$(stat -c%z "$APP_EXEC" 2>/dev/null || stat -f%Sc -t "%Y-%m-%d %H:%M:%S" "$APP_EXEC" 2>/dev/null || echo "unknown")
    
    log "app file info: size=${app_size} bytes, atime=${app_atime}, mtime=${app_mtime}, ctime=${app_ctime}"
  fi
  
  log "start app: $APP_EXEC ${args_array[*]:-}"
  
  # 決定應用程式的日誌輸出位置
  local app_output_log
  if [ -n "$APP_LOG_FILE" ]; then
    app_output_log="$APP_LOG_FILE"
    log "app output will be logged to: $APP_LOG_FILE"
  else
    app_output_log="$MANAGER_LOG_FILE"
  fi
  
  # 確保日誌目錄存在
  mkdir -p "$(dirname "$app_output_log")"
  
  if [ "${#args_array[@]}" -gt 0 ]; then
    "$APP_EXEC" "${args_array[@]}" >> "$app_output_log" 2>&1 &
  else
    "$APP_EXEC" >> "$app_output_log" 2>&1 &
  fi
  
  local app_pid=$!
  echo "$app_pid" > "$STATE_DIR/app.pid"
  
  # Sanity check
  sleep 0.2
  if ! kill -0 "$app_pid" 2>/dev/null; then
    log "ERROR: app failed to start (pid=$app_pid exited immediately)"
    rm -f "$STATE_DIR/app.pid" 2>/dev/null || true
    return 1
  fi
  
  local now
  now=$(date +%s)
  write_state app \
    "STATUS=running" \
    "PID=$app_pid" \
    "START_TIME=$now" \
    "LAST_START_TIME=$now"
  
  log "app started successfully (pid=$app_pid)"
  
  # 執行啟動後驗證命令
  if ! execute_post_start_command "initial_start"; then
    log "ERROR: post-start verification failed, marking app as crashed"
    write_state app "STATUS=crashed" "CRASH_RESTART_COUNT=1"
    execute_crash_command "post_start_verification_failed" "1"
    return 1
  fi
  
  return 0
}

stop_app() {
  local pid_file="$STATE_DIR/app.pid"
  
  if [ ! -f "$pid_file" ]; then
    write_state app "STATUS=stopped" "PID="
    return 0
  fi
  
  local pid
  pid=$(cat "$pid_file" 2>/dev/null || true)
  
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$pid_file" 2>/dev/null || true
    write_state app "STATUS=stopped" "PID="
    return 0
  fi
  
  log "stopping app (pid=$pid)"
  kill "$pid" 2>/dev/null || true
  
  local waited=0
  while [ "$waited" -lt "$STOP_TIMEOUT" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      log "app stopped gracefully after ${waited}s"
      rm -f "$pid_file" 2>/dev/null || true
      write_state app "STATUS=stopped" "PID="
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  
  if kill -0 "$pid" 2>/dev/null; then
    log "force killing app (pid=$pid, timeout after ${STOP_TIMEOUT}s)"
    kill -9 "$pid" 2>/dev/null || true
    sleep 0.5
  fi
  
  rm -f "$pid_file" 2>/dev/null || true
  write_state app "STATUS=stopped" "PID="
  return 0
}

restart_app() {
  local reason="${1:-manual}"
  
  # Execute restart command hook before restarting
  execute_restart_command "$reason"
  
  # Check debounce
  local last_start
  last_start=$(read_state app LAST_START_TIME)
  last_start=${last_start:-0}
  
  local now
  now=$(date +%s)
  
  if (( now - last_start < RESTART_MIN_INTERVAL )); then
    log "restart skipped: debounce (last=${last_start}, now=${now}, min=${RESTART_MIN_INTERVAL}s)"
    return 0
  fi
  
  # Apply restart delay if configured
  if [ "${RESTART_DELAY:-0}" -gt 0 ]; then
    log "restart delayed: waiting ${RESTART_DELAY}s before restart (reason=${reason})"
    sleep "$RESTART_DELAY"
  fi
  
  # Check if this is a manual/file-triggered restart (reset crash count for new attempts)
  # Health check restarts use existing crash count (they're part of failure recovery)
  local initial_crash_count=0
  if [[ "$reason" == "health_check" ]]; then
    # For health check, continue with existing crash count
    initial_crash_count=$(read_state app CRASH_RESTART_COUNT)
    initial_crash_count=${initial_crash_count:-0}
    log "restart: health check restart, continuing with crash_count=$initial_crash_count"
  else
    # For manual/file-change restarts, reset crash count (new restart opportunity)
    log "restart: $reason restart, resetting crash count to 0"
    initial_crash_count=0
  fi
  
  # Stop app
  stop_app
  
  # Try to start app
  local app_started=false
  if start_app; then
    app_started=true
  else
    # Start failed, enter failure restart flow
    log "restart: initial start failed, entering failure restart flow"
    if handle_failed_app_start "$reason" "$initial_crash_count"; then
      app_started=true
    fi
  fi
  
  # Handle based on final app status
  if ! $app_started; then
    # All restart attempts failed
    local crash_count
    crash_count=$(read_state app CRASH_RESTART_COUNT)
    crash_count=${crash_count:-0}
    
    log "CRITICAL: app restart failed after all attempts (crash_count=$crash_count, reason=$reason)"
    
    # Ensure app is stopped
    stop_app
    
    # Stop health checker (no app to monitor)
    local health_pid
    health_pid=$(cat "$STATE_DIR/health.pid" 2>/dev/null || true)
    if [ -n "$health_pid" ] && kill -0 "$health_pid" 2>/dev/null; then
      log "stopping health checker (pid=$health_pid) due to app failure"
      kill "$health_pid" 2>/dev/null || true
      sleep 0.5
      if kill -0 "$health_pid" 2>/dev/null; then
        kill -9 "$health_pid" 2>/dev/null || true
      fi
      rm -f "$STATE_DIR/health.pid" 2>/dev/null || true
      write_state health "STATUS=stopped" "PID="
    fi
    
    # Execute crash command
    execute_crash_command "restart_failed_after_retries" "$crash_count"
    
    # Ensure inotify is running (if configured)
    ensure_inotify_running
    
    write_state app "STATUS=crashed" "CRASH_REASON=restart_failed" "CRASH_TIME=$(date +%s)"
    
    log "system in degraded mode: app crashed, health checker stopped, file watcher active"
    return 1
  fi
  
  # App started successfully
  local count
  count=$(read_state app RESTART_COUNT)
  count=${count:-0}
  count=$((count + 1))
  
  # Reset crash count on successful restart
  write_state app \
    "RESTART_COUNT=$count" \
    "CRASH_RESTART_COUNT=0" \
    "LAST_RESTART_TIME=$now" \
    "LAST_RESTART_REASON=$reason"
  
  log "app restarted successfully (reason=$reason, count=$count)"
  
  # Ensure monitors are running
  ensure_monitors_running
  
  return 0
}

# Ensure both monitors are running (called after successful restart)
ensure_monitors_running() {
  # Check and restart health checker if needed
  if [ "${HEALTH_CHECK_INTERVAL:-0}" -gt 0 ]; then
    local health_pid
    health_pid=$(cat "$STATE_DIR/health.pid" 2>/dev/null || true)
    
    if [ -z "$health_pid" ] || ! kill -0 "$health_pid" 2>/dev/null; then
      log "restarting health checker (was not running)"
      start_health_checker
    fi
  fi
  
  # Check and restart inotify if needed
  ensure_inotify_running
}

# Ensure inotify is running if configured
ensure_inotify_running() {
  # Only restart if watch paths are configured
  if ! build_watch_paths; then
    return 0
  fi
  
  local inotify_pid
  inotify_pid=$(cat "$STATE_DIR/inotify.pid" 2>/dev/null || true)
  
  if [ -z "$inotify_pid" ] || ! kill -0 "$inotify_pid" 2>/dev/null; then
    log "restarting file watcher (was not running)"
    start_inotify_watcher
  fi
}

shutdown_on_crash() {
  local reason="${1:-max restarts exceeded}"
  
  log "CRITICAL: crash shutdown triggered (reason: $reason)"
  log "stopping app and health checker, keeping file watcher running"
  
  # Stop health checker
  local health_pid
  health_pid=$(cat "$STATE_DIR/health.pid" 2>/dev/null || true)
  if [ -n "$health_pid" ] && kill -0 "$health_pid" 2>/dev/null; then
    log "stopping health checker (pid=$health_pid)"
    kill "$health_pid" 2>/dev/null || true
    sleep 0.5
    if kill -0 "$health_pid" 2>/dev/null; then
      kill -9 "$health_pid" 2>/dev/null || true
    fi
    rm -f "$STATE_DIR/health.pid" 2>/dev/null || true
    write_state health "STATUS=stopped" "PID="
  fi
  
  # Stop app
  stop_app
  
  write_state app "STATUS=crashed" "CRASH_REASON=$reason" "CRASH_TIME=$(date +%s)"
  
  log "app and health checker stopped, system in degraded mode (file watcher still active)"
}

shutdown_all() {
  local reason="${1:-manual shutdown}"
  
  log "CRITICAL: shutting down all components (reason: $reason)"
  
  # Stop health checker
  local health_pid
  health_pid=$(cat "$STATE_DIR/health.pid" 2>/dev/null || true)
  if [ -n "$health_pid" ] && kill -0 "$health_pid" 2>/dev/null; then
    log "stopping health checker (pid=$health_pid)"
    kill "$health_pid" 2>/dev/null || true
    sleep 0.5
    if kill -0 "$health_pid" 2>/dev/null; then
      kill -9 "$health_pid" 2>/dev/null || true
    fi
    rm -f "$STATE_DIR/health.pid" 2>/dev/null || true
    write_state health "STATUS=stopped" "PID="
  fi
  
  # Stop inotify watcher
  local inotify_pid
  inotify_pid=$(cat "$STATE_DIR/inotify.pid" 2>/dev/null || true)
  if [ -n "$inotify_pid" ] && kill -0 "$inotify_pid" 2>/dev/null; then
    log "stopping inotify watcher (pid=$inotify_pid)"
    pkill -P "$inotify_pid" 2>/dev/null || true
    kill "$inotify_pid" 2>/dev/null || true
    sleep 0.5
    if kill -0 "$inotify_pid" 2>/dev/null; then
      pkill -9 -P "$inotify_pid" 2>/dev/null || true
      kill -9 "$inotify_pid" 2>/dev/null || true
    fi
    rm -f "$STATE_DIR/inotify.pid" 2>/dev/null || true
    write_state inotify "STATUS=stopped" "PID="
  fi
  
  # Stop app
  stop_app
  
  write_state app "STATUS=shutdown" "SHUTDOWN_REASON=$reason" "SHUTDOWN_TIME=$(date +%s)"
  
  log "all components stopped (reason: $reason)"
}
