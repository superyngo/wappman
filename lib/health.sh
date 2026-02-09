#!/bin/bash
# lib/health.sh - Health checker background process
#
# Provides: start_health_checker()
# Depends on: log(), read_state(), write_state(), restart_app(),
#             STATE_DIR, HEALTH_CHECK_INTERVAL (globals)

start_health_checker() {
  (
    trap 'log "health checker stopping"; exit 0' SIGTERM SIGINT
    
    write_state health "STATUS=running" "PID=$$" "INTERVAL=$HEALTH_CHECK_INTERVAL"
    log "health checker started (pid=$$, interval=${HEALTH_CHECK_INTERVAL}s)"
    
    local checks_ok=0
    local checks_fail=0
    
    while true; do
      sleep "$HEALTH_CHECK_INTERVAL"
      
      # Check if app is in crashed state (don't try to restart crashed apps)
      local app_status
      app_status=$(read_state app STATUS)
      
      if [ "$app_status" = "crashed" ]; then
        log "health check: app is in crashed state, health checker stopping"
        write_state health "STATUS=stopped" "PID="
        exit 0
      fi
      
      local app_pid
      app_pid=$(cat "$STATE_DIR/app.pid" 2>/dev/null || true)
      
      if [ -z "$app_pid" ] || ! kill -0 "$app_pid" 2>/dev/null; then
        log "health check: app not running, triggering restart..."
        checks_fail=$((checks_fail + 1))
        write_state health "CHECKS_FAIL=$checks_fail" "LAST_CHECK_TIME=$(date +%s)"
        
        # restart_app will handle failure, and may set app to crashed state
        restart_app "health_check"
        
        # After restart attempt, check if app is now in crashed state
        app_status=$(read_state app STATUS)
        if [ "$app_status" = "crashed" ]; then
          log "health check: app crashed after restart attempt, health checker stopping"
          write_state health "STATUS=stopped" "PID="
          exit 0
        fi
      else
        checks_ok=$((checks_ok + 1))
        write_state health "CHECKS_OK=$checks_ok" "LAST_CHECK_TIME=$(date +%s)"
      fi
    done
  ) &
  
  local health_pid=$!
  echo "$health_pid" > "$STATE_DIR/health.pid"
}
