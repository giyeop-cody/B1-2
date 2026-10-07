#!/usr/bin/env bash
# B1-2 [2/3] 시나리오 실행기 — 장애 재현 + 증거 수집
# 실행: sudo bash 20-run-scenario.sh <oom|cpu|deadlock> <before|after>
#
# before/after 는 미션이 요구하는 "환경변수 변경 전후 비교" 다. 바꿀 변수 하나만 바꾸고
# 나머지는 고정한다(B1-2 원본 레포의 run-*.sh 와 동일한 매트릭스).
#
# [경로 주의] 실행 중 로그는 반드시 /var/log/agent-app 아래에 둔다. 이 레포(/home/user/...) 는
#   /home/user 가 700 이라 실행 계정(agent-admin)이 경로를 탐색(traverse)할 수 없다 — 실측으로
#   "Permission denied" 확인. 수집이 끝나면 root 가 레포 evidence/ 로 복사해 보관한다.
set -uo pipefail
source "$(dirname "$0")/00-env.sh"
[[ $EUID -eq 0 ]] || { echo "root(sudo) 로 실행하세요"; exit 1; }

SCEN="${1:?Usage: 20-run-scenario.sh <oom|cpu|deadlock> <before|after>}"
MODE="${2:?Usage: 20-run-scenario.sh <oom|cpu|deadlock> <before|after>}"
EV="$B12_LAB/evidence/$SCEN"
RUNDIR="$AGENT_LOG_DIR/b1-2/$SCEN"
mkdir -p "$EV" "$RUNDIR"
chown "$AGENT_ADMIN:$GRP_CORE" "$RUNDIR"
chmod 775 "$RUNDIR"

APPLOG="$RUNDIR/app_${MODE}.log"
MONLOG="$RUNDIR/monitor_${MODE}.log"
PSLOG="$RUNDIR/process-samples_${MODE}.txt"
META="$RUNDIR/metadata_${MODE}.txt"

case "$SCEN-$MODE" in
  oom-before)       MEMORY_LIMIT=256 CPU_MAX_OCCUPY=50  MULTI_THREAD_ENABLE=false ;;
  oom-after)        MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50  MULTI_THREAD_ENABLE=false ;;
  cpu-before)       MEMORY_LIMIT=512 CPU_MAX_OCCUPY=100 MULTI_THREAD_ENABLE=false ;;
  cpu-after)        MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50  MULTI_THREAD_ENABLE=false ;;
  deadlock-before)  MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50  MULTI_THREAD_ENABLE=true  ;;
  deadlock-after)   MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50  MULTI_THREAD_ENABLE=false ;;
  *) echo "unknown case: $SCEN-$MODE"; exit 1 ;;
esac

echo "########## SCENARIO $SCEN / $MODE ##########"
echo "MEMORY_LIMIT=$MEMORY_LIMIT CPU_MAX_OCCUPY=$CPU_MAX_OCCUPY MULTI_THREAD_ENABLE=$MULTI_THREAD_ENABLE"
echo "runtime dir: $RUNDIR"

pkill -f "$B12_APP" 2>/dev/null || true
sleep 2

cat > "$META" <<EOF
case=$SCEN-$MODE
timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
host=$(hostname)
binary=$B12_APP
MEMORY_LIMIT=$MEMORY_LIMIT
CPU_MAX_OCCUPY=$CPU_MAX_OCCUPY
MULTI_THREAD_ENABLE=$MULTI_THREAD_ENABLE
run_as=$AGENT_ADMIN
EOF

echo "-- 앱 실행 (agent-admin) --"
: > "$APPLOG"; chown "$AGENT_ADMIN:$GRP_CORE" "$APPLOG"; chmod 664 "$APPLOG"
runuser -u "$AGENT_ADMIN" -- bash -c "
  . '$AGENT_HOME/env.sh'
  export MEMORY_LIMIT=$MEMORY_LIMIT CPU_MAX_OCCUPY=$CPU_MAX_OCCUPY MULTI_THREAD_ENABLE=$MULTI_THREAD_ENABLE
  setsid nohup '$B12_APP' >> '$APPLOG' 2>&1 < /dev/null &
"
# 부트 완료 대기 (관제를 앱보다 먼저 켜면 NOT_FOUND 로 즉시 종료된다 — 실측으로 확인)
for i in $(seq 1 20); do
  grep -q 'Agent READY' "$APPLOG" 2>/dev/null && break
  sleep 1
