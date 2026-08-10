# B1-2 평가 기준 준수 점검 Q&A

> 과제 평가 기준(이미지 루브릭 + B1-2.md 과제 가이드 + 네이토 사전평가 20항목) 대비 산출물 준수 여부 점검

---

## 평가 기준 1: 장애 재현 및 Before & After

### 1-1. [OOM] MEMORY_LIMIT 변경 전후(Before & After) 비교

**Q: OOM 장애를 재현하고, MEMORY_LIMIT 변경 전후를 비교했는가?**

**A: 준수 ✅**

| 항목 | Before (256MB) | After (512MB) |
|------|----------------|---------------|
| 환경변수 | `MEMORY_LIMIT=256` | `MEMORY_LIMIT=512` |
| Heap 증가 | 25→50→...→275MB | 25→...→525MB |
| 결과 | MemoryGuard 강제 종료 (30초) | 자체 cleanup 후 정상 동작 (60초+) |
| 종료 여부 | 종료됨 | 종료되지 않음 |

- 📎 증거: `evidence/oom/app_before_MEMORY_LIMIT_256.log`, `evidence/oom/app_after_MEMORY_LIMIT_512.log`
- 📎 관제: `evidence/oom/monitor_before_MEMORY_LIMIT_256.log` (RSS 17MB→273MB 선형 증가)
- 📎 리포트: `issues/issue-1-oom.md`
- 📎 재현: `vm/run-oom.sh before|after`
- 📎 추론: `docs/reasoning-02-oom.md`

**최소 2회 실행 요건**: 준수 ✅ (Before 1회, After 1회 = 2회 실행)

---

### 1-2. [CPU] CPU_MAX_OCCUPY 변경 전후(Before & After) 비교

**Q: CPU 과점유를 재현하고, CPU_MAX_OCCUPY 변경 전후를 비교했는가?**

**A: 준수 ✅**

| 항목 | Before (100%) | After (50%) |
|------|---------------|-------------|
| 환경변수 | `CPU_MAX_OCCUPY=100` | `CPU_MAX_OCCUPY=50` |
| CPU 증가 | 5%→10%→...→55.73% | 5%→...→49.09%→50% |
| 결과 | Watchdog 강제 종료 (37초) | cooldown 후 정상 동작 (60초+) |
| 종료 여부 | 종료됨 | 종료되지 않음 |

- 📎 증거: `evidence/cpu/app_before_CPU_MAX_OCCUPY_80.log`, `evidence/cpu/app_after_CPU_MAX_OCCUPY_50.log`
- 📎 리포트: `issues/issue-2-cpu.md`
- 📎 재현: `vm/run-cpu.sh before|after`
- 📎 추론: `docs/reasoning-03-cpu.md`

**CPU 사용률 급상승 구간 캡처**: 준수 ✅ (CpuWorker Current Load 5%→55.73% 시계열)
**종료 로그**: 준수 ✅ (`[CRITICAL] [CpuWorker] CPU Threshold Violated!`)

---

### 1-3. [Deadlock] MULTI_THREAD_ENABLE 변경 전후 비교 + PID 증거

**Q: Deadlock을 재현하고, MULTI_THREAD_ENABLE 변경 전후를 비교했는가?**

**A: 준수 ✅**

| 항목 | Before (true) | After (false) |
|------|---------------|---------------|
| 환경변수 | `MULTI_THREAD_ENABLE=true` | `MULTI_THREAD_ENABLE=false` |
| 스레드 상태 | Thread-1, Thread-2 모두 BLOCKED | Thread-A→B→C 순차 정상 실행 |
| 프로세스 | PID 존재, 무응답 | 정상 동작 |
| 교착상태 | 발생 (4대 조건 충족) | 발생하지 않음 |

- 📎 증거: `evidence/deadlock/app_before_MULTI_THREAD_true.log`, `evidence/deadlock/app_after_MULTI_THREAD_false.log`
- 📎 리포트: `issues/issue-3-deadlock.md`
- 📎 재현: `vm/run-deadlock.sh before|after`
- 📎 추론: `docs/reasoning-04-deadlock.md`

**PID 존재 증거**: 준수 ✅ (`ps -ef` 출력: PID 3178, 3179 존재)
**CPU/MEM 변화 정체 증거**: 준수 ✅ (3회 연속 측정: CPU 0.1%, MEM 0.8% 고정)
**마지막 로그 지점**: 준수 ✅ (`WAITING for [Socket_Pool_B]... (Status: BLOCKED)`)

