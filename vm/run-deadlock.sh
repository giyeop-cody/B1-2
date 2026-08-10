#!/usr/bin/env bash
set -euo pipefail
# Deadlock 시나리오: MULTI_THREAD_ENABLE 변화에 따른 교착상태 관측
source ~/.bash_profile
mkdir -p "$AGENT_LOG_DIR"
MODE="${1:-before}"
case "$MODE" in
  before) MULTI_THREAD_ENABLE=true ;;
  after)  MULTI_THREAD_ENABLE=false ;;
  *) echo "Usage: run-deadlock.sh [before|after]"; exit 1 ;;
esac
export MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50 MULTI_THREAD_ENABLE
echo "=== Deadlock $MODE: MULTI_THREAD_ENABLE=$MULTI_THREAD_ENABLE ==="
"$AGENT_HOME/agent-leak-app" 2>&1 | tee "$AGENT_LOG_DIR/app_deadlock_${MODE}.log"
