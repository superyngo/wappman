#!/bin/bash
# lib/status.sh - Status checking utilities
#
# Provides: is_running(), get_uptime()
# Depends on: STATE_DIR (global)

is_running() {
  for proc in app health inotify; do
    local pid_file="$STATE_DIR/${proc}.pid"
    if [ -f "$pid_file" ]; then
      local pid
      pid=$(cat "$pid_file" 2>/dev/null || true)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
      fi
    fi
  done
  return 1
}

get_uptime() {
  local start_time="$1"
  
  if [ -z "$start_time" ] || [ "$start_time" = "0" ]; then
    echo "N/A"
    return
  fi
  
  local now
  now=$(date +%s)
  local uptime=$((now - start_time))
  
  local hours=$((uptime / 3600))
  local minutes=$(( (uptime % 3600) / 60 ))
  local seconds=$((uptime % 60))
  
  if [ "$hours" -gt 0 ]; then
    echo "${hours}h ${minutes}m ${seconds}s"
  elif [ "$minutes" -gt 0 ]; then
    echo "${minutes}m ${seconds}s"
  else
    echo "${seconds}s"
  fi
}
