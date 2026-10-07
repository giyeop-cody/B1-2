#!/usr/bin/env bash
# B1-2 [보너스] 스케줄링 알고리즘 추론을 위한 실측 데이터 수집
# 실행: sudo bash 40-scheduling-probe.sh [측정초:기본 12]
# 출력: 표준출력 + $AGENT_LOG_DIR/b1-2/bonus/scheduling-probe.txt
#
# 과제 보너스: "스케줄링 알고리즘을 추론하시오."
# 접근: 추측하지 않고 ① 커널/스케줄러 클래스 ② 스레드 정책·우선순위 ③ cgroup 대역폭 제어
#       ④ 앱이 보고하는 CPU 점유율 vs OS 실측 점유율 ⑤ 대조군(busy loop) 을 각각 측정한다.
set -uo pipefail
source "$(dirname "$0")/00-env.sh"
[[ $EUID -eq 0 ]] || { echo "root(sudo) 로 실행하세요"; exit 1; }
DUR=${1:-12}
OUT_DIR="$AGENT_LOG_DIR/b1-2/bonus"; mkdir -p "$OUT_DIR"; chmod 770 "$OUT_DIR"
OUT="$OUT_DIR/scheduling-probe.txt"
exec > >(tee "$OUT") 2>&1

echo "############ B1-2 보너스: 스케줄링 알고리즘 추론 실측 ############"
echo "측정 시각: $(date '+%F %T %Z') · 측정 길이: ${DUR}s"

echo
echo "=== [1] 커널 & 스케줄러 클래스 근거 ==="
echo "uname -r      : $(uname -r)"
echo "nproc         : $(nproc)"
echo "CPU 모델      : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"
echo "--- /proc/sys/kernel/sched_* (CFS/RT/DL 튜너블 존재 여부) ---"
for k in /proc/sys/kernel/sched_*; do [[ -f $k ]] && echo "  $(basename "$k") = $(cat "$k")"; done
echo "--- /sys/kernel/sched_debug 첫 12줄 ---"
head -12 /sys/kernel/sched_debug 2>/dev/null || echo "  (읽기 불가)"

echo
echo "=== [2] cgroup CPU 제어 상태 (대역폭 제한이 걸려 있는가) ==="
CG="/sys/fs/cgroup/$(awk -F: '$1=="0"{print $3}' /proc/self/cgroup)"
echo "cgroup 경로: $CG"
for f in cpu.max cpu.weight cpu.stat cpuset.cpus.effective; do
  [[ -f $CG/$f ]] && { echo "--- $f ---"; cat "$CG/$f"; }
done

echo
echo "=== [3] agent-leak-app 기동 (CPU_MAX_OCCUPY=50) ==="
pkill -f '[a]gent-leak-app' 2>/dev/null; sleep 1
APPLOG="$OUT_DIR/leak-app.log"
setsid runuser -u "$AGENT_ADMIN" -- bash -c "
  set -a; . '$AGENT_HOME/env.sh'
  export MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50 MULTI_THREAD_ENABLE=false
  export AGENT_LOG_DIR='$OUT_DIR'
  set +a
  nohup '$B12_APP' > '$APPLOG' 2>&1 < /dev/null &
" >/dev/null 2>&1
for _ in $(seq 1 15); do
  pgrep -f '[a]gent-leak-app' >/dev/null && grep -q 'Agent READY' "$APPLOG" 2>/dev/null && break
  sleep 1
done
PID=$(pgrep -f '[a]gent-leak-app' | while read -r p; do echo "$(awk '/VmRSS/{print $2}' /proc/$p/status 2>/dev/null || echo 0) $p"; done | sort -rn | head -1 | cut -d' ' -f2)
[[ -n "${PID:-}" ]] || { echo "앱 기동 실패 (10-deploy-leak-app.sh 먼저 실행 필요)"; exit 1; }
echo "관측 대상 PID=$PID (VmRSS=$(awk '/VmRSS/{print $2}' /proc/$PID/status) KB)"
echo "램프업 대기 30s — CpuWorker 가 5% 에서 서서히 오르는 것을 실측으로 확인했으므로 정상 구간까지 대기"
sleep 30

