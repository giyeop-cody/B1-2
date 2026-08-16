#!/usr/bin/env bash
set -euo pipefail
# OOM 시나리오: MEMORY_LIMIT 변화에 따른 MemoryGuard 트리거 관측
source ~/.bash_profile
LOG_DIR="${AGENT_LOG_DIR}"
mkdir -p "$LOG_DIR"

MODE="${1:-before}"
case "$MODE" in
  before) MEMORY_LIMIT=256 ;;
  after)  MEMORY_LIMIT=512 ;;
  *) echo "Usage: run-oom.sh [before|after]"; exit 1 ;;
esac
# OOM 비교에서는 MEMORY_LIMIT만 바꾼다. CPU는 안전값 50으로 고정한다.
export MEMORY_LIMIT CPU_MAX_OCCUPY=50 MULTI_THREAD_ENABLE=false

echo "=== OOM $MODE: MEMORY_LIMIT=$MEMORY_LIMIT ==="
"$AGENT_HOME/agent-leak-app" 2>&1 | tee "$LOG_DIR/app_oom_${MODE}.log"
