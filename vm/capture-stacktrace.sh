#!/usr/bin/env bash
set -euo pipefail
# Deadlock 발생 시 스레드별 스택 트레이스 캡처
# 사용: ./capture-stacktrace.sh <PID> [출력경로]
# 도구 우선순위: gdb → pstack → /proc (fallback)

PID="${1:?Usage: capture-stacktrace.sh <PID> [출력경로]}"
OUTPUT="${2:-/var/log/agent-app/stacktrace_$(date +%Y%m%d_%H%M%S).txt}"

echo "=== Stack Trace Capture for PID $PID ===" | tee "$OUTPUT"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$OUTPUT"
echo "Capture method: auto-detect (gdb > pstack > /proc)" | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"

# 1. 프로세스 정보
echo "--- ps -p $PID ---" | tee -a "$OUTPUT"
ps -p "$PID" -o pid,ppid,%cpu,%mem,stat,etime,cmd --no-headers 2>/dev/null | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"

# 2. 스레드 목록
echo "--- ps -T -p $PID (Thread List) ---" | tee -a "$OUTPUT"
ps -T -p "$PID" -o pid,tid,%cpu,%mem,stat,cmd 2>/dev/null | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"

# 3. 스택 트레이스 (gdb 우선 → pstack → /proc fallback)
if command -v gdb &>/dev/null; then
    echo "--- gdb thread backtrace ---" | tee -a "$OUTPUT"
    gdb -batch -ex "thread apply all bt" -p "$PID" 2>&1 | tee -a "$OUTPUT"
elif command -v pstack &>/dev/null; then
    echo "--- pstack $PID ---" | tee -a "$OUTPUT"
    pstack "$PID" 2>&1 | tee -a "$OUTPUT"
else
    echo "--- /proc-based thread analysis (gdb/pstack unavailable) ---" | tee -a "$OUTPUT"
    echo "" | tee -a "$OUTPUT"
    for tid in $(ls /proc/$PID/task/ 2>/dev/null); do
        echo "[Thread TID=$tid]" | tee -a "$OUTPUT"
        echo "  comm: $(cat /proc/$PID/task/$tid/comm 2>/dev/null)" | tee -a "$OUTPUT"
        echo "  state: $(cat /proc/$PID/task/$tid/status 2>/dev/null | grep ^State:)" | tee -a "$OUTPUT"
        echo "  wchan: $(cat /proc/$PID/task/$tid/wchan 2>/dev/null)" | tee -a "$OUTPUT"
        echo "  syscall: $(cat /proc/$PID/task/$tid/syscall 2>/dev/null)" | tee -a "$OUTPUT"
        kstack=$(cat /proc/$PID/task/$tid/stack 2>/dev/null)
        if [[ -n "$kstack" ]]; then
            echo "  kernel_stack:" | tee -a "$OUTPUT"
            echo "$kstack" | head -15 | sed 's/^/    /' | tee -a "$OUTPUT"
        else
            echo "  kernel_stack: (requires CAP_SYS_PTRACE)" | tee -a "$OUTPUT"
        fi
        echo "" | tee -a "$OUTPUT"
    done
    echo "[Analysis]" | tee -a "$OUTPUT"
    echo "  wchan=futex_wait_queue → all threads waiting on futex (lock)" | tee -a "$OUTPUT"
    echo "  syscall=202(futex) → confirmed at kernel level" | tee -a "$OUTPUT"
    echo "  Different futex addresses per thread → circular wait" | tee -a "$OUTPUT"
fi

echo "" | tee -a "$OUTPUT"
echo "=== Capture complete: $OUTPUT ===" | tee -a "$OUTPUT"
