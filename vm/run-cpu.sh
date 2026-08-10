#!/usr/bin/env bash
set -euo pipefail
# CPU Spike 시나리오: CPU_MAX_OCCUPY 변화에 따른 Watchdog 트리거 관측
source ~/.bash_profile
mkdir -p "$AGENT_LOG_DIR"
MODE="${1:-before}"
case "$MODE" in
  before) CPU_MAX_OCCUPY=100 ;;
  after)  CPU_MAX_OCCUPY=50 ;;
  *) echo "Usage: run-cpu.sh [before|after]"; exit 1 ;;
esac
export MEMORY_LIMIT=512 CPU_MAX_OCCUPY MULTI_THREAD_ENABLE=false
echo "=== CPU $MODE: CPU_MAX_OCCUPY=$CPU_MAX_OCCUPY ==="
"$AGENT_HOME/agent-leak-app" 2>&1 | tee "$AGENT_LOG_DIR/app_cpu_${MODE}.log"
