#!/usr/bin/env bash
# B1-2 장애 3종 Before/After와 실제 gdb 스택을 한 번에 수집한다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${B1_WORK_DIR:-/home/user/b1-2-work}"
EVIDENCE_DIR="$ROOT/evidence/final-validation"
APP_HOME="$WORK_DIR/agent-app"
APP_BIN="$APP_HOME/agent-leak-app"
HOME_DIR="$WORK_DIR/home"
APP_PID=""
MONITOR_PID=""

mkdir -p "$APP_HOME/upload_files" "$APP_HOME/api_keys" "$WORK_DIR/logs" "$HOME_DIR" "$EVIDENCE_DIR"
printf 'agent_api_key_test' > "$APP_HOME/api_keys/secret.key"
chmod 600 "$APP_HOME/api_keys/secret.key"

case "$(uname -m)" in
  x86_64|amd64) SOURCE_BIN="$ROOT/agent-leak-app-x86" ;;
  arm64|aarch64) SOURCE_BIN="$ROOT/agent-leak-app-arm64" ;;
  *) echo "지원하지 않는 CPU: $(uname -m)" >&2; exit 2 ;;
esac
install -m 0755 "$SOURCE_BIN" "$APP_BIN"

cat > "$HOME_DIR/.bash_profile" <<ENV
export AGENT_HOME="$APP_HOME"
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="$APP_HOME/upload_files"
export AGENT_KEY_PATH="$APP_HOME/api_keys"
export AGENT_LOG_DIR="$WORK_DIR/logs"
ENV

export HOME="$HOME_DIR"
export AGENT_HOME="$APP_HOME"
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="$APP_HOME/upload_files"
export AGENT_KEY_PATH="$APP_HOME/api_keys"
export AGENT_LOG_DIR="$WORK_DIR/logs"

cleanup() {
  set +e
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM -- "-$APP_PID" 2>/dev/null || kill -TERM "$APP_PID" 2>/dev/null
    sleep 1
    kill -KILL -- "-$APP_PID" 2>/dev/null || true
  fi
  pkill -TERM -x agent-leak-app 2>/dev/null || true
  sleep 1
  pkill -KILL -x agent-leak-app 2>/dev/null || true
  if [[ -n "$MONITOR_PID" ]] && kill -0 "$MONITOR_PID" 2>/dev/null; then
    kill "$MONITOR_PID" 2>/dev/null || true
  fi
  wait "$APP_PID" 2>/dev/null || true
  wait "$MONITOR_PID" 2>/dev/null || true
  APP_PID=""
  MONITOR_PID=""
  set -e
}
trap cleanup EXIT INT TERM

start_case() {
  local label="$1" memory="$2" cpu="$3" threads="$4"
  cleanup
  printf '%s\n' \
    "case=$label" \
    "timestamp=$(date -Iseconds)" \
    "MEMORY_LIMIT=$memory" \
    "CPU_MAX_OCCUPY=$cpu" \
    "MULTI_THREAD_ENABLE=$threads" \
    "binary=$(basename "$SOURCE_BIN")" \
    > "$EVIDENCE_DIR/${label}-metadata.txt"

  echo "=== START $label: MEMORY=$memory CPU=$cpu THREAD=$threads ==="
  setsid env \
    MEMORY_LIMIT="$memory" \
    CPU_MAX_OCCUPY="$cpu" \
    MULTI_THREAD_ENABLE="$threads" \
    "$APP_BIN" > "$EVIDENCE_DIR/${label}-app.log" 2>&1 &
  APP_PID=$!
  sleep 1
  "$ROOT/vm/monitor.sh" 1 "$EVIDENCE_DIR/${label}-monitor.log" >/dev/null 2>&1 &
  MONITOR_PID=$!
}

wait_for_marker() {
  local label="$1" marker="$2" max_seconds="$3"
  local logfile="$EVIDENCE_DIR/${label}-app.log"
  for _ in $(seq 1 "$max_seconds"); do
    if grep -Fq "$marker" "$logfile" 2>/dev/null; then
      echo "MARKER PASS [$label]: $marker"
      return 0
    fi
    if [[ -n "$APP_PID" ]] && ! kill -0 "$APP_PID" 2>/dev/null; then
      echo "프로세스가 marker 전에 종료됨: $label / $marker" >&2
      tail -30 "$logfile" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "marker 시간 초과: $label / $marker" >&2
  tail -30 "$logfile" >&2 || true
  return 1
}

