# 평가문항별 답변과 제시할 증거

평가 원본은 [rubric.png](rubric.png)이다. 아래 “답변”은 구두 설명 예시이며,
“제시”는 평가 중 열어 볼 원본 파일과 확인 지점을 뜻한다.
실험 일시: 2026-10-07 KST, OrbStack `b1-lab`, Ubuntu 24.04.5 amd64.

## 항목 1 — 산출물·재현·증거 (8문항)

### 1-1. [OOM] 메모리 선형 증가 후 강제 종료 패턴이 기록되어 있는가?

**답변:** “네. 워커 PID 7689의 RSS가 계단식으로 증가했습니다. 2초 간격 관제에서
18,376 KB로 시작해 274,416 KB까지 증가했고, 21:23:01에 NOT_FOUND로 바뀌었습니다.
앱은 Heap 275MB가 MEMORY_LIMIT=256MB를 넘었다고 기록하며 스스로 종료했습니다.
이는 커널 OOM kill이 아니라 앱의 MemoryGuard 종료입니다. ‘선형 증가’는
일정 간격의 할당을 표본화한 계단형 추세로 설명합니다.”

**제시:** [관제 before](../evidence/oom/monitor_before.log)의 첫 표본·중간 증가·마지막 NOT_FOUND →
[앱 before](../evidence/oom/app_before.log)의 `Current Heap`, `Memory limit exceeded`,
`Self-terminating process 7689` → [ps/top](../evidence/oom/process-samples_before.txt).

**판단 포인트:** RSS의 상승, 같은 PID, 종료 메시지와 관제 시각을 연결할 수 있다.

### 1-2. [OOM] MEMORY_LIMIT 조정 후 생존 시간이 늘어난 비교가 있는가?

**답변:** “네. MEMORY_LIMIT만 256에서 512로 바꿨고 CPU_MAX_OCCUPY=50,
MULTI_THREAD_ENABLE=false는 고정했습니다. before는 21:22:28에 시작해 21:23:01에
종료했고 after는 170초 관측을 마칠 때까지 생존했습니다. after도 메모리 증가와
cleanup이 있으므로 누수가 근본 해결됐다고 주장하지 않습니다.”

**제시:** [before 메타데이터](../evidence/oom/metadata_before.txt)와
[after 메타데이터](../evidence/oom/metadata_after.txt)의 세 변수·result →
[after 앱 로그](../evidence/oom/app_after.log) → [OOM 보고서 비교표](../issues/issue-1-oom.md).

**판단 포인트:** 변수 하나만 바뀌었고, 관측 창의 차이를 설명한다.

### 1-3. [CPU] CPU 임계치 초과 후 프로세스 종료 패턴이 있는가?

**답변:** “네. 추가 20ms 측정에서 워커 PID 17645가 부트 후 98.809%의 짧은 CPU 피크를
보였습니다. CPU_MAX_OCCUPY=100에서는 약27초 뒤 내부 Load 임계값 위반으로 종료했습니다.
strace로 별도 재현한 워커 PID17834가 자기 PID에 SIGTERM을 발송한 것과 종료코드143을
확인했습니다. 최초 ps 관제의 3.0%는 수명 평균이라 짧은 피크를 놓쳤습니다.
실제 CPU 피크와 앱의 내부 Load는 각각의 지표로 제시하며 동일한 수치로 바꾸어 말하지 않습니다.”

**제시:** [CPU 앱 before](../evidence/cpu/app_before.log)의 마지막 Current Load와 CRITICAL →
[CPU 관제 before](../evidence/cpu/monitor_before.log) →
[ps/top 표본](../evidence/cpu/process-samples_before.txt) → [추가 실증을 반영한 CPU 보고서](../issues/issue-2-cpu.md).