echo
echo "=== [4] 스레드별 스케줄링 정책·우선순위 (chrt) ==="
command -v chrt >/dev/null && echo "chrt: $(command -v chrt)" || echo "chrt: MISSING"
printf '%-8s %-20s %-24s %-6s %-8s %s\n' TID COMM "chrt(policy/prio)" NICE RT_PRIO WCHAN
for t in /proc/$PID/task/*; do
  tid=$(basename "$t")
  pol=$(chrt -p "$tid" 2>/dev/null | awk -F': *' '/scheduling policy/{p=$2} /priority/{r=$2} END{print p" / "r}')
  nice=$(awk '{print $19}' "$t/stat" 2>/dev/null)
  rtp=$(awk '{print $40}' "$t/stat" 2>/dev/null)
  wc=$(cat "$t/wchan" 2>/dev/null)
  printf '%-8s %-20s %-24s %-6s %-8s %s\n' "$tid" "$(cat "$t/comm" 2>/dev/null)" "${pol:-?}" "${nice:-?}" "${rtp:-?}" "${wc:--}"
done

echo
echo "=== [5] /proc/<pid>/sched — 스케줄러 내부 통계 ==="
if [[ -r /proc/$PID/sched ]]; then
  sed -n '1,25p' /proc/$PID/sched
else
  echo "  /proc/$PID/sched 없음 → 이 커널은 CONFIG_SCHED_DEBUG 미설정 (스케줄러 내부 통계 미노출)"
  ls -l /proc/$PID/sched 2>&1 | head -1
fi

echo
echo "=== [6] ${DUR}s 동안 스레드별 CPU 시간 증분 (utime+stime, USER_HZ=$(getconf CLK_TCK)) ==="
declare -A T0
for t in /proc/$PID/task/*; do tid=$(basename "$t"); T0[$tid]=$(awk '{print $14+$15}' "$t/stat" 2>/dev/null || echo 0); done
CPU0=$(awk '{print $14+$15}' /proc/$PID/stat)
W0=$(date +%s.%N)
sleep "$DUR"
W1=$(date +%s.%N); CPU1=$(awk '{print $14+$15}' /proc/$PID/stat)
HZ=$(getconf CLK_TCK)
ELAPSED=$(awk -v a="$W0" -v b="$W1" 'BEGIN{printf "%.3f", b-a}')
echo "경과 wall: ${ELAPSED}s"
printf '%-8s %-20s %10s %10s\n' TID COMM "틱증분" "CPU%"
for t in /proc/$PID/task/*; do
  tid=$(basename "$t")
  t1=$(awk '{print $14+$15}' "$t/stat" 2>/dev/null || echo 0)
  d=$(( t1 - ${T0[$tid]:-0} ))
  pct=$(awk -v d="$d" -v hz="$HZ" -v e="$ELAPSED" 'BEGIN{printf "%.2f", (d/hz)/e*100}')
  printf '%-8s %-20s %10s %10s\n' "$tid" "$(cat "$t/comm" 2>/dev/null)" "$d" "$pct"
done
echo "---"
awk -v d="$((CPU1-CPU0))" -v hz="$HZ" -v e="$ELAPSED" 'BEGIN{printf "프로세스 전체 틱 증분: %d → OS 실측 CPU 점유율 %.2f%%\n", d, (d/hz)/e*100}'

echo
echo "=== [6b] 자발적/비자발적 컨텍스트 스위치 (duty-cycle 판별 근거) ==="
printf '%-8s %-20s %-12s %-14s %s\n' TID COMM voluntary nonvoluntary wchan
for t in /proc/$PID/task/*; do
  tid=$(basename "$t")
  v=$(awk '/^voluntary_ctxt_switches/{print $2}' "$t/status" 2>/dev/null)
  nv=$(awk '/^nonvoluntary_ctxt_switches/{print $2}' "$t/status" 2>/dev/null)
  printf '%-8s %-20s %-12s %-14s %s\n' "$tid" "$(cat "$t/comm" 2>/dev/null)" "${v:-?}" "${nv:-?}" "$(cat "$t/wchan" 2>/dev/null)"
done
echo "→ 자발적 스위치가 압도적으로 많으면 '일정 주기마다 스스로 잠드는 duty-cycle' 방식이다."

echo
echo "=== [6c] 워커 스레드가 실제로 무엇을 하는가 (syscall 샘플링, 0.2초 x 10회) ==="
# /proc/<pid>/task/<tid>/syscall 은 root 만 읽을 수 있다. strace 가 없는 환경에서
# 'CPU 를 쓰는 중인지 / 잠자는 중인지'를 판별하는 대체 관측이다.
for t in /proc/$PID/task/*; do
  tid=$(basename "$t"); [[ "$tid" == "$PID" ]] && continue
  echo "--- TID $tid ($(cat "$t/comm")) ---"
  for _ in $(seq 1 10); do
    awk '{print "  syscall_nr="$1}' "$t/syscall" 2>/dev/null || echo "  (읽기 불가)"
    sleep 0.2
  done
done
echo "→ x86-64 syscall 번호: 270=pselect6(타임아웃 대기), 23=select, 35=nanosleep, 202=futex, 0=read, 1=write"

echo
echo "=== [7] 앱이 스스로 보고한 CPU 점유율 (같은 구간 로그) ==="
grep -E 'CpuWorker|Threshold' "$APPLOG" | tail -8

echo
echo "=== [8] cgroup cpu.stat 재측정 (throttling 발생 여부) ==="
[[ -f $CG/cpu.stat ]] && cat "$CG/cpu.stat"

echo
echo "=== [9] 대조군: 순수 CPU 루프 1개 (외부 기준) ==="
# timeout 을 앞에 두면 $! 가 timeout 의 PID 가 되어 측정이 0 이 나온다(실측으로 확인) → 서브셸 자체를 측정
( i=0; while :; do i=$((i+1)); done ) &
REF=$!
R0=$(awk '{print $14+$15}' /proc/$REF/stat 2>/dev/null || echo 0)
sleep "$DUR"; R1=$(awk '{print $14+$15}' /proc/$REF/stat 2>/dev/null || echo 0)
kill "$REF" 2>/dev/null; wait "$REF" 2>/dev/null
awk -v d="$((R1-R0))" -v hz="$HZ" -v e="$DUR" 'BEGIN{printf "대조군(싱글 스레드 busy loop) CPU 점유율: %.2f%%\n", (d/hz)/e*100}'

echo
echo "=== [10] 정리 ==="
kill -TERM "$PID" 2>/dev/null; sleep 1; kill -KILL "$PID" 2>/dev/null
echo "앱 종료. 원본 저장: $OUT"
echo "== SCHEDULING PROBE DONE =="
