#!/bin/bash
# lib/commands.sh - CLI command implementations
#
# Provides: cmd_start(), cmd_stop(), cmd_restart(), cmd_restart_app(),
#           cmd_restart_monitor(), cmd_clean(), cmd_log(), cmd_status(),
#           cmd_list(), cmd_config(), cmd_status_all(), show_usage()
# Depends on: All other modules (this is the top-level orchestration layer)

cmd_list() {
  local services=()
  while IFS= read -r svc; do
    [ -n "$svc" ] && services+=("$svc")
  done < <(list_services)

  if [ "${#services[@]}" -eq 0 ]; then
    echo "No services configured."
    echo "Use '$0 config <SERVICE_NAME>' to create a new service configuration."
    return 0
  fi

  echo "Configured services:"
  for svc in "${services[@]}"; do
    echo "  $svc"
  done
}

cmd_config() {
  local is_new=false
  if [ ! -f "$CONF" ]; then
    is_new=true
    create_config_template
    echo "✓ Configuration template created: $CONF"
  fi

  local editor="${EDITOR:-${VISUAL:-vi}}"
  echo "Opening $CONF with $editor..."
  "$editor" "$CONF"

  if $is_new; then
    echo ""
    echo "Next steps:"
    echo "  1. Set APP_EXEC to your application path in the config"
    echo "  2. Run: $0 start $SERVICE_NAME"
  fi
}

cmd_status_all() {
  local services=()
  while IFS= read -r svc; do
    [ -n "$svc" ] && services+=("$svc")
  done < <(list_services)

  if [ "${#services[@]}" -eq 0 ]; then
    echo "No services configured."
    return 0
  fi

  # Header
  printf "%-20s  %-12s  %-12s  %-12s\n" "SERVICE" "APP" "HEALTH" "WATCHER"
  printf "%-20s  %-12s  %-12s  %-12s\n" "───────────────────" "────────────" "────────────" "────────────"

  for svc in "${services[@]}"; do
    SERVICE_NAME="$svc"
    resolve_conf

    local app_indicator="⚫ n/a"
    local health_indicator="⚫ n/a"
    local inotify_indicator="⚫ n/a"

    if [ -f "$CONF" ] && load_config 2>/dev/null; then
      # App status
      local app_pid
      app_pid=$(cat "$STATE_DIR/app.pid" 2>/dev/null || true)
      local app_status
      app_status=$(read_state app STATUS 2>/dev/null || true)

      if [ -n "$app_pid" ] && kill -0 "$app_pid" 2>/dev/null; then
        app_indicator="🟢 running"
      elif [ "$app_status" = "crashed" ]; then
        app_indicator="🔴 crashed"
      else
        app_indicator="🔴 stopped"
      fi

      # Health checker status
      local health_status
      health_status=$(read_state health STATUS 2>/dev/null || true)

      if [ "$health_status" = "disabled" ]; then
        health_indicator="🟡 disabled"
      else
        local health_pid
        health_pid=$(cat "$STATE_DIR/health.pid" 2>/dev/null || true)
        if [ -n "$health_pid" ] && kill -0 "$health_pid" 2>/dev/null; then
          health_indicator="🟢 running"
        else
          health_indicator="🔴 stopped"
        fi
      fi

      # File watcher status
      local inotify_status
      inotify_status=$(read_state inotify STATUS 2>/dev/null || true)

      if [ "$inotify_status" = "disabled" ]; then
        inotify_indicator="🟡 disabled"
      else
        local inotify_pid
        inotify_pid=$(cat "$STATE_DIR/inotify.pid" 2>/dev/null || true)
        if [ -n "$inotify_pid" ] && kill -0 "$inotify_pid" 2>/dev/null; then
          inotify_indicator="🟢 running"
        else
          inotify_indicator="🔴 stopped"
        fi
      fi
    fi

    printf "%-20s  %-12s  %-12s  %-12s\n" "$svc" "$app_indicator" "$health_indicator" "$inotify_indicator"
  done
}

