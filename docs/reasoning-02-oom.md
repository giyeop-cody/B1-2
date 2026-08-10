# 추론 기록 #02: OOM (Memory Leak) 분석

## 가설
agent-leak-app이 메모리를 해제하지 않고 지속 할당 → MEMORY_LIMIT 도달 시 MemoryGuard 강제 종료

## 관측 과정

### Step 1: Before (MEMORY_LIMIT=256) 실행
- App 로그: MemoryWorker가 3초마다 25MB씩 Heap 증가 (25→50→...→275MB)
- 275MB 도달 시 `[MemoryGuard] Memory limit exceeded (275MB >= 256MB)` → Self-terminating
- 관제 로그: RSS 17MB → 273MB 선형 증가 (ps aux + RSS 정렬로 포착)
- 생존 시간: ~30초

### Step 2: After (MEMORY_LIMIT=512) 실행
- App 로그: Heap 25→...→525MB 도달 후 `[MemoryWorker] Memory Usage Reached Limit. Starting cleanup...`
- **cleanup 메커니즘 동작**: Heap이 25MB로 리셋 후 정상 재개
- 프로세스 종료 없음 → 60초+ 생존 확인
- 핵심: 512MB 환경에서는 MemoryGuard가 아닌 **자체 cleanup**이 먼저 동작

## 핵심 통찰
- MemoryGuard(강제 종료)와 MemoryWorker cleanup(자체 정리)는 **별개의 메커니즘**
- MEMORY_LIMIT가 낮으면 cleanup이 동작하기 전에 MemoryGuard가 먼저 트리거
- MEMORY_LIMIT를 높이면 cleanup이 정상 작동할 여유 확보 → 종료 방지
- 근본 원인은 여전히 메모리 누수(해제 안 함); 환경변수 조정은 임시 방편

## 응용
- 다른 메모리 누수 장애에도 동일 분석 프레임 적용:
  1. 관제로 RSS 선형 증가 패턴 확인
  2. 임계치 로그(CRITICAL)로 보호 메커니즘 식별
  3. 임계치 상향으로 임시 조치 + 자체 cleanup 동작 여부 확인
  4. 근본 해결은 코드 수준 해제 로직 추가
