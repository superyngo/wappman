#!/bin/bash
# lib/watcher.sh - File watcher (inotify) background process
#
# Provides: build_watch_paths(), start_inotify_watcher()
# Depends on: log(), write_state(), restart_app(),
#             WATCH_FILES, RESTART_FILE, STATE_DIR (globals)

build_watch_paths() {
  WATCH_PATHS=()
  WATCH_FILES_ARRAY=()
  local has_valid=false
  
  # Parse WATCH_FILES
  if [ -n "${WATCH_FILES:-}" ]; then
    read -r -a WATCH_FILES_ARRAY <<< "$WATCH_FILES"
    
    for f in "${WATCH_FILES_ARRAY[@]}"; do
      if [ -f "$f" ]; then
        local dir
        dir="$(dirname "$f")"
        
        # Add directory to watch paths (unique)
        local exists=false
        for p in "${WATCH_PATHS[@]}"; do
          [ "$p" = "$dir" ] && exists=true && break
        done
        $exists || WATCH_PATHS+=("$dir")
        
        has_valid=true
      else
        log "WARNING: WATCH_FILES path not found, skipping: $f"
      fi
    done
  fi
  
  # Parse RESTART_FILE
  if [ -n "${RESTART_FILE:-}" ]; then
    local restart_dir
    restart_dir="$(dirname "$RESTART_FILE")"
    
    if [ -d "$restart_dir" ]; then
      local exists=false
      for p in "${WATCH_PATHS[@]}"; do
        [ "$p" = "$restart_dir" ] && exists=true && break
      done
      $exists || WATCH_PATHS+=("$restart_dir")
      
      has_valid=true
    else
      log "WARNING: RESTART_FILE directory not found, skipping: $restart_dir"
    fi
  fi
  
  if ! $has_valid; then
    return 1
  fi
  
  return 0
}

start_inotify_watcher() {
  (
    # Ensure this subshell and all children terminate together
    trap 'pkill -P $$; log "inotify watcher stopping"; exit 0' SIGTERM SIGINT
    
    log "inotify watcher started (pid=$$, watching ${#WATCH_PATHS[@]} paths)"
    
    local events_triggered=0
    
    # Start inotifywait and capture its output
    inotifywait -m \
      -e close_write -e moved_to -e delete_self \
      --format '%w%f|%e' \
      "${WATCH_PATHS[@]}" 2>&1 | while IFS='|' read -r path ev; do
      
      # Skip inotify info messages
      [[ "$path" =~ ^Watches\ established ]] && continue
      
      local should_restart=false
      local reason=""
      
      # Check restart file
      if [ -n "${RESTART_FILE:-}" ] && [ "$path" = "$RESTART_FILE" ]; then
        should_restart=true
        reason="restart_file"
      fi
      
      # Check watched files
      if ! $should_restart; then
        for f in "${WATCH_FILES_ARRAY[@]}"; do
          if [ "$path" = "$f" ]; then
            should_restart=true
            reason="file_change:$(basename "$path")"
            break
          fi
        done
      fi
      
      if $should_restart; then
        log "inotify: $path ($ev) -> restart"
        events_triggered=$((events_triggered + 1))
        write_state inotify \
          "EVENTS_TRIGGERED=$events_triggered" \
          "LAST_EVENT_TIME=$(date +%s)" \
          "LAST_EVENT_PATH=$path"
        
        # Always attempt restart, even if app is in crashed state
        # Use || true to prevent subshell exit on failure due to set -e
        restart_app "$reason" || {
          log "inotify: restart attempt failed, but continuing to monitor"
        }
        
        # Clean up restart file
        if [ "$reason" = "restart_file" ]; then
          rm -f "$RESTART_FILE" 2>/dev/null || true
        fi
      fi
    done
  ) &
  
  local inotify_pid=$!
  echo "$inotify_pid" > "$STATE_DIR/inotify.pid"
  
  # Write state after getting the actual PID
  write_state inotify \
    "STATUS=running" \
    "PID=$inotify_pid" \
    "WATCH_COUNT=${#WATCH_PATHS[@]}" \
    "WATCH_FILES=${WATCH_FILES:-}" \
    "RESTART_FILE=${RESTART_FILE:-}"
}