추가로 [CPU CSV](../evidence/cpu-resolution/cpu_before.csv),
[요약](../evidence/cpu-resolution/summary_before.json),
[SIGTERM 원본](../evidence/policy-scheduling/signals.17834)을 제시한다.
**판단 포인트:** 프로세스의 급상승, 정책 메시지, 신호의 발신·수신 주체를 각각 확인한다.

### 1-4. [CPU] CPU_MAX_OCCUPY 조정 후 종료/생존 변화 비교가 있는가?

**답변:** “네. MEMORY_LIMIT=512, MULTI_THREAD_ENABLE=false를 유지하고
CPU_MAX_OCCUPY만 100에서 50으로 변경했습니다. before는 정책 종료,
after는 170초 생존입니다. 설정 변경으로 앱의 종료를 회피했지만 OS CPU 과점유를
제어한 실험이라고 해석하지 않습니다.”

**제시:** [before metadata](../evidence/cpu/metadata_before.txt),
[after metadata](../evidence/cpu/metadata_after.txt),
[after 앱 로그](../evidence/cpu/app_after.log), [비교표](../issues/issue-2-cpu.md).

추가 실험의 [100 요약](../evidence/cpu-resolution/summary_before.json)과
[50 요약](../evidence/cpu-resolution/summary_after.json)도 비교한다.
원본 바이너리 SHA-256이 같고 나머지 두 변수는 고정돼 있다.

### 1-5. [Deadlock] PID는 존재하지만 CPU/MEM·로그가 정체된 상태를 식별했는가?

**답변:** “네. 워커 PID 11287이 존재하고 ps -L에서 락 대기 스레드가 보이지만,
앱 로그는 21:29:48의 WAITING/BLOCKED에서 멈췄습니다. RSS는 관측 중
18,548–18,628 KB로 거의 고정됐습니다. 부트 직후 표본과 이후 정체 구간을 구분했습니다.
프로세스 존재와 포트 열림만으로 정상 서비스라고 판단하지 않았습니다.”

**제시:** [Deadlock 앱 마지막 로그](../evidence/deadlock/app_before.log) →
[ps -L 표본](../evidence/deadlock/process-samples_before.txt)의 PID 11287·futex_wait →
[관제 시계열](../evidence/deadlock/monitor_before.log) →
[스택](../evidence/deadlock/stacktrace_before.txt)의 total_threads=4, futex_wait_threads=3.

### 1-6. [Deadlock] MULTI_THREAD_ENABLE 조정 후 재현/회피 비교가 있는가?

**답변:** “네. true에서는 진행이 멈춰 스택을 수집하고 강제 종료했습니다.
false에서는 나머지 두 변수를 그대로 유지한 채 170초 생존했고 로그가 계속 진행했습니다.
동시성을 끈 회피 조치이며 락 구현을 고친 근본 해결은 아닙니다.”

**제시:** [before metadata](../evidence/deadlock/metadata_before.txt),
[after metadata](../evidence/deadlock/metadata_after.txt),
[after 앱 로그](../evidence/deadlock/app_after.log), [Deadlock 보고서](../issues/issue-3-deadlock.md).

### 1-7. [Format] 리포트 3건에 현상→증거→원인→조치 구조가 있는가?

**답변:** “네. 세 보고서 모두 Description, Evidence & Logs, Root Cause Analysis,
Workaround & Verification의 네 절을 갖추었습니다. 관측한 현상과 제안하는 해결을 구분했습니다.”

**제시:** [OOM](../issues/issue-1-oom.md), [CPU](../issues/issue-2-cpu.md),
[Deadlock](../issues/issue-3-deadlock.md)의 제목 및 1–4절.
이는 GitHub Issue **형식의 마크다운 보고서**다. 이번 작업에서 원격 GitHub Issue를 새로 등록한 것은 아니다.

### 1-8. [Evidence] PID·타임스탬프·핵심 로그 메시지가 첨부되어 있는가?

