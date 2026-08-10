# 추론 기록 #04: Deadlock 분석

## 가설
MULTI_THREAD_ENABLE=true 시 두 Worker Thread가 서로의 락을 대기 → 교착상태

## 관측 과정

### Step 1: Before (MULTI_THREAD_ENABLE=true) 실행
- App 로그:
  - Worker-Thread-1: LOCK ACQUIRED [Shared_Memory_A] → needs [Socket_Pool_B] → BLOCKED
  - Worker-Thread-2: LOCK ACQUIRED [Socket_Pool_B] → needs [Shared_Memory_A] → BLOCKED
- 14:45:35 이후 로그 완전 중단 (무응답)
- ps -ef: PID 존재 (종료 안 됨)
- ps -p: CPU 0.1% / MEM 0.8% 고정 (3회 측정 변화 없음)
- State: SNl (Sleeping, low priority — 락 대기)

### Step 2: After (MULTI_THREAD_ENABLE=false) 실행
- App 로그: `SYSTEM STATUS: STABLE`
- Scheduler가 Thread-A → B → C 순차 실행, 모두 Completed
- 교착상태 없음, 정상 동작

## 교착상태 4대 조건 검증
| 조건 | 충족 | 근거 |
|------|------|------|
| 상호 배제 | ✅ | Shared_Memory_A, Socket_Pool_B는 단일 스레드만 접근 |
| 점유 대기 | ✅ | T1은 A 보유하며 B 대기, T2는 B 보유하며 A 대기 |
| 비선점 | ✅ | 락은 자발적 해제만 가능 |
| 순환 대기 | ✅ | T1→A→needs B→T2→B→needs A→T1 (순환) |

## 핵심 통찰
- Deadlock은 프로세스가 **죽지 않고 멈추는** 장애 (OOM/CPU와 다른 패턴)
- 진단 신호: PID 존재 + CPU/MEM 정체 + 로그 중단 = Deadlock 의심
- MULTI_THREAD_ENABLE=false는 동시성 이점을 포기하는 임시 조치
- 근본 해결: 락 획득 순서 통일(순환 대기 제거) 또는 타임아웃

## 응용
- 교착상태 진단 프레임:
  1. ps로 PID 존재 + 무응답 확인
  2. ps -p 반복 측정으로 CPU/MEM 정체 확인
  3. App 로그 마지막 줄에서 WAITING/BLOCKED + 락 이름 식별
  4. 락 의존 그래프 그려 순환 구조 확인
  5. 4대 조건 검증 → 교착상태 확정
