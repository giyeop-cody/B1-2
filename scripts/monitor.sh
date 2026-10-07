#!/usr/bin/env bash
set -euo pipefail
# B1-2 프로세스 관제 스크립트
# 사용: ./monitor.sh [간격초] [로그경로]
APP_NAME="agent-leak-app"
INTERVAL="${1:-2}"
LOG_FILE="${2:-/var/log/agent-app/monitor.log}"
mkdir -p "$(dirname "$LOG_FILE")"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Monitor started (interval=${INTERVAL}s) ===" | tee -a "$LOG_FILE"
while true; do
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  pid=$(ps aux | grep "[a]gent-leak-app" | sort -k6 -rn | head -1 | awk '{print $2}' 2>/dev/null || true)
  if [[ -z "$pid" ]]; then
    echo "[$ts] PROCESS:$APP_NAME STATUS:NOT_FOUND" | tee -a "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Process terminated. Monitor stopping. ===" | tee -a "$LOG_FILE"
    break
  fi
  stats=$(ps -p "$pid" -o %cpu,%mem,rss,vsz --no-headers 2>/dev/null || true)
  if [[ -n "$stats" ]]; then
    echo "[$ts] PROCESS:$APP_NAME PID:$pid CPU/MEM/RSS/VSZ: $stats" | tee -a "$LOG_FILE"
  fi
  sleep "$INTERVAL"
done