**답변:** “네. 보고서에서 원본 파일로 연결하며, metadata에는 실행 시각·계정·부모/워커 PID,
app에는 시각과 원인 메시지, monitor에는 시각·PID·CPU/MEM/RSS/VSZ가 있습니다.
스크린샷 대신 추적 가능한 로그 원문을 제시하고 SHA-256으로 무결성도 확인합니다.”

**제시:** [manifest](../evidence/manifest.json), 각 metadata/app/monitor 파일,
`python3 scripts/check-evidence.py` 실행 결과. 자동검사는 실제 공식 평가 판정을 대신하지 않는다.

## 항목 2 — 도구 선택과 데이터 추출 (3문항)

### 2-1. monitor.sh에서 메모리 추적에 사용한 명령과 추출 방법은?

**답변:** “2초마다 ps aux에서 앱 이름을 찾고 `sort -k6 -rn`으로 RSS 열(6번째)을
내림차순 정렬한 뒤 첫 행의 PID(2번째)를 awk로 추출했습니다.
이어 `ps -p "$pid" -o %cpu,%mem,rss,vsz --no-headers`로 수치를 기록합니다.
RSS와 VSZ의 단위는 KB, %MEM은 호스트 메모리 대비 비율입니다.
부모는 작은 감독 프로세스이므로 실제 메모리를 쓰는 워커를 관측하려 RSS가 큰 PID를 골랐습니다.”

**제시:** [monitor.sh](../scripts/monitor.sh)의 pid/stats/ts/sleep 줄,
[OOM 관제](../evidence/oom/monitor_before.log), [OOM metadata](../evidence/oom/metadata_before.txt).

**추가 질문 답변:** “이 방식은 이름 기반 검색·RSS 최대 선택이므로 오탐이나 PID 교체 가능성이 있습니다.
운영에서는 서비스 cgroup/프로세스 트리와 PID 시작 시각으로 대상을 고정해야 합니다.”

### 2-2. CPU 확인 도구와 옵션의 의미는?

**답변:** “ps는 `-p`로 워커 PID를 고르고 `-o`로 출력 필드를 정했습니다. `%cpu`는
프로세스 수명 평균이라 순간 사용률과 다릅니다. `ps -L -p PID`는 스레드별 상태와
wchan을 확인합니다. `top -b -n 1`은 비대화형 한 번의 스냅샷을 파일로 남깁니다.
첫 top 표본만으로 순간 과점유를 확정하지 않았습니다. 보너스에서는
/proc/PID/stat의 utime+stime을 두 시점에서 읽고 틱 증분/USER_HZ/경과시간으로
CPU 사용률을 계산해 ps 평균값과 구별했습니다.”

추가로 “20ms /proc 측정은 actual interval을 사용하고 PID의 starttime도 함께 확인합니다.
USER_HZ=100의 양자화가 있어 한 표본을 지속 CPU 포화로 해석하지 않습니다.
최초 ps 측정이 낮게 보이던 이유를 이 고해상도 원본과 비교해 설명할 수 있습니다.”

**제시:** [시나리오 sample_ps](../scripts/20-run-scenario.sh),
[CPU process-samples](../evidence/cpu/process-samples_before.txt),
[보너스 측정 코드](../scripts/40-scheduling-probe.sh)와 [원본 측정 §6](../evidence/40-scheduling-probe.txt).
[고해상도 수집기](../scripts/cpu-resolution-probe.py), [CPU before CSV](../evidence/cpu-resolution/cpu_before.csv).

### 2-3. 살아 있지만 멈춘 프로세스를 어떤 순서로 진단했는가?

**답변:** “① metadata와 ps로 실제 워커 PID를 확인했습니다.
② app 로그의 마지막 시각과 메시지를 확인했습니다.
③ 여러 시점의 ps/top/관제를 비교해 CPU·RSS·로그 진행이 정체됐는지 봤습니다.
④ ps -L/wchan으로 스레드 대기를 확인했습니다.
⑤ 종료하기 전에 스택을 수집해 gdb의 PyThread_acquire_lock_timed와 futex 대기를 확인했습니다.
⑥ 자원 교차 요청 로그와 대기 상태를 함께 해석했습니다.
⑦ true/false 비교 후 정리했습니다.”