cmd_start() {
  echo "Starting $SERVICE_NAME..."
  echo ""
  
  preflight_check
  init_state_dir
  
  if is_running; then
    echo "ERROR: Already running. Use 'status' to check or 'stop' first."
    return 1
  fi
  
  # Clean up restart trigger file if exists
  if [ -n "${RESTART_FILE:-}" ] && [ -f "$RESTART_FILE" ]; then
    rm -f "$RESTART_FILE"
    echo "○ Cleaned up existing restart trigger file"
  fi
  
  # Try to start app
  local app_started=false
  if start_app; then
    app_started=true
  else
    # Initial start failed, enter failure restart flow
    echo "○ Initial startup failed, entering failure restart flow..."
    if handle_failed_app_start "initial_start_failed" 0; then
      app_started=true
    fi
  fi
  
  # Handle based on final app status
  if ! $app_started; then
    # All restart attempts failed
    echo "ERROR: Failed to start application"
    
    # Ensure app is stopped
    stop_app
    
    # Ensure health checker is stopped (should not monitor crashed apps)
    local health_pid
    health_pid=$(cat "$STATE_DIR/health.pid" 2>/dev/null || true)
    if [ -n "$health_pid" ] && kill -0 "$health_pid" 2>/dev/null; then
      log "stopping health checker (pid=$health_pid) - app in crashed state"
      kill "$health_pid" 2>/dev/null || true
      sleep 0.5
      if kill -0 "$health_pid" 2>/dev/null; then
        kill -9 "$health_pid" 2>/dev/null || true
      fi
      rm -f "$STATE_DIR/health.pid" 2>/dev/null || true
      write_state health "STATUS=stopped" "PID="
    fi
    
    # Set crashed state
    local crash_count
    crash_count=$(read_state app CRASH_RESTART_COUNT)
    crash_count=${crash_count:-0}
    write_state app "STATUS=crashed" "CRASH_REASON=startup_failed" "CRASH_TIME=$(date +%s)"
    
    # Execute crash command
    if [ -n "${CRASH_COMMAND:-}" ]; then
      echo "○ Executing crash command"
      execute_crash_command "startup_failed_after_retries" "$crash_count"
    fi
    
    # Start file watcher only (no health checker for crashed apps)
    if build_watch_paths; then
      start_inotify_watcher
      local inotify_pid
      inotify_pid=$(cat "$STATE_DIR/inotify.pid" 2>/dev/null)
      echo "✓ File watcher started (pid=$inotify_pid)"
    else
      write_state inotify "STATUS=disabled"
      echo "○ File watcher disabled (no valid watch paths configured)"
    fi
    
    echo ""
    echo "Application startup failed. System in degraded mode."
    echo "Manager log: $MANAGER_LOG_FILE"
    if [ -n "$APP_LOG_FILE" ]; then
      echo "App log:     $APP_LOG_FILE"
    else
      echo "App output:  merged with manager log"
    fi
    return 1
  fi
  
  # App started successfully
  local app_pid
  app_pid=$(cat "$STATE_DIR/app.pid" 2>/dev/null)
  echo "✓ Application started (pid=$app_pid)"
  
  # Start health checker
  if [ "${HEALTH_CHECK_INTERVAL:-0}" -gt 0 ]; then
    start_health_checker
    local health_pid
    health_pid=$(cat "$STATE_DIR/health.pid" 2>/dev/null)
    echo "✓ Health checker started (pid=$health_pid, interval=${HEALTH_CHECK_INTERVAL}s)"
  else
    write_state health "STATUS=disabled"
    echo "○ Health checker disabled (HEALTH_CHECK_INTERVAL=0)"
  fi
  
  # Start inotify watcher
  if build_watch_paths; then
    start_inotify_watcher
    local inotify_pid
    inotify_pid=$(cat "$STATE_DIR/inotify.pid" 2>/dev/null)
    echo "✓ File watcher started (pid=$inotify_pid)"
    echo "  Monitoring paths:"
    for path in "${WATCH_PATHS[@]}"; do
      echo "    - $path"
    done
    if [ -n "${WATCH_FILES:-}" ]; then
      echo "  Watch files: ${WATCH_FILES}"
    fi
    if [ -n "${RESTART_FILE:-}" ]; then
      echo "  Restart trigger: ${RESTART_FILE}"
    fi
  else
    write_state inotify "STATUS=disabled"
    echo "○ File watcher disabled (no valid watch paths configured)"
  fi
  
  echo ""
  echo "All components started successfully."
  echo "Manager log: $MANAGER_LOG_FILE"
  if [ -n "$APP_LOG_FILE" ]; then
    echo "App log:     $APP_LOG_FILE"
  else
    echo "App output:  merged with manager log"
  fi
  echo "Use '$0 status $SERVICE_NAME' to check, '$0 stop $SERVICE_NAME' to stop."
}

