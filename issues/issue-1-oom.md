[Bug] OOM - 메모리 누수로 인한 MemoryGuard 강제 종료

## 2026-08-16 최종 재검증

비교 변수를 분리하기 위해 두 실행 모두 `CPU_MAX_OCCUPY=50`, `MULTI_THREAD_ENABLE=false`로 고정하고 `MEMORY_LIMIT`만 256→512로 변경했다.

| 구분 | 환경 | 실제 결과 | 증거 |
|---|---|---|---|
| Before | Memory=256, CPU=50, Thread=false | 275MB에서 `Memory limit exceeded`, 프로세스 종료 | `evidence/final-validation/oom-before-app.log`, `oom-before-monitor.log` |
| After | Memory=512, CPU=50, Thread=false | 525MB에서 cleanup, `MEMORY RECOVERED`, 계속 실행 | `evidence/final-validation/oom-after-app.log`, `oom-after-monitor.log` |

기존 OOM After 실행 스크립트가 CPU=100을 사용하던 문제를 수정했다. CPU Watchdog이 Memory cleanup보다 먼저 개입할 수 있었기 때문에, 이는 OOM 실험에서 CPU라는 다른 변수가 섞이는 문제였다.

## 1. Description (현상 설명)

`agent-leak-app`을 `MEMORY_LIMIT=256` 환경에서 실행하면, 약 30초 후 `MemoryGuard`에 의해 프로세스가 예고 없이 강제 종료된다.

- **실행 조건**: `MEMORY_LIMIT=256`, `CPU_MAX_OCCUPY=80`, `MULTI_THREAD_ENABLE=false`
- **발생 시점**: 부팅 후 약 30초 (Heap 275MB 도달 시)
- **증상**: 터미널에 `SELF-TERMINATED` 메시지 출력 후 프로세스 종료

## 2. Evidence & Logs (증거 자료)

> 📎 **증거 파일**: `evidence/oom/app_before_MEMORY_LIMIT_256.log` | `evidence/oom/app_after_MEMORY_LIMIT_512.log` | `evidence/oom/monitor_before_MEMORY_LIMIT_256.log`

### 2.1 monitor.sh 관제 로그 (RSS 선형 증가)

`monitor.sh`를 통해 수집된 관제 로그. 자식 프로세스(PID 2062)의 RSS가 선형적으로 증가하는 패턴 확인.

```
[2026-08-09 14:38:50] PROCESS:agent-leak-app PID:2062 CPU:2.0%  MEM:0.8%  RSS:17504KB
[2026-08-09 14:38:52] PROCESS:agent-leak-app PID:2062 CPU:1.2%  MEM:2.1%  RSS:43288KB
[2026-08-09 14:38:54] PROCESS:agent-leak-app PID:2062 CPU:1.1%  MEM:3.3%  RSS:68896KB
[2026-08-09 14:38:56] PROCESS:agent-leak-app PID:2062 CPU:0.9%  MEM:4.6%  RSS:94504KB
[2026-08-09 14:38:58] PROCESS:agent-leak-app PID:2062 CPU:0.7%  MEM:4.6%  RSS:94504KB
[2026-08-09 14:39:00] PROCESS:agent-leak-app PID:2062 CPU:0.8%  MEM:5.9%  RSS:120112KB
[2026-08-09 14:39:02] PROCESS:agent-leak-app PID:2062 CPU:0.8%  MEM:7.1%  RSS:145720KB
[2026-08-09 14:39:04] PROCESS:agent-leak-app PID:2062 CPU:0.7%  MEM:7.1%  RSS:145720KB
[2026-08-09 14:39:06] PROCESS:agent-leak-app PID:2062 CPU:0.7%  MEM:8.4%  RSS:171328KB
[2026-08-09 14:39:08] PROCESS:agent-leak-app PID:2062 CPU:0.7%  MEM:9.6%  RSS:196936KB
[2026-08-09 14:39:10] PROCESS:agent-leak-app PID:2062 CPU:0.7%  MEM:9.6%  RSS:196936KB
[2026-08-09 14:39:12] PROCESS:agent-leak-app PID:2062 CPU:0.6%  MEM:10.9% RSS:222544KB
[2026-08-09 14:39:14] PROCESS:agent-leak-app PID:2062 CPU:0.6%  MEM:12.2% RSS:248152KB
[2026-08-09 14:39:16] PROCESS:agent-leak-app PID:2062 CPU:0.6%  MEM:12.2% RSS:248152KB
[2026-08-09 14:39:18] PROCESS:agent-leak-app PID:2062 CPU:0.6%  MEM:13.4% RSS:273760KB
```

> RSS: 17MB → 43MB → 68MB → 94MB → 120MB → 145MB → 171MB → 196MB → 222MB → 248MB → 273MB
> **약 3초마다 25MB씩 선형 증가** → 전형적인 메모리 누수 패턴

### 2.2 프로그램 실행 로그 (Heap 증가 + MemoryGuard 종료)