**제시:** [시나리오 실행 순서](../scripts/20-run-scenario.sh),
[스택 수집기](../scripts/capture-stacktrace.sh), [Deadlock 원본 스택](../evidence/deadlock/stacktrace_before.txt).
futex 대기만으로 모든 프로세스를 Deadlock이라 판단하지 않는다.

## 항목 3 — OS 원리와 원인 추론 (4문항)

### 3-1. 메모리 보호 정책이 누수 프로세스를 종료하는 이유는?

**답변:** “계속 증가하는 메모리가 제한 없이 쌓이면 호스트의 가용 메모리를 소진하고
다른 서비스에도 영향을 줄 수 있습니다. 앱은 설정 상한에서 종료해 피해를 제한합니다.
이번에는 Heap 275MB ≥ 256MB라는 MemoryGuard 로그가 직접 증거이며,
커널 전체 메모리 부족에 의한 OOM killer와 구분합니다. 운영에서는 종료 전 경보와
제한된 재시작 정책이 필요하고, 누수 자체를 수정해야 합니다.”

**제시:** [OOM 종료 메시지](../evidence/oom/app_before.log), [OOM 보고서 원인 분석](../issues/issue-1-oom.md).

### 3-2. CPU 과점유 프로세스를 종료하는 것이 시스템 보호에 필요한 이유는?

**답변:** “실제 과점유는 다른 작업에 할당될 CPU 시간을 줄이고 응답 지연과 처리량 저하를
일으킬 수 있어 문제가 있는 작업을 격리하거나 제한·종료할 수 있습니다.
다만 바로 종료하기 전에 cgroup 쿼터, 작업 제한, 요청 차단 등 피해가 작은 방법도 검토해야 합니다.
이번 바이너리에서는 짧은 워커 CPU 급상승과 CpuWorker 정책에 의한 자기 SIGTERM을
각각 확인했습니다. 내부 Load를 기준으로 판단하는 앱 정책과 OS의 하드 CPU 쿼터를 구분합니다.”

**제시:** [CPU 원본 앱/OS 비교](../issues/issue-2-cpu.md).
이 답변의 운영 대응은 **제안**이며 CPU 쿼터를 적용한 실측이 아니다.

### 3-3. Deadlock을 상호 배제와 순환 대기로 설명할 수 있는가?

**답변:** “한 자원을 동시에 한 스레드만 잡을 수 있어 상호 배제가 생깁니다.
Thread-1이 A를 보유하고 B를 기다리고, Thread-2가 B를 보유하고 A를 기다리면
T1→B→T2→A→T1의 순환이 됩니다. 보유한 자원을 놓지 않는 점유 대기와
강제로 빼앗지 않는 비선점까지 함께 성립하면 진행이 멈출 수 있습니다.
이번 로그는 A=Shared_Memory_A, B=Socket_Pool_B입니다.”

**제시:** [Deadlock 앱 로그](../evidence/deadlock/app_before.log)의 LOCK ACQUIRED와 WAITING 쌍,
[스택](../evidence/deadlock/stacktrace_before.txt).

### 3-4. 로그에서 A→B, B→A 관계를 어떻게 추적했는가?

**답변:** “스레드 이름으로 로그를 묶었습니다. 21:29:46.699에 Thread-1이 A를,
Thread-2가 B를 획득했습니다. 21:29:48.710에는 Thread-1이 B를 기다리고
Thread-2가 A를 기다린다고 기록했습니다. 이후 진행 로그가 없고 스택에 락 대기가 있어
T1→B→T2→A→T1의 순환 의존을 연결했습니다. 자원 보유는LOCK ACQUIRED로그로,
실제 대기는gdb/futex스택으로 각각 확인했습니다.”