cmd_stop() {
  echo "Stopping $SERVICE_NAME..."
  echo ""
  
  init_state_dir
  
  local stopped=0
  
  # Stop in order: health → inotify → app
  for proc in health inotify app; do
    local pid_file="$STATE_DIR/${proc}.pid"
    
    if [ ! -f "$pid_file" ]; then
      continue
    fi
    
    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)
    
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$pid_file" 2>/dev/null || true
      continue
    fi
    
    echo "Stopping $proc (pid=$pid)..."
    
    # For inotify, kill all child processes first
    if [ "$proc" = "inotify" ]; then
      # Kill all children of the subshell
      pkill -P "$pid" 2>/dev/null || true
      sleep 0.3
    fi
    
    # Then kill the main process
    kill "$pid" 2>/dev/null || true
    
    # Wait for graceful shutdown
    local waited=0
    while [ "$waited" -lt "$STOP_TIMEOUT" ] && kill -0 "$pid" 2>/dev/null; do
      sleep 1
      waited=$((waited + 1))
    done
    
    # Force kill if still running
    if kill -0 "$pid" 2>/dev/null; then
      echo "  Force killing $proc..."
      if [ "$proc" = "inotify" ]; then
        # Force kill all children first
        pkill -9 -P "$pid" 2>/dev/null || true
      fi
      kill -9 "$pid" 2>/dev/null || true
      sleep 0.5
    fi
    
    # Final cleanup for inotify - ensure no orphaned inotifywait
    if [ "$proc" = "inotify" ]; then
      pkill -9 -P "$pid" 2>/dev/null || true
    fi
    
    rm -f "$pid_file" 2>/dev/null || true
    write_state "$proc" "STATUS=stopped" "PID="
    stopped=$((stopped + 1))
  done
  
  echo ""
  if [ "$stopped" -gt 0 ]; then
    echo "Stopped $stopped component(s)."
  else
    echo "No components were running."
  fi
}

cmd_restart() {
  cmd_stop
  sleep 1
  cmd_start
}

cmd_restart_app() {
  init_state_dir
  
  if ! is_running; then
    echo "ERROR: Manager not running. Use 'start' first."
    return 1
  fi
  
  echo "Restarting application only..."
  restart_app "manual"
  echo "Application restarted."
}

cmd_restart_monitor() {
  init_state_dir
  
  echo "Restarting monitor components (health checker and file watcher)..."
  echo ""
  
  # Stop monitors
  local stopped=0
  for proc in health inotify; do
    local pid_file="$STATE_DIR/${proc}.pid"
    
    if [ ! -f "$pid_file" ]; then
      continue
    fi
    
    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)
    
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$pid_file" 2>/dev/null || true
      continue
    fi
    
    echo "Stopping $proc (pid=$pid)..."
    
    # For inotify, kill all child processes first
    if [ "$proc" = "inotify" ]; then
      pkill -P "$pid" 2>/dev/null || true
      sleep 0.3
    fi
    
    # Then kill the main process
    kill "$pid" 2>/dev/null || true
    
    # Wait for graceful shutdown
    local waited=0
    while [ "$waited" -lt "$STOP_TIMEOUT" ] && kill -0 "$pid" 2>/dev/null; do
      sleep 1
      waited=$((waited + 1))
    done
    
    # Force kill if still running
    if kill -0 "$pid" 2>/dev/null; then
      echo "  Force killing $proc..."
      if [ "$proc" = "inotify" ]; then
        pkill -9 -P "$pid" 2>/dev/null || true
      fi
      kill -9 "$pid" 2>/dev/null || true
      sleep 0.5
    fi
    
    # Final cleanup for inotify
    if [ "$proc" = "inotify" ]; then
      pkill -9 -P "$pid" 2>/dev/null || true
    fi
    
    rm -f "$pid_file" 2>/dev/null || true
    write_state "$proc" "STATUS=stopped" "PID="
    stopped=$((stopped + 1))
  done
  
  if [ "$stopped" -gt 0 ]; then
    echo "Stopped $stopped monitor(s)."
  fi
  
  echo ""
  sleep 1
  
  # Start monitors
  local started=0
  
  # Start health checker
  if [ "$HEALTH_CHECK_INTERVAL" -gt 0 ]; then
    echo "Starting health checker..."
    start_health_checker
    started=$((started + 1))
  fi
  
  # Start inotify watcher
  if build_watch_paths; then
    echo "Starting file watcher..."
    start_inotify_watcher
    started=$((started + 1))
  fi
  
  echo ""
  if [ "$started" -gt 0 ]; then
    echo "Started $started monitor(s)."
  else
    echo "No monitors configured to start."
  fi
}