```
2026-08-09 14:38:50,378 [INFO] [MemoryWorker] Current Heap: 25MB
2026-08-09 14:38:53,409 [INFO] [MemoryWorker] Current Heap: 50MB
2026-08-09 14:38:56,440 [INFO] [MemoryWorker] Current Heap: 75MB
2026-08-09 14:38:59,470 [INFO] [MemoryWorker] Current Heap: 100MB
2026-08-09 14:39:02,501 [INFO] [MemoryWorker] Current Heap: 125MB
2026-08-09 14:39:05,528 [INFO] [MemoryWorker] Current Heap: 150MB
2026-08-09 14:39:08,563 [INFO] [MemoryWorker] Current Heap: 175MB
2026-08-09 14:39:11,593 [INFO] [MemoryWorker] Current Heap: 200MB
2026-08-09 14:39:14,623 [INFO] [MemoryWorker] Current Heap: 225MB
2026-08-09 14:39:17,655 [INFO] [MemoryWorker] Current Heap: 250MB
2026-08-09 14:39:20,690 [INFO] [MemoryWorker] Current Heap: 275MB
2026-08-09 14:39:20,690 [CRITICAL] [MemoryGuard] Memory limit exceeded (275MB >= 256MB) / (Recommend Over 256MB)
2026-08-09 14:39:20,690 [CRITICAL] [MemoryGuard] Self-terminating process 2062 to prevent system instability.
```

### 2.3 ps 명령어 출력 (프로세스 종료 확인)

```
$ ps -ef | grep agent-leak-app
(프로세스 없음 — MemoryGuard에 의해 종료됨)
```

## 3. Root Cause Analysis (원인 분석)

### 현상 분석
`agent-leak-app` 내부의 `MemoryWorker`가 힙(Heap) 메모리에 데이터를 지속적으로 할당하고 해제하지 않는 메모리 누수(Memory Leak) 결함이 존재한다.

- **증가 패턴**: 3초마다 25MB씩 선형 증가 (25 → 50 → 75 → ... → 275MB)
- **해제 없음**: 할당된 메모리가 `del` 또는 `pop` 등으로 해제되지 않음

### 시스템 동작 원리
1. 프로세스의 물리 메모리 사용량이 `MEMORY_LIMIT`(256MB)에 도달
2. 애플리케이션 내부의 **MemoryGuard 정책**이 시스템 전체 불안정을 방지하기 위해 해당 프로세스에 SIGKILL 시그널 전송
3. 프로세스가 "Self-terminating" 메시지를 출력하고 즉시 종료

이는 운영체제의 **OOM(Out of Memory) 보호 메커니즘**과 유사하게, 시스템 전체의 안정성을 위해 단일 프로세스를 희생시키는 방식이다.

## 4. Workaround & Verification (조치 및 검증)

### 조치 내용
환경변수 `MEMORY_LIMIT`를 256MB에서 **512MB**로 상향 조정.

**적용 절차**: `.bash_profile` 수정 후 프로세스 재시작 (기존 프로세스 종료 → 새 환경변수로 재실행).

```bash
# Before
export MEMORY_LIMIT=256

# After
export MEMORY_LIMIT=512
```

### Before & After 비교

| 항목 | Before (256MB) | After (512MB) |
|------|----------------|---------------|
| **생존 시간** | ~30초 후 종료 | 60초+ 생존 (계속 실행) |
| **Heap 최대치** | 275MB (크래시) | 525MB (자체 cleanup) |
| **종료 여부** | MemoryGuard 강제 종료 | **종료 없음** (정상 동작) |
| **MemoryGuard** | Triggered | Not triggered |

### After 실행 로그

```
2026-08-09 14:44:06,684 [INFO] [MemoryWorker] Current Heap: 25MB
... (중략) ...
2026-08-09 14:45:04,246 [INFO] [MemoryWorker] Current Heap: 500MB
2026-08-09 14:45:07,277 [INFO] [MemoryWorker] Current Heap: 525MB
2026-08-09 14:45:07,277 [WARNING] [MemoryWorker] Memory Usage Reached Limit (525MB). Starting cleanup...
2026-08-09 14:45:12,336 [INFO] [MemoryWorker] Current Heap: 25MB    ← cleanup 후 25MB로 리셋
2026-08-09 14:45:15,363 [INFO] [MemoryWorker] Current Heap: 50MB    ← 정상 재개
```

> 512MB 환경에서는 525MB 도달 시 MemoryGuard가 아닌 **자체 cleanup 메커니즘**이 동작하여 Heap을 25MB로 리셋하고 정상적으로 작업을 재개한다. 프로세스가 종료되지 않고 계속 실행됨을 확인.

### 근본적 해결 제안
환경변수 조정은 임시 방편이다. 근본적 해결을 위해서는:
- 소스 코드 내 `MemoryWorker`에서 불필요한 데이터를 주기적으로 `del` 또는 `pop`으로 해제
- 가비지 컬렉션(GC) 주기 조정
- 메모리 프로파일링 도구(memory_profiler 등)로 누수 지점 정확히 식별 후 수정

---

> 📎 첨부 파일: `evidence/oom/app_before_MEMORY_LIMIT_256.log`, `evidence/oom/app_after_MEMORY_LIMIT_512.log`, `evidence/oom/monitor_before_MEMORY_LIMIT_256.log`
