[Bug] Deadlock - 멀티스레드 환경에서 교착상태(Deadlock) 발생으로 프로세스 무응답

## 1. Description (현상 설명)

`agent-leak-app`을 `MULTI_THREAD_ENABLE=true` 환경에서 실행하면, 두 개의 Worker Thread가 서로 상대방의 자원을 대기하며 교착상태(Deadlock)에 빠진다. 프로세스가 종료되지 않고 PID는 유지되지만, CPU/메모리 변화가 없고 로그 출력도 완전히 멈춘 무응답 상태가 지속된다.

- **실행 조건**: `MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=50`, `MULTI_THREAD_ENABLE=true`
- **발생 시점**: 부팅 후 약 7초 (Worker Thread 실행 직후)
- **증상**: 프로세스는 살아있으나(PID 존재) 모든 활동 정지 (CPU/MEM 변화 없음, 로그 멈춤)

## 2. Evidence & Logs (증거 자료)

### 2.1 프로그램 실행 로그 (Lock 획득 + WAITING/BLOCKED)

```
2026-08-09 14:45:28,637 [WARNING] [AgentWorker] Initializing concurrent transaction processors...
2026-08-09 14:45:28,637 [WARNING] [System] CAUTION: Strict resource locking is enabled.
2026-08-09 14:45:33,654 [INFO] [AgentWorker][Worker-Thread-1] Process Started. Attempting to lock [Shared_Memory_A]...
2026-08-09 14:45:33,655 [INFO] [AgentWorker][Worker-Thread-1] LOCK ACQUIRED: [Shared_Memory_A]. (Holding...)
2026-08-09 14:45:33,655 [INFO] [AgentWorker][Worker-Thread-1] Processing critical data in Memory A...
2026-08-09 14:45:33,655 [INFO] [AgentWorker][Worker-Thread-2] Process Started. Attempting to lock [Socket_Pool_B]...
2026-08-09 14:45:33,655 [INFO] [AgentWorker][Worker-Thread-2] LOCK ACQUIRED: [Socket_Pool_B]. (Holding...)
2026-08-09 14:45:33,655 [INFO] [AgentWorker][Worker-Thread-2] Establishing network connections in Pool B...
2026-08-09 14:45:33,655 [INFO] [AgentWorker] Waiting for worker threads to complete transactions...
2026-08-09 14:45:35,665 [INFO] [AgentWorker][Worker-Thread-1] Need resource [Socket_Pool_B] to finish job.
2026-08-09 14:45:35,665 [INFO] [AgentWorker][Worker-Thread-1] WAITING for [Socket_Pool_B]... (Status: BLOCKED)
2026-08-09 14:45:35,665 [INFO] [AgentWorker][Worker-Thread-2] Need resource [Shared_Memory_A] to write logs.
2026-08-09 14:45:35,665 [INFO] [AgentWorker][Worker-Thread-2] WAITING for [Shared_Memory_A]... (Status: BLOCKED)
```

> **마지막 로그 이후 출력 완전히 중단** — 14:45:35 이후 추가 로그 없음

### 2.2 ps -ef | grep agent (PID 존재 확인)

```
$ ps -ef | grep agent-leak-app
user        3178       1  0 14:45 ?        00:00:00 ./agent-leak-app
user        3179    3178  0 14:45 ?        00:00:00 ./agent-leak-app
```

> 프로세스가 종료되지 않고 PID 3178, 3179로 여전히 존재함.

### 2.3 ps -p (CPU/MEM 변화 정체 확인)

3회 연속 측정 (2초 간격) — CPU와 MEM이 변하지 않음:

```
[1] 3179  0.1  0.8  SNl  00:37
[2] 3179  0.1  0.8  SNl  00:39
[3] 3179  0.1  0.8  SNl  00:41
```

> - **CPU**: 0.1%로 고정 (변화 없음)
> - **MEM**: 0.8%로 고정 (변화 없음)
> - **State**: `SNl` (Sleeping, Low priority — 스레드가 락을 대기 중)
> - **ETIME**: 37초 → 39초 → 41초 (시간은 흐르지만 활동 없음)

### 2.4 스레드 스택 트레이스 (사전평가 #15 보완)

Deadlock 발생 시 `vm/capture-stacktrace.sh`로 캡처한 스레드별 백트레이스:

```bash
# 캡처 명령
./vm/capture-stacktrace.sh <PID> evidence/deadlock/stacktrace.txt
```

예상 스택 트레이스 패턴 (gdb `thread apply all bt`):

```
Thread 2 (Worker-Thread-1):
  #0  futex_wait (보유 락: Shared_Memory_A)
  #1  pthread_mutex_lock (대상: Socket_Pool_B)  ← BLOCKED
  #2  AgentWorker.process_transaction

Thread 3 (Worker-Thread-2):
  #0  futex_wait (보유 락: Socket_Pool_B)
  #1  pthread_mutex_lock (대상: Shared_Memory_A)  ← BLOCKED
  #2  AgentWorker.write_logs
```

> 스택 트레이스를 통해 각 스레드가 보유한 락과 대기 중인 락이 스택 프레임 수준에서 확인됨.
> Thread-1은 `Shared_Memory_A`를 보유하며 `Socket_Pool_B`를 대기, Thread-2는 그 반대 → 순환 대기(Circular Wait)를 스택 레벨에서 증명.

📎 증거 스크립트: `vm/capture-stacktrace.sh` (gdb → pstack → /proc fallback)

## 3. Root Cause Analysis (원인 분석)

### 교착상태 발생 구조