cmd_clean() {
  init_state_dir
  
  echo "Cleaning state directory..."
  echo ""
  
  # Check if anything is running
  if is_running; then
    echo "ERROR: Components are still running. Please stop first."
    echo "Run: $0 stop $SERVICE_NAME"
    return 1
  fi
  
  # Remove all state files
  local removed=0
  for file in "$STATE_DIR"/*.{pid,state}; do
    if [ -f "$file" ]; then
      rm -f "$file"
      echo "Removed: $(basename "$file")"
      removed=$((removed + 1))
    fi
  done
  
  echo ""
  if [ "$removed" -gt 0 ]; then
    echo "Cleaned $removed file(s) from state directory."
  else
    echo "State directory is already clean."
  fi
}

cmd_log() {
  echo "Monitoring wappman log (Ctrl+C to exit)..."
  echo "Log file: $MANAGER_LOG_FILE"
  echo ""
  
  # Create log file if it doesn't exist
  if [ ! -f "$MANAGER_LOG_FILE" ]; then
    mkdir -p "$(dirname "$MANAGER_LOG_FILE")"
    touch "$MANAGER_LOG_FILE"
    echo "Log file created."
  fi
  
  exec tail -f "$MANAGER_LOG_FILE"
}

cmd_status() {
  init_state_dir
  
  echo "wappman status: $SERVICE_NAME"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  # Configuration Info
  echo "Configuration:"
  echo "  Service:      $SERVICE_NAME"
  echo "  Config file:  $CONF"
  echo "  State dir:    $STATE_DIR"
  local exec_cmd="$APP_EXEC"
  if [ -n "$APP_ARGS" ]; then
    exec_cmd="$exec_cmd $APP_ARGS"
  fi
  echo "  Command:      $exec_cmd"
  if [ -n "$SUCCESS_CHECK_COMMAND" ]; then
    echo "  Check CMD:    $SUCCESS_CHECK_COMMAND"
  fi
  if [ -n "$CRASH_COMMAND" ]; then
    echo "  Crash CMD:    $CRASH_COMMAND"
  fi
  echo "  Manager log:  $MANAGER_LOG_FILE"
  if [ -n "$APP_LOG_FILE" ]; then
    echo "  App log:      $APP_LOG_FILE"
  else
    echo "  App log:      (merged with manager log)"
  fi
  echo ""
  
  # Application status
  echo "Application:"
  local app_pid
  app_pid=$(cat "$STATE_DIR/app.pid" 2>/dev/null || true)
  
  if [ -n "$app_pid" ] && kill -0 "$app_pid" 2>/dev/null; then
    local start_time
    start_time=$(read_state app START_TIME)
    local uptime
    uptime=$(get_uptime "$start_time")
    local restart_count
    restart_count=$(read_state app RESTART_COUNT)
    restart_count=${restart_count:-0}
    
    # Extract restart events from log
    local log_restart_count=0
    local log_health_restarts=0
    local log_file_restarts=0
    local log_manual_restarts=0
    
    if [ -f "$MANAGER_LOG_FILE" ]; then
      log_restart_count=$(grep -c "app restarted successfully" "$MANAGER_LOG_FILE" 2>/dev/null || true)
      log_restart_count=${log_restart_count:-0}
      
      log_health_restarts=$(grep "app restarted successfully" "$MANAGER_LOG_FILE" 2>/dev/null | grep -c "reason=health_check" 2>/dev/null || true)
      log_health_restarts=${log_health_restarts:-0}
      
      log_file_restarts=$(grep "app restarted successfully" "$MANAGER_LOG_FILE" 2>/dev/null | grep -cE "reason=(file_change|restart_file)" 2>/dev/null || true)
      log_file_restarts=${log_file_restarts:-0}
      
      log_manual_restarts=$(grep "app restarted successfully" "$MANAGER_LOG_FILE" 2>/dev/null | grep -c "reason=manual" 2>/dev/null || true)
      log_manual_restarts=${log_manual_restarts:-0}
    fi
    
    echo "  Status:   running     (pid=$app_pid)"
    echo "  Uptime:   $uptime"
    echo "  Restarts: $restart_count (total from log: $log_restart_count)"
    
    if [ "$log_restart_count" -gt 0 ]; then
      echo "    ├─ Health check: $log_health_restarts"
      echo "    ├─ File change:  $log_file_restarts"
      echo "    └─ Manual:       $log_manual_restarts"
    fi
    
    if [ "$restart_count" -gt 0 ]; then
      local last_reason
      last_reason=$(read_state app LAST_RESTART_REASON)
      echo "  Last restart: ${last_reason:-unknown}"
    fi
  else
    echo "  Status:   stopped"
  fi
  
  echo ""
  
  # Health checker status
  echo "Health Checker:"
  local health_status
  health_status=$(read_state health STATUS)
  
  if [ "$health_status" = "disabled" ]; then
    echo "  Status:   disabled"
  else
    local health_pid
    health_pid=$(cat "$STATE_DIR/health.pid" 2>/dev/null || true)
    
    if [ -n "$health_pid" ] && kill -0 "$health_pid" 2>/dev/null; then
      local interval
      interval=$(read_state health INTERVAL)
      local checks_ok
      checks_ok=$(read_state health CHECKS_OK)
      local checks_fail
      checks_fail=$(read_state health CHECKS_FAIL)
      
      echo "  Status:   running     (pid=$health_pid)"
      echo "  Interval: ${interval:-N/A}s"
      echo "  Checks:   OK=${checks_ok:-0} FAIL=${checks_fail:-0}"
    else
      echo "  Status:   stopped"
    fi
  fi
  
  echo ""
  
  # File watcher status
  echo "File Watcher:"
  local inotify_status
  inotify_status=$(read_state inotify STATUS)
  
  if [ "$inotify_status" = "disabled" ]; then
    echo "  Status:   disabled"
  else
    local inotify_pid
    inotify_pid=$(cat "$STATE_DIR/inotify.pid" 2>/dev/null || true)
    
    if [ -n "$inotify_pid" ] && kill -0 "$inotify_pid" 2>/dev/null; then
      local watch_count
      watch_count=$(read_state inotify WATCH_COUNT)
      local events
      events=$(read_state inotify EVENTS_TRIGGERED)
      local stored_watch_files
      stored_watch_files=$(read_state inotify WATCH_FILES)
      local stored_restart_file
      stored_restart_file=$(read_state inotify RESTART_FILE)
      
      echo "  Status:   running     (pid=$inotify_pid)"
      echo "  Events:   ${events:-0} triggered"
      echo "  Monitoring:"
      
      # Rebuild watch paths to show current monitoring
      if build_watch_paths; then
        for path in "${WATCH_PATHS[@]}"; do
          echo "    - $path"
        done
      fi
      
      # Show watch files
      if [ -n "$stored_watch_files" ]; then
        echo "  Watch files:"
        for f in $stored_watch_files; do
          if [ -f "$f" ]; then
            echo "    ✓ $f"
          else
            echo "    ✗ $f (not found)"
          fi
        done
      fi
      
      # Show restart trigger file
      if [ -n "$stored_restart_file" ]; then
        if [ -f "$stored_restart_file" ]; then
          echo "  Restart trigger: $stored_restart_file ✓"
        else
          echo "  Restart trigger: $stored_restart_file (will be monitored when created)"
        fi
      fi
    else
      echo "  Status:   stopped"
    fi
  fi
  
  echo ""
  echo "═══════════════════════════════════════════════════════════"
}

cmd_log_rotate() {
  local rotated=0
  local deleted=0
  local today
  today=$(date +%Y-%m-%d)

  # Collect log files to rotate
  local log_files=()
  log_files+=("$MANAGER_LOG_FILE")
  if [ -n "${APP_LOG_FILE:-}" ] && [ "$APP_LOG_FILE" != "$MANAGER_LOG_FILE" ]; then
    log_files+=("$APP_LOG_FILE")
  fi

  echo "Log rotation for $SERVICE_NAME (retain=${LOG_RETAIN_DAYS} days)"
  echo ""

  # Rotate current logs
  for lf in "${log_files[@]}"; do
    if [ ! -f "$lf" ]; then
      echo "  Skip (not found): $lf"
      continue
    fi

    # Only rotate if file is non-empty
    if [ ! -s "$lf" ]; then
      echo "  Skip (empty):     $lf"
      continue
    fi

    local dir base ext rotated_name
    dir=$(dirname "$lf")
    base=$(basename "$lf")

    # Split filename into name and extension
    if [[ "$base" == *.* ]]; then
      ext=".${base##*.}"
      base="${base%.*}"
    else
      ext=""
    fi

    rotated_name="${dir}/${base}.${today}${ext}"

    # If today's rotated file already exists, append a counter
    if [ -f "$rotated_name" ]; then
      local counter=1
      while [ -f "${dir}/${base}.${today}.${counter}${ext}" ]; do
        counter=$((counter + 1))
      done
      rotated_name="${dir}/${base}.${today}.${counter}${ext}"
    fi

    mv "$lf" "$rotated_name"
    touch "$lf"
    echo "  Rotated: $lf → $(basename "$rotated_name")"
    rotated=$((rotated + 1))
  done

  echo ""

  # Delete old rotated logs beyond retention period
  for lf in "${log_files[@]}"; do
    local dir base ext
    dir=$(dirname "$lf")
    base=$(basename "$lf")

    if [[ "$base" == *.* ]]; then
      ext=".${base##*.}"
      base="${base%.*}"
    else
      ext=""
    fi

    # Find rotated files matching the pattern: base.YYYY-MM-DD[.N].ext
    for old_file in "${dir}/${base}".????-??-??${ext} "${dir}/${base}".????-??-??.?${ext} "${dir}/${base}".????-??-??.??${ext}; do
      [ -f "$old_file" ] || continue

      # Extract date from filename
      local fname
      fname=$(basename "$old_file")
      local date_part
      date_part=$(echo "$fname" | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
      [ -n "$date_part" ] || continue

      # Calculate age in days
      local file_epoch today_epoch age_days
      file_epoch=$(date -d "$date_part" +%s 2>/dev/null) || continue
      today_epoch=$(date -d "$today" +%s)
      age_days=$(( (today_epoch - file_epoch) / 86400 ))

      if [ "$age_days" -ge "$LOG_RETAIN_DAYS" ]; then
        rm -f "$old_file"
        echo "  Deleted (${age_days}d old): $(basename "$old_file")"
        deleted=$((deleted + 1))
      fi
    done
  done

  echo ""
  echo "Done: $rotated file(s) rotated, $deleted old file(s) deleted."
}

cmd_del() {
  echo "Deleting service: $SERVICE_NAME"
  echo ""

  init_state_dir

  # Check if anything is running
  if is_running; then
    echo "ERROR: Components are still running. Please stop first."
    echo "Run: $0 stop $SERVICE_NAME"
    return 1
  fi

  # Collect items to be deleted
  local items=()
  [ -f "$CONF" ] && items+=("Config:    $CONF")
  [ -d "$STATE_DIR" ] && items+=("State dir: $STATE_DIR")
  [ -f "$MANAGER_LOG_FILE" ] && items+=("Log:       $MANAGER_LOG_FILE")

  # Rotated manager logs
  local mgr_dir mgr_base mgr_ext
  mgr_dir=$(dirname "$MANAGER_LOG_FILE")
  mgr_base=$(basename "$MANAGER_LOG_FILE")
  if [[ "$mgr_base" == *.* ]]; then
    mgr_ext=".${mgr_base##*.}"
    mgr_base="${mgr_base%.*}"
  else
    mgr_ext=""
  fi
  for rf in "${mgr_dir}/${mgr_base}".????-??-??${mgr_ext} "${mgr_dir}/${mgr_base}".????-??-??.?${mgr_ext} "${mgr_dir}/${mgr_base}".????-??-??.??${mgr_ext}; do
    [ -f "$rf" ] && items+=("Log:       $rf")
  done

  if [ -n "${APP_LOG_FILE:-}" ] && [ "$APP_LOG_FILE" != "$MANAGER_LOG_FILE" ]; then
    [ -f "$APP_LOG_FILE" ] && items+=("Log:       $APP_LOG_FILE")
    # Rotated app logs
    local app_dir app_base app_ext
    app_dir=$(dirname "$APP_LOG_FILE")
    app_base=$(basename "$APP_LOG_FILE")
    if [[ "$app_base" == *.* ]]; then
      app_ext=".${app_base##*.}"
      app_base="${app_base%.*}"
    else
      app_ext=""
    fi
    for rf in "${app_dir}/${app_base}".????-??-??${app_ext} "${app_dir}/${app_base}".????-??-??.?${app_ext} "${app_dir}/${app_base}".????-??-??.??${app_ext}; do
      [ -f "$rf" ] && items+=("Log:       $rf")
    done
  fi

  if [ "${#items[@]}" -eq 0 ]; then
    echo "Nothing to delete for service '$SERVICE_NAME'."
    return 0
  fi

  echo "The following will be deleted:"
  for item in "${items[@]}"; do
    echo "  $item"
  done
  echo ""

  # Confirm if interactive
  if [ -t 0 ]; then
    read -p "Are you sure? [y/N] " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) ;;
      *)
        echo "Aborted."
        return 0
        ;;
    esac
  else
    echo "ERROR: Non-interactive mode. Use -y flag or run interactively."
    return 1
  fi

  echo ""

  # Delete log files (including rotated)
  local deleted=0

  # Manager logs
  for rf in "$MANAGER_LOG_FILE" "${mgr_dir}/${mgr_base}".????-??-??${mgr_ext} "${mgr_dir}/${mgr_base}".????-??-??.?${mgr_ext} "${mgr_dir}/${mgr_base}".????-??-??.??${mgr_ext}; do
    if [ -f "$rf" ]; then
      rm -f "$rf"
      echo "  Deleted: $rf"
      deleted=$((deleted + 1))
    fi
  done

  # App logs
  if [ -n "${APP_LOG_FILE:-}" ] && [ "$APP_LOG_FILE" != "$MANAGER_LOG_FILE" ]; then
    for rf in "$APP_LOG_FILE" "${app_dir}/${app_base}".????-??-??${app_ext} "${app_dir}/${app_base}".????-??-??.?${app_ext} "${app_dir}/${app_base}".????-??-??.??${app_ext}; do
      if [ -f "$rf" ]; then
        rm -f "$rf"
        echo "  Deleted: $rf"
        deleted=$((deleted + 1))
      fi
    done
  fi

  # Delete state directory
  if [ -d "$STATE_DIR" ]; then
    rm -rf "$STATE_DIR"
    echo "  Deleted: $STATE_DIR/"
    # Clean up parent dir if empty
    local parent_dir
    parent_dir=$(dirname "$STATE_DIR")
    rmdir "$parent_dir" 2>/dev/null || true
  fi

  # Delete config file
  if [ -f "$CONF" ]; then
    rm -f "$CONF"
    echo "  Deleted: $CONF"
  fi

  echo ""
  echo "Service '$SERVICE_NAME' has been deleted."
}

show_usage() {
  cat << EOF
Usage: $0 <command> <SERVICE_NAME|all>

Commands:
  list                          List all configured services
  config  <SERVICE_NAME>        Create or edit a service configuration
  start   <SERVICE_NAME|all>    Start service (app, health checker, file watcher)
  stop    <SERVICE_NAME|all>    Stop service
  restart <SERVICE_NAME|all>    Restart service (stop + start)
  restart-app <SERVICE_NAME|all>    Restart application only (keep monitors)
  restart-monitor <SERVICE_NAME|all> Restart monitors (health checker, file watcher)
  status  <SERVICE_NAME|all>    Show service status (all = overview table)
  log     <SERVICE_NAME>        Monitor service log file (tail -f)
  log-rotate <SERVICE_NAME|all> Rotate log files and delete old ones
  clean   <SERVICE_NAME|all>    Clean state files (must stop first)
  del     <SERVICE_NAME>        Delete service (config, state, logs)

Configuration:
  Service configs are stored in: ${CONF_DIR}/

Examples:
  $0 config myapp          # Create/edit config for 'myapp'
  $0 start myapp           # Start 'myapp' service
  $0 status all            # Show all services status overview
  $0 stop all              # Stop all services

EOF
}