---

### 1-4. [Deadlock] 스레드/락 대기 추론 근거 (스택 트레이스)

**Q: 스레드가 락을 대기하고 있음을 증명했는가? (스택 트레이스)**

**A: 준수 ✅ (사전평가 #15 FAIL → 보완 완료)**

`/proc` 기반 스택 트레이스 캡처:
- 3개 스레드 모두 `wchan=futex_wait_queue` (뮤텍스 대기)
- `syscall=202(futex)` — 커널 레벨에서 락 대기 증명
- 서로 다른 futex 주소 (0x34d2cbb0 vs 0x34d246a0) → 순환 대기 증명

- 📎 증거: `evidence/deadlock/stacktrace.txt`
- 📎 스크립트: `vm/capture-stacktrace.sh` (gdb→pstack→/proc fallback)
- 📎 추론: `docs/reasoning-07-stacktrace.md`

---

## 평가 기준 2: 리포트 형식

### 2-1. [Format] 3건의 GitHub Issue 형태 기술 리포트

**Q: OOM, CPU, Deadlock 각각에 대해 GitHub Issue 형태의 리포트를 작성했는가?**

**A: 준수 ✅**

3개 리포트 + 1개 보너스 리포트 작성:
1. `issues/issue-1-oom.md` — [Bug] OOM - MemoryGuard 강제 종료
2. `issues/issue-2-cpu.md` — [Bug] CPU - Watchdog 보호 조치
3. `issues/issue-3-deadlock.md` — [Bug] Deadlock - 교착상태 무응답
4. `issues/bonus-scheduling.md` — [Analysis] FCFS 스케줄링 추론 (보너스)

실제 GitHub Issues로도 등록됨 (#5, #6, #7, #8).

### 2-2. [Format] 각 리포트의 필수 포함 항목

**Q: 각 리포트가 아래 구조를 갖추고 있는가?**
- 발생 현상 (Description)
- 재현 경로 및 증거 (Evidence & Logs)
- 근본 원인 (Root Cause Analysis)
- 조치 내용 (Workaround & Verification)
- 결과 확인 (Before & After)

**A: 준수 ✅**

| 항목 | OOM | CPU | Deadlock |
|------|-----|-----|----------|
| Description (현상) | ✅ | ✅ | ✅ |
| Evidence & Logs (증거) | ✅ | ✅ | ✅ |
| Root Cause Analysis (원인) | ✅ | ✅ | ✅ |
| Workaround & Verification (조치) | ✅ | ✅ | ✅ |
| Before & After (결과) | ✅ | ✅ | ✅ |

---

## 평가 기준 3: 케이스별 필수 증거 최소 요건

### 3-1. OOM 필수 증거

**Q: 아래 3가지 OOM 증거를 모두 제출했는가?**

| 요건 | 준수 | 증거 |
|------|------|------|
| monitor.sh 결과 (메모리 상승 수치) | ✅ | `evidence/oom/monitor_before_MEMORY_LIMIT_256.log` — RSS 17MB→273MB |
| 종료 직전/직후 실행 로그 | ✅ | `evidence/oom/app_before_MEMORY_LIMIT_256.log` — `MemoryGuard... Self-terminating` |
| MEMORY_LIMIT 변경 전후 비교 (최소 2회) | ✅ | Before(256MB, 30초 종료) / After(512MB, 60초+ 생존) |

### 3-2. CPU 필수 증거

**Q: 아래 3가지 CPU 증거를 모두 제출했는가?**

| 요건 | 준수 | 증거 |
|------|------|------|
| CPU 사용률 급상승 구간 캡처 | ✅ | `evidence/cpu/app_before_CPU_MAX_OCCUPY_80.log` — Load 5%→55.73% |
| 종료 로그 ("WATCHDOG… SIGTERM" 등) | ✅ | `CPU Threshold Violated! (55.73%)` |
| CPU_MAX_OCCUPY 변경 전후 비교 | ✅ | Before(100%, 37초 종료) / After(50%, cooldown 정상) |

### 3-3. Deadlock 필수 증거

**Q: 아래 4가지 Deadlock 증거를 모두 제출했는가?**

| 요건 | 준수 | 증거 |
|------|------|------|
| PID 존재 증거 (ps -ef \| grep) | ✅ | `ps -ef` 출력: PID 3178, 3179 존재 |
| CPU/MEM 변화 정체 증거 | ✅ | 3회 측정: CPU 0.1%, MEM 0.8% 고정 (State: SNl) |
| 마지막 로그 지점 ("WAITING… BLOCKED") | ✅ | `WAITING for [Socket_Pool_B]... (Status: BLOCKED)` |
| 스레드/락 대기 추론 근거 | ✅ | 4대 조건 검증 표 + `/proc` 스택 트레이스 (futex_wait_queue) |

---

## 평가 기준 4: 관제 도구 (monitor.sh)

### 4-1. monitor.sh를 활용한 관측

**Q: monitor.sh를 활용하여 프로세스의 자원 사용 패턴을 관측했는가?**

**A: 준수 ✅**

- `vm/monitor.sh`: `ps aux` + RSS 정렬로 worker 프로세스 추적 (CPU/MEM/RSS/VSZ 시계열)
- 관제 로그: `evidence/oom/monitor_before_MEMORY_LIMIT_256.log` (2초 간격, 62줄)
- 설계 과정: `docs/reasoning-01-monitoring.md` (1차 pgrep 실패 → 2차 ps aux+RSS 정렬 성공)

### 4-2. 관제 도구 선택 및 필드 이해

**Q: ps/top 등 관제 도구의 선택 이유와 필드 의미를 설명했는가?**

**A: 준수 ✅**

- `docs/reasoning-01-monitoring.md`: `ps aux` 출력 필드 설명 (%cpu=3열, %mem=4열, rss=6열, vsz=5열)
- 프로세스 분기 시 단일 PID 추적의 위험성과 RSS 정렬의 필요성 설명

---

## 평가 기준 5: 원인 분석 및 OS 동작 원리

### 5-1. MemoryGuard 동작 원리

**Q: 메모리 누수가 시스템에 미치는 영향과 MemoryGuard의 동작을 설명했는가?**

**A: 준수 ✅**

- OOM 리포트 §3: 힙 메모리 해제 없음 → 선형 증가 → MemoryGuard SIGKILL
- 추론: `docs/reasoning-02-oom.md` — MemoryGuard(강제 종료) vs MemoryWorker cleanup(자체 정리) 별개 메커니즘 식별

### 5-2. Watchdog 동작 원리

**Q: CPU 과점유가 시스템 지연을 유발하는 원리와 Watchdog 동작을 설명했는가?**

**A: 준수 ✅**

- CPU 리포트 §3: CpuWorker 부하 증가 → Watchdog 임계치(약 50%) 초과 → SIGTERM
- 추론: `docs/reasoning-03-cpu.md` — Watchdog 임계치 50% 고정, CPU_MAX_OCCUPY와의 관계 분석

### 5-3. 교착상태 4대 조건

**Q: Deadlock의 4대 조건을 모두 검증했는가?**

**A: 준수 ✅**

| 조건 | 충족 | 근거 |
|------|------|------|
| 상호 배제 | ✅ | Shared_Memory_A, Socket_Pool_B 단일 스레드만 접근 |
| 점유 대기 | ✅ | T1: A 보유+B 대기, T2: B 보유+A 대기 |
| 비선점 | ✅ | 락은 자발적 해제만 가능 |
| 순환 대기 | ✅ | T1→A→B→T2→B→A→T1 + futex 주소 상이 |

### 5-4. 근본 원인 분석 및 코드 개선 제안

**Q: 근본 원인을 분석하고 코드 수준의 개선안을 제시했는가?**

**A: 준수 ✅**

- OOM: `del`/`pop`으로 주기적 메모리 해제, GC 주기 조정, memory_profiler 권장
- CPU: backoff 메커니즘, CPU 모니터링 주기 단축, task queue 도입
- Deadlock: 락 획득 순서 통일, 타임아웃 설정, 단일 락 통합, 데드락 감지

---

## 평가 기준 6: 보너스 (스케줄링 알고리즘 추론)

### 6-1. 스케줄링 알고리즘 추론

**Q: 로그 패턴 분석을 통해 스케줄링 알고리즘을 추론했는가?**

**A: 준수 ✅**

- `issues/bonus-scheduling.md`: Thread-A→B→C 순차 실행 → FCFS 추론
- `docs/reasoning-05-scheduling.md`: FCFS vs Round-Robin vs Priority 검증 과정
- 장단점 + 적합 서비스 분석 (배치: 적합, 웹 서버: 부적합)

---

## 평가 기준 7: 동시 장애 우선순위 (사전평가 #18)

### 7-1. 동시 장애 우선순위 결정 기준

**Q: 동시 장애 발생 시 우선순위 결정 기준이 있는가?**

**A: 준수 ✅ (사전평가 #18 FAIL → 보완 완료)**

- `docs/incident-priority-matrix.md`: 서비스 영향도/확산 속도/복구 난이도 기준
- OOM 1순위, CPU 2순위, Deadlock 3순위 (근거 포함)
- 조치 절차 플로우차트 + 의사결정 매트릭스

### 7-2. 치명도 등급 매트릭스

**Q: 치명도 등급별 우선조치 기준이 있는가?**

**A: 준수 ✅**

- `docs/severity-matrix.md`: P0(Critical)~P3(Low) 등급 + 조치 시한 + 에스컬레이션

---

## 평가 기준 8: 재현 가능성

### 8-1. 환경 구성 및 재현 스크립트

**Q: 다른 사람이 동일한 결과를 재현할 수 있는가?**

**A: 준수 ✅**

- `vm/user-data.yml`: cloud-init VM 프로비저닝
- `vm/setup-env.sh`: 수동 환경 구성
- `vm/run-oom.sh`, `vm/run-cpu.sh`, `vm/run-deadlock.sh`: 시나리오별 재현 스크립트
- `vm/monitor.sh`: 관제 스크립트
- `vm/capture-stacktrace.sh`: 스택 트레이스 캡처
- `docs/reproducibility.md`: VM/수동 환경별 재현 가이드 + 증거 체크리스트

### 8-2. 추론 과정 기록

**Q: 분석 추론 과정이 기록되어 응용 가능한가?**

**A: 준수 ✅**

| 문서 | 내용 |
|------|------|
| `reasoning-00-approach.md` | 컨테이너 vs VM 선정 근거 |
| `reasoning-01-monitoring.md` | 관제 스크립트 설계 (실패→성공) |
| `reasoning-02-oom.md` | OOM 분석 (MemoryGuard vs cleanup) |
| `reasoning-03-cpu.md` | CPU 분석 (Watchdog 임계치 50%) |
| `reasoning-04-deadlock.md` | Deadlock 분석 (4대 조건) |
| `reasoning-05-scheduling.md` | FCFS 추론 (알고리즘 검증) |
| `reasoning-06-pre-eval.md` | 사전평가 API 흐름 + 분석 |
| `reasoning-07-stacktrace.md` | 스택 트레이스 (gdb vs /proc) |

각 문서에 "응용 포인트" 섹션 포함 → 다른 장애 상황에도 프레임 재사용 가능

---

## 종합 준수 요약

| 평가 기준 | 항목 수 | 준수 | 미준수 | 비고 |
|-----------|---------|------|--------|------|
| 1. 장애 재현 (Before & After) | 4 | 4 | 0 | OOM/CPU/Deadlock/스택트레이스 |
| 2. 리포트 형식 | 2 | 2 | 0 | 3건 GitHub Issue + 필수 구조 |
| 3. 필수 증거 | 3 | 3 | 0 | OOM(3)/CPU(3)/Deadlock(4) |
| 4. 관제 도구 | 2 | 2 | 0 | monitor.sh + 필드 설명 |
| 5. 원인 분석 | 4 | 4 | 0 | MemoryGuard/Watchdog/4대조건/개선안 |
| 6. 보너스 | 1 | 1 | 0 | FCFS 추론 |
| 7. 동시 장애 | 2 | 2 | 0 | 우선순위 + 치명도 매트릭스 |
| 8. 재현 가능성 | 2 | 2 | 0 | 스크립트 + 추론 기록 |
| **합계** | **20** | **20** | **0** | **100% 준수** |

> 네이토 사전평가 2차 결과(18/20)에서 FAIL했던 #15(스택 트레이스)와 #18(동시 장애 우선순위)은 eval 브랜치에서 보완 완료. 모든 평가 기준 준수.
