#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVIDENCE="$ROOT/evidence/final-validation"

required=(
  oom-before-app.log
  oom-before-monitor.log
  oom-after-app.log
  oom-after-monitor.log
  cpu-before-app.log
  cpu-before-monitor.log
  cpu-after-app.log
  cpu-after-monitor.log
  deadlock-before-app.log
  deadlock-before-process-samples.txt
  deadlock-before-gdb-stacktrace.txt
  deadlock-after-app.log
  verification-summary.txt
)

for file in "${required[@]}"; do
  [[ -s "$EVIDENCE/$file" ]] || { echo "FAIL: missing/empty $file" >&2; exit 1; }
done

grep -Fq 'Memory limit exceeded' "$EVIDENCE/oom-before-app.log"
grep -Fq 'MEMORY RECOVERED' "$EVIDENCE/oom-after-app.log"
grep -Fq 'CPU Threshold Violated' "$EVIDENCE/cpu-before-app.log"
grep -Fq 'Cooldown complete' "$EVIDENCE/cpu-after-app.log"
grep -Fq 'Status: BLOCKED' "$EVIDENCE/deadlock-before-app.log"
grep -Fq 'futex_wait_queue' "$EVIDENCE/deadlock-before-process-samples.txt"
grep -Fq 'gdb thread backtrace' "$EVIDENCE/deadlock-before-gdb-stacktrace.txt"
grep -Fq 'PyThread_acquire_lock_timed' "$EVIDENCE/deadlock-before-gdb-stacktrace.txt"
grep -Fq 'All tasks completed' "$EVIDENCE/deadlock-after-app.log"
grep -Fq 'B1-2 FINAL RUNTIME VALIDATION: ALL PASS' "$EVIDENCE/verification-summary.txt"

# 비교 실험에서 한 변수만 바뀌었는지 metadata로 확인한다.
grep -Fq 'MEMORY_LIMIT=256' "$EVIDENCE/oom-before-metadata.txt"
grep -Fq 'MEMORY_LIMIT=512' "$EVIDENCE/oom-after-metadata.txt"
grep -Fq 'CPU_MAX_OCCUPY=50' "$EVIDENCE/oom-before-metadata.txt"
grep -Fq 'CPU_MAX_OCCUPY=50' "$EVIDENCE/oom-after-metadata.txt"
grep -Fq 'CPU_MAX_OCCUPY=100' "$EVIDENCE/cpu-before-metadata.txt"
grep -Fq 'CPU_MAX_OCCUPY=50' "$EVIDENCE/cpu-after-metadata.txt"
grep -Fq 'MULTI_THREAD_ENABLE=true' "$EVIDENCE/deadlock-before-metadata.txt"
grep -Fq 'MULTI_THREAD_ENABLE=false' "$EVIDENCE/deadlock-after-metadata.txt"

bash -n "$ROOT"/vm/*.sh "$ROOT"/scripts/*.sh
git -C "$ROOT" diff --check

if pgrep -x agent-leak-app >/dev/null 2>&1; then
  echo 'FAIL: agent-leak-app process still running' >&2
  exit 1
fi
if ss -ltn 2>/dev/null | grep -q ':15034 '; then
  echo 'FAIL: port 15034 still listening' >&2
  exit 1
fi

printf '%s\n' \
  'required_evidence=PASS' \
  'oom_markers=PASS' \
  'cpu_markers=PASS' \
  'deadlock_gdb_and_futex=PASS' \
  'controlled_variables=PASS' \
  'shell_syntax=PASS' \
  'process_cleanup=PASS' \
  'B1-2 FINAL EVIDENCE CHECK: ALL PASS'
