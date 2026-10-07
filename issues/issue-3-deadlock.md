# [Bug] Deadlock — 두 워커의 교차 자원 요청 후 진행 정지

## 1. Description (현상 설명)

2026-10-07 21:29:39 KST, `b1-lab`에서 MEMORY_LIMIT=512, CPU_MAX_OCCUPY=50,
MULTI_THREAD_ENABLE=true로 실행했다. 워커 PID 11287은 살아 있으나
21:29:48 이후 두 스레드의 WAITING/BLOCKED 로그에서 진행이 멈췄다.

## 2. Evidence & Logs (증거 자료)

- [앱 로그](../evidence/deadlock/app_before.log): Worker-Thread-1은 Socket_Pool_B,
  Worker-Thread-2는 Shared_Memory_A를 요청하며 BLOCKED.
- [ps -L / top 표본](../evidence/deadlock/process-samples_before.txt): 워커 PID와
  futex 대기 스레드가 존재. 워커 RSS는 관제에서 18,548–18,628 KB로 거의 고정.
- [관제 로그](../evidence/deadlock/monitor_before.log): 48개 표본, 초기 부트 이후 진행 정체.
- [스택](../evidence/deadlock/stacktrace_before.txt): 총 4스레드, futex 대기 3개와 wait4 대기 1개.
  gdb 사용자 영역 스택에서 `PyThread_acquire_lock_timed` 확인.

## 3. Root Cause Analysis (원인 분석)

앱 로그가 서로 다른 순서로 두 자원을 요청하는 패턴을 보이고,
락 대기 스택·PID 생존·로그 및 메모리 진행 정체가 함께 관측된다.
상호 배제, 점유 대기, 비선점, 순환 대기라는 교착상태 조건에 부합하는 정황이다.
futex 대기 자체만으로 교착상태를 확정하지 않으며, 이번 판정은 로그와 함께 내린다.
자원 소유 관계는 앱의 LOCK ACQUIRED 기록으로 확인하고, 실제 락 대기는 사용자 영역 스택으로
확인한다. Thread-1의 A→B와 Thread-2의 B→A를 연결하면 순환 대기 고리가 완성된다.

## 4. Workaround & Verification (조치 및 검증)

MULTI_THREAD_ENABLE만 true → false로 바꾸고 나머지 변수는 유지했다.

| 지표 | Before | After |
|---|---|---|
| 결과 | 관측 중 진행 정지, 스택 수집 후 강제 종료 | 170초 생존, 로그 계속 진행 |
| 관제 표본 수 | 48 | 89 |
| RSS 범위 | 18,548–18,628 KB | 18,464–530,840 KB |

변경 후 [메타데이터](../evidence/deadlock/metadata_after.txt), [앱 로그](../evidence/deadlock/app_after.log),
[관제](../evidence/deadlock/monitor_after.log). 동시성 해제는 회피 조치이며 기능을 축소한다.
근본 해결에는 전역 락 획득 순서 통일이나 타임아웃·보유 락 해제 정책이 필요하다.
