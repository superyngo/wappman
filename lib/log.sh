#!/bin/bash
# lib/log.sh - Logging utility
#
# Provides: log()
# Depends on: MANAGER_LOG_FILE (global)

log() {
  mkdir -p "$(dirname "$MANAGER_LOG_FILE")"
  echo "[$(date '+%F %T')] $*" >> "$MANAGER_LOG_FILE"
}
