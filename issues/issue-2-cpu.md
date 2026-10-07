# [Bug] CPU Latency — 짧은 워커 CPU 급상승과 보호 정책 SIGTERM 종료

## 1. Description (현상 설명)

2026-10-07 21:26:07 KST, OrbStack `b1-lab`에서 MEMORY_LIMIT=512,
CPU_MAX_OCCUPY=100, MULTI_THREAD_ENABLE=false로 실행했다.
앱 내부 Load가 상승하다 21:26:34에 54.76% 임계값 위반 로그를 남기고 종료했다.

## 2. Evidence & Logs (증거 자료)

### 추가 실증: 수명 평균이 놓친 짧은 CPU 급상승

2026-10-07 23:02에 제공 바이너리를 수정하지 않고 20ms 목표 간격으로 `/proc/PID/stat`의
utime+stime을 측정했다. PID 17645에서 부트 완료 뒤 8.4292초에 **98.809%**,
종료 직전 27.149초에 **98.178%**가 기록됐다. CPU 계산은
`100 × 틱 증분 / USER_HZ / 실제 측정 간격`이며 USER_HZ=100이다.
이 값은 한 코어 기준 짧은 구간 사용률이고 10ms CPU 틱의 양자화 영향을 받는다.
지속적인 호스트 포화와는 구별한다.

- [before CPU 원본 CSV](../evidence/cpu-resolution/cpu_before.csv)
- [after CPU 원본 CSV](../evidence/cpu-resolution/cpu_after.csv)
- [before 실행 요약](../evidence/cpu-resolution/summary_before.json): 약 27.25초 후 종료.
- [after 실행 요약](../evidence/cpu-resolution/summary_after.json): 170초 관측 동안 생존.
- [정책 로그](../evidence/policy-scheduling/cpu-policy-before.log): 23:07:01.396에 내부 Load 51.62%,
  곧이어 `CPU Threshold Violated!`.
- [워커 신호 추적](../evidence/policy-scheduling/signals.17834):
  23:07:01.498338 `kill(17834, SIGTERM) = 0`, 발신 PID=17834/UID=1000,
  워커 자신이 보낸 SIGTERM으로 종료. [종료 코드](../evidence/policy-scheduling/termination.json)는 143.

### 최초 2초 관제 및 ps/top 표본

- [실행 조건](../evidence/cpu/metadata_before.txt)과 [앱 종료 로그](../evidence/cpu/app_before.log).
- [관제](../evidence/cpu/monitor_before.log): 13개 표본에서 프로세스 CPU 최대 3.0%,
  RSS 18,596–18,660 KB. CPU 값은 ps의 프로세스 수명 평균이다.
- [ps/top 표본](../evidence/cpu/process-samples_before.txt): 워커와 호스트의 CPU 상태.
- [별도 정상 설정 보너스 측정](../evidence/40-scheduling-probe.txt): 12초 동안
  /proc CPU 시간 증분으로 OS CPU 2.33% 측정. 이는 CPU-before와 다른 실행이다.

## 3. Root Cause Analysis (원인 분석)

직접 종료 원인은 앱 CpuWorker의 임계값 위반이다. 최초 실험에서는 내부 Load 54.76%,
추가 고해상도 실험에서는 52.74%, strace 실험에서는 51.62%에서 정책 종료를 재현했다.
CPU_MAX_OCCUPY는 앱 내부 동작에 영향을 주며 OS CPU 쿼터 설정은 아니다.
프로세스의 짧은 CPU 급상승은 /proc 원본으로, 보호 정책에 의한 자기 SIGTERM은
앱 로그와 시스템콜 추적으로 각각 확인했다. 내부 Load와 OS CPU 사용률의 단위는 구별해야 한다.
CPU_MAX_OCCUPY=50에서도 순간 CPU가 50%를 넘을 수 있으므로 이 설정을 커널의 하드 CPU 제한으로
해석하지 않는다. 미션의 Watchdog에 해당하는 보호 기능이 이 바이너리에서는 CpuWorker라는 이름으로
기록되고 실제로 SIGTERM을 발송한다.

## 4. Workaround & Verification (조치 및 검증)

CPU_MAX_OCCUPY만 100 → 50으로 바꾸고 나머지 두 변수는 유지했다.

| 지표 | Before | After |
|---|---|---|
| 결과 | 내부 임계값 위반 종료 | 170초 생존 후 관측 종료를 위해 정리 |
| 관제 표본 수 | 13 | 89 |
| 관제 ps CPU 최대 | 3.0% | 5.2% |

추가 실행의 단일 변수 비교도 [before](../evidence/cpu-resolution/summary_before.json)/
[after](../evidence/cpu-resolution/summary_after.json)에 남겼다. MEMORY_LIMIT=512와
MULTI_THREAD_ENABLE=false는 고정했고 CPU_MAX_OCCUPY만 100 → 50으로 바꿨다.
before는 정책 종료, after는 170초 생존 후 측정 종료를 위해 SIGTERM으로 정리했다.
after 요약의 종료 코드는 이 **실험 정리 신호**이며 정책 실패로 해석하지 않는다.

변경 후 [메타데이터](../evidence/cpu/metadata_after.txt), [앱 로그](../evidence/cpu/app_after.log),
[관제](../evidence/cpu/monitor_after.log). after의 OS 표본 최대가 더 크다는 사실도
앱 내부 Load와 OS CPU가 별개임을 보여준다. 임계값·단위·종료 정책은 바이너리 구현 확인이 필요하다.