done
# agent-leak-app 은 "부모(수퍼바이저, RSS ~1MB, wchan=do_wait) + 자식(실제 워커)" 2프로세스 구조다.
# 관측 대상은 워커여야 한다 — 부모만 보면 CPU/MEM 이 항상 ~0 이라 장애가 아무것도 안 보인다(실측 확인).
PARENT="$(pgrep -f "$B12_APP" | head -1 || true)"
WORKER="$(for p in $(pgrep -f "$B12_APP"); do
            echo "$(awk '/VmRSS/{print $2}' "/proc/$p/status" 2>/dev/null || echo 0) $p"
          done | sort -rn | head -1 | awk '{print $2}')"
PID="${WORKER:-$PARENT}"

echo "-- 프로세스 관제(2초 간격) 시작 --"
runuser -u "$AGENT_ADMIN" -- bash -c "
  setsid nohup '$B12_PROCMON' 2 '$MONLOG' >/dev/null 2>&1 < /dev/null &
"
sleep 2
echo "app parent=${PARENT:-none} worker=${WORKER:-none} (관측 대상=worker)"
{
  echo "app_parent_pid=$PARENT"
  echo "app_worker_pid=$WORKER"
  echo "observed_pid=$PID"
} >> "$META"

: > "$PSLOG"
{
  echo "parent_pid=$PARENT"
  echo "worker_pid=$WORKER"
  echo "--- 프로세스 트리 ---"
  ps -o pid,ppid,rss,stat,etime,cmd -p "$PARENT" --no-headers 2>/dev/null
  ps -o pid,ppid,rss,stat,etime,cmd --ppid "$PARENT" --no-headers 2>/dev/null
} >> "$PSLOG"
sample_ps() {
  {
    echo "=== sample $1 @ $(date '+%F %T') ==="
    ps -p "$PID" -o pid,ppid,%cpu,%mem,rss,stat,etime,cmd 2>/dev/null || echo "(프로세스 없음 — 종료됨)"
    ps -L -p "$PID" -o pid,tid,%cpu,%mem,stat,wchan:24,cmd 2>/dev/null || true
    echo "-- top 배치 스냅샷 --"
    top -b -n 1 2>/dev/null | sed -n '1,8p'
    top -b -n 1 2>/dev/null | grep -E 'agent-leak|%Cpu|MiB Mem' | head -4
  } >> "$PSLOG"
}

if [[ "$SCEN" == "deadlock" && "$MODE" == "before" ]]; then
  echo "-- 데드락 관측: 90초 동안 10초 간격 표본 (PID 는 있는데 CPU/MEM 이 정체되는지 확인) --"
  for i in $(seq 1 9); do
    sleep 10
    sample_ps "$i"
    if ! kill -0 "$PID" 2>/dev/null; then echo "프로세스가 종료됨(예상과 다름)"; break; fi
  done
  echo "-- 스레드 스택 캡처 --"
  bash "$AGENT_HOME/bin/capture-stacktrace.sh" "${PARENT:-$PID}" "$RUNDIR/stacktrace_${MODE}.txt" >/dev/null 2>&1 || echo "(스택 캡처 실패)"
  tail -6 "$RUNDIR/stacktrace_${MODE}.txt" 2>/dev/null
  echo "-- 관측 종료, 프로세스 정리(kill -9) --"
  kill -9 "$PID" 2>/dev/null || true
  echo "result=HUNG_THEN_KILLED" >> "$META"
else
  echo "-- 자력 종료 대기 (최대 170초) --"
  for i in $(seq 1 170); do
    kill -0 "$PID" 2>/dev/null || { echo "프로세스 종료 @ ${i}s"; break; }
    if (( i % 15 == 0 )); then sample_ps "$((i/15))"; fi
    sleep 1
  done
  if kill -0 "$PID" 2>/dev/null; then
    echo "170초까지 생존 → SURVIVED (정상 운영으로 간주, 정리 kill)"
    echo "result=SURVIVED_170s" >> "$META"
    sample_ps final
    kill -9 "$PID" 2>/dev/null || true
  else
    echo "result=TERMINATED" >> "$META"
  fi
fi

pkill -f "$B12_PROCMON" 2>/dev/null || true
sleep 1

echo
echo "-- 앱 로그 마지막 14줄 --"
tail -14 "$APPLOG"
echo
echo "-- 프로세스 관제 로그 (첫 3줄 / 마지막 6줄) --"
head -3 "$MONLOG" 2>/dev/null
tail -6 "$MONLOG" 2>/dev/null || echo "(없음)"

echo
echo "-- 레포 evidence/ 로 복사 --"
cp -f "$RUNDIR"/*"$MODE"* "$EV"/ 2>/dev/null || true
chown -R 1001:1001 "$EV" 2>/dev/null || true
ls -l "$EV"
echo "########## DONE $SCEN/$MODE ##########"