wait_for_exit() {
  local max_seconds="$1"
  for _ in $(seq 1 "$max_seconds"); do
    if ! pgrep -x agent-leak-app >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "프로세스가 예상 시간 안에 종료되지 않음" >&2
  return 1
}

# 1. OOM: MEMORY_LIMIT만 256 → 512로 바꾼다.
start_case "oom-before" 256 50 false
wait_for_marker "oom-before" "Memory limit exceeded" 55
wait_for_exit 10
cleanup

start_case "oom-after" 512 50 false
wait_for_marker "oom-after" "MEMORY RECOVERED" 90
sleep 8
cleanup

# 2. CPU: CPU_MAX_OCCUPY만 100 → 50으로 바꾼다.
start_case "cpu-before" 512 100 false
wait_for_marker "cpu-before" "CPU Threshold Violated" 65
wait_for_exit 10
cleanup

start_case "cpu-after" 512 50 false
wait_for_marker "cpu-after" "Cooldown complete" 80
sleep 8
cleanup

# 3. Deadlock Before: 실제 gdb 스택과 5회 상태 표본을 저장한다.
start_case "deadlock-before" 512 50 true
wait_for_marker "deadlock-before" "Status: BLOCKED" 30
sleep 3
TARGET_PID="$({
  for pid in $(pgrep -x agent-leak-app); do
    printf '%s %s\n' "$(find "/proc/$pid/task" -mindepth 1 -maxdepth 1 | wc -l)" "$pid"
  done
} | sort -nr | head -1 | awk '{print $2}')"
[[ -n "$TARGET_PID" ]] || { echo "Deadlock target PID를 찾지 못함" >&2; exit 1; }
echo "TARGET_PID=$TARGET_PID"

{
  echo "timestamp=$(date -Iseconds)"
  echo "target_pid=$TARGET_PID"
  for number in 1 2 3 4 5; do
    echo "=== sample $number ==="
    ps -p "$TARGET_PID" -o pid,ppid,%cpu,%mem,stat,etime,cmd
    ps -T -p "$TARGET_PID" -o pid,tid,%cpu,%mem,stat,wchan:25,cmd
    sleep 2
  done
} > "$EVIDENCE_DIR/deadlock-before-process-samples.txt"

sudo "$ROOT/vm/capture-stacktrace.sh" \
  "$TARGET_PID" \
  "$EVIDENCE_DIR/deadlock-before-gdb-stacktrace.txt" >/dev/null
sudo chown "$(id -u):$(id -g)" "$EVIDENCE_DIR/deadlock-before-gdb-stacktrace.txt"
grep -Eq 'gdb thread backtrace|Thread' "$EVIDENCE_DIR/deadlock-before-gdb-stacktrace.txt"
grep -Eq '^#0|#[0-9]+' "$EVIDENCE_DIR/deadlock-before-gdb-stacktrace.txt"
cleanup

# 4. Deadlock After: 순차 작업 완료를 확인한다.
start_case "deadlock-after" 512 50 false
wait_for_marker "deadlock-after" "All tasks completed" 30
sleep 5
cleanup

# 핵심 결과 자동 확인
grep -Fq "Memory limit exceeded" "$EVIDENCE_DIR/oom-before-app.log"
grep -Fq "MEMORY RECOVERED" "$EVIDENCE_DIR/oom-after-app.log"
grep -Fq "CPU Threshold Violated" "$EVIDENCE_DIR/cpu-before-app.log"
grep -Fq "Cooldown complete" "$EVIDENCE_DIR/cpu-after-app.log"
grep -Fq "Status: BLOCKED" "$EVIDENCE_DIR/deadlock-before-app.log"
grep -Fq "All tasks completed" "$EVIDENCE_DIR/deadlock-after-app.log"

{
  echo "validation_timestamp=$(date -Iseconds)"
  echo "oom_before=PASS"
  echo "oom_after=PASS"
  echo "cpu_before=PASS"
  echo "cpu_after=PASS"
  echo "deadlock_before=PASS"
  echo "deadlock_gdb_backtrace=PASS"
  echo "deadlock_after=PASS"
  echo "B1-2 FINAL RUNTIME VALIDATION: ALL PASS"
} | tee "$EVIDENCE_DIR/verification-summary.txt"
