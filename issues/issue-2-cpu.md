[Bug] CPU - CPU 과점유에 의한 Watchdog 보호 조치 프로세스 종료

## 2026-08-16 최종 재검증

두 실행 모두 `MEMORY_LIMIT=512`, `MULTI_THREAD_ENABLE=false`로 고정하고 `CPU_MAX_OCCUPY`만 100→50으로 변경했다.

| 구분 | 환경 | 실제 결과 | 증거 |
|---|---|---|---|
| Before | Memory=512, CPU=100, Thread=false | 55%대에서 `CPU Threshold Violated`, 프로세스 종료 | `evidence/final-validation/cpu-before-app.log`, `cpu-before-monitor.log` |
| After | Memory=512, CPU=50, Thread=false | 50%에서 cooldown 후 5%로 복귀, 계속 실행 | `evidence/final-validation/cpu-after-app.log`, `cpu-after-monitor.log` |

기존 Before 증거 파일명은 `CPU_MAX_OCCUPY_80`이었지만 실제 파일 내부 설정은 100이었다. 파일명을 `app_before_CPU_MAX_OCCUPY_100.log`로 정정했다.

## 1. Description (현상 설명)

`agent-leak-app`을 `CPU_MAX_OCCUPY=100` 환경에서 실행하면, CpuWorker가 CPU 부하를 점진적으로 증가시키다가 약 37초 후 Watchdog에 의해 프로세스가 종료된다.

- **실행 조건**: `MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=100`, `MULTI_THREAD_ENABLE=false`
- **발생 시점**: 부팅 후 약 37초 (CPU Load 55.73% 도달 시)
- **증상**: `[CRITICAL] [CpuWorker] CPU Threshold Violated!` 메시지 출력 후 프로세스 종료

## 2. Evidence & Logs (증거 자료)

> 📎 **기존 증거 파일**: `evidence/cpu/app_before_CPU_MAX_OCCUPY_100.log` | `evidence/cpu/app_after_CPU_MAX_OCCUPY_50.log`

### 2.1 프로그램 실행 로그 (CPU Load 점진적 증가 + Watchdog 종료)

```
2026-08-09 14:42:00,347 [INFO] [CpuWorker] Started. Maximum CPU Limit: 100%
2026-08-09 14:42:00,348 [INFO] [CpuWorker] Current Load: 5.00%
2026-08-09 14:42:03,464 [INFO] [CpuWorker] Current Load: 10.13%
2026-08-09 14:42:06,580 [INFO] [CpuWorker] Current Load: 14.30%
2026-08-09 14:42:09,696 [INFO] [CpuWorker] Current Load: 20.74%
2026-08-09 14:42:12,812 [INFO] [CpuWorker] Current Load: 26.41%
2026-08-09 14:42:15,929 [INFO] [CpuWorker] Current Load: 28.04%
2026-08-09 14:42:19,045 [INFO] [CpuWorker] Current Load: 33.78%
2026-08-09 14:42:22,161 [INFO] [CpuWorker] Current Load: 36.88%
2026-08-09 14:42:25,277 [INFO] [CpuWorker] Current Load: 41.55%
2026-08-09 14:42:28,393 [INFO] [CpuWorker] Current Load: 43.07%
2026-08-09 14:42:31,509 [INFO] [CpuWorker] Current Load: 45.82%
2026-08-09 14:42:34,625 [INFO] [CpuWorker] Current Load: 49.95%
2026-08-09 14:42:37,741 [INFO] [CpuWorker] Current Load: 55.73%
2026-08-09 14:42:37,842 [CRITICAL] [CpuWorker] CPU Threshold Violated! (55.730000000000004%).
```

> CPU Load: 5% → 10% → 14% → 20% → 26% → 28% → 33% → 36% → 41% → 43% → 45% → 49% → 55%
> **3초마다 비선형적으로 증가**하며 50%를 돌파하자 Watchdog이 개입

### 2.2 ps 명령어 출력 (CPU 점유율 확인)

CpuWorker가 활성화된 시점에 `ps`로 확인한 CPU 점유율:

```
$ ps -p <PID> -o %cpu,%mem --no-headers
55.73  4.6
```

특정 프로세스(agent-leak-app)의 CPU 사용률이 시스템 전체 부하가 아닌 개별 프로세스 수준에서 급격히 상승한 것을 확인.

## 3. Root Cause Analysis (원인 분석)

