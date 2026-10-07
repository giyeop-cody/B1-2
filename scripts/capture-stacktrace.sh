#!/usr/bin/env bash
# Deadlock 발생 시 스레드별 스택 트레이스 캡처 (B1-2 원본 레포 vm/capture-stacktrace.sh 개선본)
# 사용: ./capture-stacktrace.sh <PID> [출력경로]
#
# 원본 대비 개선 (실측에서 드러난 문제 때문에):
#  1) agent-leak-app 은 "부모(수퍼바이저) + 자식(실제 워커)" 2프로세스 구조다.
#     부모만 캡처하면 wchan=do_wait 만 보이고 교착상태 근거가 전혀 안 나온다 → 자식까지 캡처.
#  2) 원본의 "[Analysis] wchan=futex_wait_queue → ..." 는 실제 관측값이 아니라 고정 문자열이다.
#     → 관측된 wchan/syscall 로부터 결론을 조립하도록 변경.
set -euo pipefail

PID="${1:?Usage: capture-stacktrace.sh <PID> [출력경로]}"
OUTPUT="${2:-/var/log/agent-app/stacktrace_$(date +%Y%m%d_%H%M%S).txt}"

syscall_name() {
  case "$1" in
    202) echo "futex" ;;
    61)  echo "wait4" ;;
    230) echo "clock_nanosleep" ;;
    35)  echo "nanosleep" ;;
    0)   echo "read" ;;
    232) echo "epoll_wait" ;;
    42)  echo "connect" ;;
    *)   echo "syscall_$1" ;;
  esac
}

dump_target() {
  local pid="$1" label="$2"
  echo "================ $label (PID $pid) ================"
  echo "--- ps -p $pid ---"
  ps -p "$pid" -o pid,ppid,%cpu,%mem,rss,stat,etime,cmd --no-headers 2>/dev/null || { echo "(없음)"; return; }
  echo
  echo "--- ps -T -p $pid (Thread List) ---"
  ps -T -p "$pid" -o pid,tid,%cpu,%mem,stat,wchan:24,cmd 2>/dev/null || true
  echo
  if command -v gdb &>/dev/null; then
    echo "--- gdb thread backtrace ---"
    gdb -batch -ex "thread apply all bt" -p "$pid" 2>&1 || true
  elif command -v pstack &>/dev/null; then
    echo "--- pstack $pid ---"
    pstack "$pid" 2>&1 || true
  else
    echo "--- /proc 기반 스레드 분석 (gdb/pstack 없음) ---"
    for tid in $(ls "/proc/$pid/task/" 2>/dev/null); do
      local st wchan sc scnum
      st=$(awk '/^State:/{print $2,$3}' "/proc/$pid/task/$tid/status" 2>/dev/null || echo "?")
      wchan=$(cat "/proc/$pid/task/$tid/wchan" 2>/dev/null || echo "?")
      sc=$(cat "/proc/$pid/task/$tid/syscall" 2>/dev/null || echo "")
      scnum="${sc%% *}"
      echo "[TID=$tid] comm=$(cat "/proc/$pid/task/$tid/comm" 2>/dev/null) state=$st wchan=$wchan syscall=${scnum:-?}($(syscall_name "${scnum:-0}"))"
      local kstack
      kstack=$(cat "/proc/$pid/task/$tid/stack" 2>/dev/null || true)
      if [[ -n "$kstack" ]]; then
        echo "$kstack" | head -8 | sed 's/^/    /'
      else
        echo "    kernel_stack: (읽기 불가 — CAP_SYS_PTRACE/커널 옵션 필요)"
      fi
    done
  fi
  echo
}

{
  echo "=== Stack Trace Capture for PID $PID ==="
  echo "Timestamp: $(date '+%F %T')"
  echo "Capture method: auto-detect (gdb > pstack > /proc)"
  echo "tool availability: gdb=$(command -v gdb || echo none) pstack=$(command -v pstack || echo none)"
  echo
  echo "--- 프로세스 트리 ---"
  ps -o pid,ppid,rss,stat,etime,cmd --ppid "$PID" --no-headers 2>/dev/null || true
  ps -p "$PID" -o pid,ppid,rss,stat,etime,cmd --no-headers 2>/dev/null || true
  echo
  dump_target "$PID" "TARGET(부모/수퍼바이저)"
  for child in $(pgrep -P "$PID" 2>/dev/null); do
    dump_target "$child" "CHILD(실제 워커)"
  done

  echo "================ 관측값 기반 판정 ================"
  FUTEX_TIDS=0; TOTAL_TIDS=0; WAIT_TIDS=0
  for pid in "$PID" $(pgrep -P "$PID" 2>/dev/null); do
    for tid in $(ls "/proc/$pid/task/" 2>/dev/null); do
      TOTAL_TIDS=$((TOTAL_TIDS+1))
      wchan=$(cat "/proc/$pid/task/$tid/wchan" 2>/dev/null || echo "")
      scnum=$(cut -d' ' -f1 "/proc/$pid/task/$tid/syscall" 2>/dev/null || echo "")
      case "$wchan" in *futex*) FUTEX_TIDS=$((FUTEX_TIDS+1));; esac
      [[ "$scnum" == "61" ]] && WAIT_TIDS=$((WAIT_TIDS+1))
    done
  done
  echo "total_threads=$TOTAL_TIDS futex_wait_threads=$FUTEX_TIDS wait4_threads=$WAIT_TIDS"
  if (( FUTEX_TIDS >= 2 )); then
    echo "판정: 워커 스레드 $FUTEX_TIDS 개가 futex(락) 대기 중 → 교착상태(순환 대기) 정황 성립"
  elif (( FUTEX_TIDS == 1 )); then
    echo "판정: futex 대기 스레드 1개 — 단독 락 대기(교착-state 단정 불가)"
  else
    echo "판정: futex 대기 스레드 없음 — 이 프로세스 트리에서는 교착상태 근거 미확인"
  fi
  echo
  echo "=== Capture complete: $OUTPUT ==="
} | tee "$OUTPUT"