**제시:** [앱 before](../evidence/deadlock/app_before.log)의 4개 획득·대기 메시지를 한 화면에 표시.
`bash eval/show-evidence.sh deadlock`으로 시각·스레드·자원을 함께 보여 준다.

## 항목 4 — 운영 판단·개선·회고 (5문항)

### 4-1. 운영에서 누수를 장애 전에 탐지하도록 monitor.sh를 어떻게 개선할 것인가?

**답변:** “현재 도구는 2초마다 수치를 기록하다 프로세스가 없으면 종료할 뿐,
RSS 증가율이나 상한 접근 경보가 없습니다. 운영에서는 워커의 시작 시각과 cgroup으로
대상을 고정하고, 이동 시간창의 RSS 기울기와 한도 대비 비율을 함께 보겠습니다.
예를 들어 한도 80% 초과가 지속되거나 RSS가 계속 증가하면 경보를 내되,
정상 캐시 증가·cleanup 패턴을 고려해 지속 시간과 회복 여부도 판단하겠습니다.
로그는 타임스탬프·PID·starttime·상한·RSS·증가율을 구조화하고 관제 저장 실패도 경보하겠습니다.”

**제시:** [현재 monitor.sh](../scripts/monitor.sh),
[OOM before 증가](../evidence/oom/monitor_before.log), [after 회복 패턴](../evidence/oom/app_after.log).
80%는 개선 예시이며 이번 실험에서 적용한 경보 설정이 아니다.

### 4-2. 세 장애 중 가장 치명적인 것은 무엇이며 근본 예방은?

**답변:** “이 서비스가 요청 처리 서버라는 전제에서는 Deadlock을 가장 위험하게 봅니다.
PID와 포트가 살아 있어 단순 생존 감시는 정상으로 판단할 수 있는데 처리 진행은 멈추기 때문입니다.
전역 락 순서를 통일하고, 락 범위를 줄이며, 타임아웃 시 보유 락을 해제하도록 설계하겠습니다.
실제 요청 응답과 진행 카운터 기반 감시도 추가하겠습니다. 다만 공유 호스트 전체를 고갈시키는
누수라면 OOM의 영향 범위가 더 커 우선순위가 달라집니다.”

**제시:** [Deadlock PID 생존/정체](../evidence/deadlock/process-samples_before.txt),
[BLOCKED 로그](../evidence/deadlock/app_before.log).
서비스 요청 지연은 이번 실험에서 측정하지 않았으므로 일반 운영 가정임을 명시한다.

### 4-3. 같은 서버에서 OOM과 Deadlock이 동시에 발생하면 어떤 순서로 대응할 것인가?

**답변:** “① 호스트 가용 메모리·swap·서비스 영향부터 확인합니다.
② 메모리 고갈이 임박하면 문제 서비스의 트래픽을 빼고 격리·제한하는 등 확산을 먼저 막습니다.
③ 안전한 여유가 있으면 종료 전에 PID·시각·RSS·앱 로그·Deadlock 스택을 빠르게 수집합니다.
④ 영향이 큰 프로세스를 통제된 방식으로 정리하고 재시작·대체 인스턴스로 복구합니다.
⑤ OOM 원인과 락 순환을 따로 분석해 고칩니다. 동시에 발생했다는 이유만으로
하나가 다른 하나의 원인이라고 단정하지 않습니다. 스택 수집이 장애 확산 방지를 지연하면
최소 증거만 확보하고 복구를 우선하겠습니다.”

**제시:** [OOM metadata](../evidence/oom/metadata_before.txt),
[Deadlock 스택](../evidence/deadlock/stacktrace_before.txt), [수집기](../scripts/capture-stacktrace.sh).
두 장애를 동시에 발생시킨 실험은 하지 않았으며 이 답변은 대응 절차 제안이다.