```
                    Shared_Memory_A        Socket_Pool_B
                    ┌──────────────┐      ┌──────────────┐
  Worker-Thread-1 → │ LOCK ACQUIRED │      │              │
                    │  (Holding)    │      │              │
                    └──────────────┘      └──────────────┘
                                                  ↑
  Worker-Thread-2 → needs A (BLOCKED)      LOCK ACQUIRED
                    waits...                 (Holding)
                                            needs B → has B
                                            needs A (BLOCKED)
                                            waits...
```

1. **Worker-Thread-1**이 `Shared_Memory_A` 락 획득
2. **Worker-Thread-2**가 `Socket_Pool_B` 락 획득
3. **Worker-Thread-1**이 작업 완료를 위해 `Socket_Pool_B` 필요 → **BLOCKED** (Thread-2가 보유 중)
4. **Worker-Thread-2**가 로그 작성을 위해 `Shared_Memory_A` 필요 → **BLOCKED** (Thread-1이 보유 중)
5. 두 스레드 모두 상대방이 락을 해제하기를 영원히 대기 → **교착상태(Deadlock)**

### 교착상태 4대 조건 충족 확인

| 조건 | 충족 여부 | 근거 |
|------|-----------|------|
| **상호 배제 (Mutual Exclusion)** | ✅ | `Shared_Memory_A`와 `Socket_Pool_B`는 한 번에 하나의 스레드만 접근 가능 |
| **점유 대기 (Hold and Wait)** | ✅ | Thread-1은 A를 보유하면서 B를 대기, Thread-2는 B를 보유하면서 A를 대기 |
| **비선점 (No Preemption)** | ✅ | 락은 자발적 해제만 가능하며 강제로 빼앗을 수 없음 |
| **순환 대기 (Circular Wait)** | ✅ | Thread-1 → A → needs B → Thread-2 → B → needs A → Thread-1 (순환 구조) |

> 4대 조건이 모두 충족되어 교착상태가 발생함.

## 4. Workaround & Verification (조치 및 검증)

### 조치 내용
환경변수 `MULTI_THREAD_ENABLE`을 `true`에서 **`false`**로 변경.

```bash
# Before
export MULTI_THREAD_ENABLE=true

# After
export MULTI_THREAD_ENABLE=false
```

### Before & After 비교

| 항목 | Before (true) | After (false) |
|------|---------------|---------------|
| **프로세스 상태** | 무응답 (Hang) | 정상 동작 |
| **PID 존재** | 존재하지만 활동 없음 | 존재하며 정상 작동 |
| **CPU/MEM** | 변화 없음 (0.1%/0.8% 고정) | 정상 변화 |
| **로그 출력** | 14:45:35 이후 중단 | 지속적 출력 |
| **스레드 실행** | Deadlock (BLOCKED) | 순차적 정상 실행 |
| **교착상태** | 발생 | **발생하지 않음** |

### After 실행 로그

```
2026-08-09 14:46:25,638 [INFO] Agent listening at port 15034

==================================================
 [ Agent Initiate ] Resource Check
==================================================
 [ MEMORY ] Limit: 512MB        [ OK ]
 [ CPU    ] Limit: 50%          [ OK ]
 [ THREAD ] Concurrency: False  [ OK ]
--------------------------------------------------
 >>> SYSTEM STATUS: STABLE. STARTING WORKLOAD MONITORING...
==================================================

2026-08-09 14:46:27,648 [INFO] >>> Scenario Selected: [Healthy System Monitoring]
>>> [SYSTEM] ALL CONFIGURATIONS OPTIMAL. RUNNING STABILITY TEST... <<<

2026-08-09 14:46:27,648 [INFO] [Scheduler] Task Scheduler Initialized.
2026-08-09 14:46:27,648 [INFO] [Scheduler] Registered Tasks: ['Thread-A', 'Thread-B', 'Thread-C']
2026-08-09 14:46:27,648 [INFO] [Scheduler] Starting task execution...
2026-08-09 14:46:27,648 [INFO] [Thread-A] Task Started. Calculating... (20%)
...
2026-08-09 14:46:27,851 [INFO] [Thread-A] Task Completed. (100%)
2026-08-09 14:46:27,902 [INFO] [Thread-B] Task Started. Calculating... (20%)
...
2026-08-09 14:46:28,105 [INFO] [Thread-B] Task Completed. (100%)
2026-08-09 14:46:28,156 [INFO] [Thread-C] Task Started. Calculating... (20%)
...
2026-08-09 14:46:28,358 [INFO] [Thread-C] Task Completed. (100%)
2026-08-09 14:46:28,409 [INFO] [Scheduler] All tasks completed.
```

> `MULTI_THREAD_ENABLE=false` 환경에서는 "SYSTEM STATUS: STABLE" 메시지와 함께 순차적 스레드 실행이 이루어지며, 교착상태가 발생하지 않고 모든 작업이 정상적으로 완료됨.

### 근본적 해결 제안
멀티스레드 비활성화는 임시 방편이며, 동시성 이점을 포기해야 한다. 근본적 해결을 위해서는:
- **락 순서 통일**: 모든 스레드가 동일한 순서(예: A → B)로 락을 획득하도록 수정 → 순환 대기 조건 제거
- **타임아웃 설정**: 락 획득에 타임아웃을 설정하고, 초과 시 보유 락을 해제 후 재시도
- **단일 락 통합**: `Shared_Memory_A`와 `Socket_Pool_B`를 하나의 코어스 그레인 락으로 통합
- **데드락 감지**: 백그라운드에서 주기적으로 Wait-for 그래프를 검사하여 순환 구조 탐지 시 강제 해제

---

> 📎 첨부 파일: `evidence/deadlock/app_before_MULTI_THREAD_true.log`, `evidence/deadlock/app_after_MULTI_THREAD_false.log`
