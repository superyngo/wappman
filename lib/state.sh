#!/bin/bash
# lib/state.sh - State directory management
#
# Provides: init_state_dir(), read_state(), write_state()
# Depends on: STATE_DIR (global)

init_state_dir() {
  mkdir -p "$STATE_DIR" 2>/dev/null || {
    echo "ERROR: Failed to create state directory: $STATE_DIR"
    exit 1
  }
}

read_state() {
  local component="$1"
  local key="$2"
  local state_file="$STATE_DIR/${component}.state"
  
  if [ -f "$state_file" ]; then
    grep "^${key}=" "$state_file" 2>/dev/null | cut -d= -f2- || echo ""
  else
    echo ""
  fi
}

write_state() {
  local component="$1"
  shift
  local state_file="$STATE_DIR/${component}.state"
  local temp_file="${state_file}.tmp"
  
  # Remove existing temp file if present
  [ -f "$temp_file" ] && rm -f "$temp_file"
  
  # Read existing state
  if [ -f "$state_file" ]; then
    cp "$state_file" "$temp_file"
  else
    : > "$temp_file"
  fi
  
  # Update key-value pairs
  for pair in "$@"; do
    local key="${pair%%=*}"
    local value="${pair#*=}"
    
    if grep -q "^${key}=" "$temp_file" 2>/dev/null; then
      sed -i "s|^${key}=.*|${key}=${value}|" "$temp_file"
    else
      echo "${key}=${value}" >> "$temp_file"
    fi
  done
  
  # Atomic write
  mv "$temp_file" "$state_file"
}