### 4-4. 소스를 수정할 수 있다면 장애별 어떤 개선을 할 것인가?

**답변:** “OOM은 할당·해제 경로를 힙 프로파일러로 추적하고 자원 수명·캐시 상한·eviction을
명시하겠습니다. CPU는 내부 Load 계수와 실제 CPU 측정 단위를 확인하고,
무한 반복·과도한 polling을 제거하며 작업량·재시도·동시성을 제한하겠습니다.
Deadlock은 모든 경로에서 A→B 락 순서를 통일하거나 한 번에 안전하게 획득하는 구조를 쓰고,
타임아웃·예외 시 락 해제와 동시성 테스트를 추가하겠습니다.
단순히 MEMORY_LIMIT을 높이거나 스레드를 끄는 조치와 코드 수준 해결을 구분하겠습니다.”

**제시:** [OOM](../issues/issue-1-oom.md), [CPU](../issues/issue-2-cpu.md),
[Deadlock](../issues/issue-3-deadlock.md)의 원인·조치 절.
바이너리 내부 소스를 분석하거나 해당 개선을 구현한 것은 아니다.

### 4-5. 처음부터 다시 한다면 무엇을 다르게 할 것인가?

**답변:** “시작부터 워커 PID와 starttime을 고정하고 모든 실험에 metadata를 먼저 남기겠습니다.
CPU는 앱 Load와 OS 사용률을 동시에 측정하고 짧은 간격의 /proc 델타 표본을
before/after 양쪽에 넣겠습니다. Deadlock은 종료 전에 로그·wchan·gdb 스택을 수집하겠습니다.
실험별 새 출력 폴더와 종료코드 검증을 사용해 오래된 증거가 섞이지 않게 하겠습니다.
마지막으로 ‘실측’, ‘근거에 따른 추론’, ‘개선 제안’을 처음부터 별도 표시하겠습니다.”

**제시:** [metadata 예시](../evidence/cpu/metadata_before.txt),
[manifest](../evidence/manifest.json), [재현 및 측정 해석](../docs/reproduction.md),
[검증기](../scripts/check-evidence.py).
현재도 이름·RSS 기반 PID 검색이 남아 있어 PID 추적 개선은 향후 과제다.

## 항목 5 — 보너스 크레딧 (1문항)

### 5-1. 보너스 문제 해결에 따른 크레딧을 부여할 수 있는가?

**답변:** “추가 측정까지 수행하고 Priority 계열의 우선순위 가중 공정 배분으로 추론했습니다.
앱이 nice=10을 설정하는 시스템콜, 실제 SCHED_OTHER 정책, 45초 커널 스레드 전환을
확보했습니다. 같은 CPU의 nice0/10 포화 대조군은90.24%/9.67%로 CPU 몫이 달랐습니다.
정상 앱의 Memory/CpuWorker 로그는 서로 끼어들며 평균3.0549/3.1204초 주기로 진행합니다.
FCFS처럼 완료 순서만으로 실행되지 않고 SCHED_RR도 아닙니다.
실제 Linux 정책과 추상 분류를 함께 설명합니다. 크레딧 판정은 평가자가 합니다.”

**제시:** [보너스 보고서](../issues/bonus-scheduling.md),
[원본 측정](../evidence/40-scheduling-probe.txt)의 §4·§6·§6b·§6c·§7·§9.

추가로 [정상 앱 로그](../evidence/policy-scheduling/normal-app.log),
[주기 계산](../evidence/policy-scheduling/log-pattern.json),
[커널 trace](../evidence/policy-scheduling/sched-trace.txt),
[정책 정보](../evidence/policy-scheduling/policies.txt),
[우선순위 대조](../evidence/policy-scheduling/priority-control.json)를 제시한다.
**판단 포인트:** 대조군을 앱 측정으로 오인하지 않고, nice 기반 가중 배분이라는 추론을 검증한다.