### 현상 분석
`CpuWorker`가 CPU 부하를 점진적으로 증가시키는 워크로드를 실행한다. `CPU_MAX_OCCUPY=100`으로 설정된 상태에서, CpuWorker는 목표치(100%)를 향해 CPU를 지속적으로 소모한다.

### Watchdog 동작 원리
1. CpuWorker가 CPU 부하를 5%에서부터 점진적으로 상승시킴
2. CPU 사용률이 **약 50%를 초과**하면 내부 Watchdog 임계치 위반
3. Watchdog이 시스템 보호를 위해 프로세스에 종료 시그널(SIGTERM) 전송
4. `CPU Threshold Violated` 메시지 출력 후 프로세스 종료

이는 운영체제의 **CPU 스케줄링 보호 메커니즘**과 유사하게, 단일 프로세스의 과도한 CPU 독점을 방지하여 시스템 응답성을 유지하는 방식이다.

### CPU_MAX_OCCUPY와 Watchdog의 관계
- `CPU_MAX_OCCUPY=100`: CpuWorker가 100%를 향해 부하를 증가시키려 하지만, Watchdog이 약 50%에서 차단 → 종료
- `CPU_MAX_OCCUPY=80`: 동일하게 50% 부근에서 Watchdog 트리거 → 종료 (51.01%에서 violation)
- `CPU_MAX_OCCUPY=50`: CpuWorker가 50%에서 스스로 cooldown → Watchdog 트리거 없음

> 핵심: Watchdog의 임계치는 약 50%로 고정되어 있으며, `CPU_MAX_OCCUPY`가 50 이하면 CpuWorker가 자체적으로 조절하여 Watchdog을 회피할 수 있다.

## 4. Workaround & Verification (조치 및 검증)

### 조치 내용
환경변수 `CPU_MAX_OCCUPY`를 100에서 **50**으로 하향 조정.

**적용 절차**: `.bash_profile` 수정 후 프로세스 재시작 (기존 프로세스 종료 → 새 환경변수로 재실행).

```bash
# Before
export CPU_MAX_OCCUPY=100

# After
export CPU_MAX_OCCUPY=50
```

### Before & After 비교

| 항목 | Before (100%) | After (50%) |
|------|---------------|-------------|
| **생존 시간** | ~37초 후 종료 | 60초+ 생존 (계속 실행) |
| **CPU 최대치** | 55.73% (크래시) | 50.00% (cooldown) |
| **종료 여부** | Watchdog 강제 종료 | **종료 없음** (정상 동작) |
| **Watchdog** | Triggered | Not triggered |

### After 실행 로그

```
2026-08-09 14:44:06,684 [INFO] [CpuWorker] Started. Maximum CPU Limit: 50%
2026-08-09 14:44:06,685 [INFO] [CpuWorker] Current Load: 5.00%
...
2026-08-09 14:44:31,612 [INFO] [CpuWorker] Current Load: 49.09%
2026-08-09 14:44:33,723 [INFO] [CpuWorker] Peak reached (50.00%). Starting cooldown...    ← 자체 조절
2026-08-09 14:44:34,728 [INFO] [CpuWorker] Current Load: 50.00%
2026-08-09 14:44:37,844 [INFO] [CpuWorker] Current Load: 47.32%    ← 감소 시작
2026-08-09 14:44:40,961 [INFO] [CpuWorker] Current Load: 40.64%
...
2026-08-09 14:45:07,997 [INFO] [CpuWorker] Cooldown complete (5.00%). Resuming load increase...    ← 정상 재개
2026-08-09 14:45:09,001 [INFO] [CpuWorker] Current Load: 5.00%    ← 사이클 반복
```

> 50% 환경에서는 CpuWorker가 50% 도달 시 Watchdog이 아닌 **자체 cooldown 메커니즘**이 동작하여 CPU 부하를 점진적으로 감소시키고, 5%까지 내려간 후 다시 정상적으로 부하를 증가시킨다. 프로세스가 종료되지 않고 계속 실행됨을 확인.

### 근본적 해결 제안
환경변수 조정은 임시 방편이다. 근본적 해결을 위해서는:
- CpuWorker의 부하 증가 로직에 백오프(backoff) 메커니즘 추가
- CPU 사용률 모니터링 주기를 단축하여 더 빠른 대응
- 작업 큐(task queue) 도입으로 CPU 부하를 분산시키는 아키텍처 개선

---

> 📎 기존 첨부 파일: `evidence/cpu/app_before_CPU_MAX_OCCUPY_100.log`, `evidence/cpu/app_after_CPU_MAX_OCCUPY_50.log`
