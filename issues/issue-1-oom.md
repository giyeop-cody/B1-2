# [Bug] OOM Crash — MEMORY_LIMIT=256에서 MemoryGuard 자기 종료

## 1. Description (현상 설명)

2026-10-07 21:22:28 KST, OrbStack `b1-lab`의 `agent-admin`으로 실행했다.
MEMORY_LIMIT=256, CPU_MAX_OCCUPY=50, MULTI_THREAD_ENABLE=false에서 정상 부트 후
메모리 증가가 관측되고 21:23:01에 종료했다. 관측 워커는 PID 7689다.

## 2. Evidence & Logs (증거 자료)

- [메타데이터](../evidence/oom/metadata_before.txt): 조건·실행 계정·워커 PID·TERMINATED.
- [프로세스 관제](../evidence/oom/monitor_before.log): RSS 18,376 → 274,416 KB,
  표본 16개, 마지막 STATUS:NOT_FOUND.
- [앱 로그](../evidence/oom/app_before.log): Heap 275MB, `Memory limit exceeded (275MB >= 256MB)` 및
  `Self-terminating process 7689`.
- [ps/top 표본](../evidence/oom/process-samples_before.txt): 워커 RSS 및 호스트 메모리 상태.

## 3. Root Cause Analysis (원인 분석)

앱의 MemoryWorker가 힙을 증가시키고, 내부 MemoryGuard가 설정 상한 초과를 판단해
프로세스를 스스로 종료했다. 관제 RSS도 증가하므로 앱 로그의 증가가 물리 메모리에 반영된다.
RSS는 실제 상주 페이지, VSZ는 가상 주소 공간 크기다. 이번 종료를 커널 OOM killer로
판정하지 않는다. 직접 근거는 앱이 남긴 자기 종료 메시지다.
바이너리 소스의 할당·해제 위치는 확인하지 않았으므로 누수 코드 지점까지 특정하지 않는다.

## 4. Workaround & Verification (조치 및 검증)

MEMORY_LIMIT만 256 → 512로 바꿨다. CPU_MAX_OCCUPY=50, MULTI_THREAD_ENABLE=false는 유지했다.

| 지표 | Before | After |
|---|---|---|
| 결과 | 자기 종료 | 170초 생존 후 관측 종료를 위해 강제 정리 |
| RSS 최대 | 274,416 KB | 530,872 KB |
| 관제 표본 | 16개 | 89개 |

변경 후 [메타데이터](../evidence/oom/metadata_after.txt), [앱 로그](../evidence/oom/app_after.log),
[관제](../evidence/oom/monitor_after.log)를 비교한다. 상한 변경은 조기 종료 회피 조치다.
증가 패턴 자체는 지속되므로 근본 해결에는 할당·해제 추적과 캐시 상한 검토가 필요하다.
