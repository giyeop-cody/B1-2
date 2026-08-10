# 추론 기록 #03: CPU Spike 분석

## 가설
CpuWorker가 CPU 부하를 점진 증가 → Watchdog 임계치 초과 시 강제 종료

## 관측 과정

### Step 1: Before (CPU_MAX_OCCUPY=100) 실행
- App 로그: CpuWorker Current Load 5% → 10% → ... → 55.73% (3초 간격, 비선형 증가)
- 55.73% 도달 시 `[CpuWorker] CPU Threshold Violated!` → 프로세스 종료
- 생존 시간: ~37초

### Step 2: After (CPU_MAX_OCCUPY=50) 실행
- App 로그: CpuWorker 5% → ... → 49.09% → `Peak reached (50.00%). Starting cooldown...`
- **자체 cooldown 동작**: 50% → 47% → 40% → ... → 5% (점진 감소 후 재상승)
- Watchdog 트리거 없음 → 60초+ 생존

## 핵심 통찰
- Watchdog 임계치는 **약 50%로 고정** (CPU_MAX_OCCUPY 값과 무관)
- CPU_MAX_OCCUPY ≥ 50: CpuWorker가 50%를 돌파하려 함 → Watchdog 트리거 → 종료
- CPU_MAX_OCCUPY ≤ 50: CpuWorker가 50%에서 스스로 cooldown → Watchdog 회피
- 임계치 50%는 Watchdog의 **절대적 안전선**, CPU_MAX_OCCUPY는 CpuWorker의 **자체 목표선**
- 두 값이 만나는 지점(50)이 안정/불안정의 분기점

## 응용
- CPU throttling 장애 분석 프레임:
  1. App 로그에서 부하 증가 패턴 확인 (선형 vs 비선형)
  2. Watchdog/threshold 로그로 보호 메커니즘 임계치 식별
  3. 목표선을 임계치 이하로 조정 → 자체 조절 메커니즘 활성화
  4. 근본 해결: 부하 증가 로직에 backoff/thread pool 도입
