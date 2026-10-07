# [Bug] CPU Latency — 내부 Load 임계값 위반으로 종료, OS 과점유는 미관측

## 1. Description (현상 설명)

2026-10-07 21:26:07 KST, OrbStack `b1-lab`에서 MEMORY_LIMIT=512,
CPU_MAX_OCCUPY=100, MULTI_THREAD_ENABLE=false로 실행했다.
앱 내부 Load가 상승하다 21:26:34에 54.76% 임계값 위반 로그를 남기고 종료했다.

## 2. Evidence & Logs (증거 자료)

- [실행 조건](../evidence/cpu/metadata_before.txt)과 [앱 종료 로그](../evidence/cpu/app_before.log).
- [관제](../evidence/cpu/monitor_before.log): 13개 표본에서 프로세스 CPU 최대 3.0%,
  RSS 18,596–18,660 KB. CPU 값은 ps의 프로세스 수명 평균이다.
- [ps/top 표본](../evidence/cpu/process-samples_before.txt): 워커와 호스트의 CPU 상태.
- [별도 정상 설정 보너스 측정](../evidence/40-scheduling-probe.txt): 12초 동안
  /proc CPU 시간 증분으로 OS CPU 2.33% 측정. 이는 CPU-before와 다른 실행이다.

## 3. Root Cause Analysis (원인 분석)

직접 종료 원인은 앱 CpuWorker의 `CPU Threshold Violated! (54.760000000000005%)`이다.
CPU_MAX_OCCUPY는 앱 내부 동작에 영향을 주며 OS CPU 쿼터 설정은 아니다.
내부 Load 54.76%를 실제 프로세스 CPU 사용률 54.76%로 해석할 수 없다.
미션은 CPU 과점유·Watchdog/SIGTERM 예시를 제시하지만, 이번 로그에서는
CpuWorker 정책 종료를 확인했으며 **OS 과점유 또는 시스템 지연은 입증하지 못했다**.
ps의 수명 평균 표본만으로 짧은 순간의 스파이크가 전혀 없었다고 단정하지도 않는다.

## 4. Workaround & Verification (조치 및 검증)

CPU_MAX_OCCUPY만 100 → 50으로 바꾸고 나머지 두 변수는 유지했다.

| 지표 | Before | After |
|---|---|---|
| 결과 | 내부 임계값 위반 종료 | 170초 생존 후 관측 종료를 위해 정리 |
| 관제 표본 수 | 13 | 89 |
| 관제 ps CPU 최대 | 3.0% | 5.2% |

변경 후 [메타데이터](../evidence/cpu/metadata_after.txt), [앱 로그](../evidence/cpu/app_after.log),
[관제](../evidence/cpu/monitor_after.log). after의 OS 표본 최대가 더 크다는 사실도
앱 내부 Load와 OS CPU가 별개임을 보여준다. 임계값·단위·종료 정책은 바이너리 구현 확인이 필요하다.
