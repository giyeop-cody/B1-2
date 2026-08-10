# [Analysis] 로그 패턴 분석을 통한 스케줄링 알고리즘 추론

## 1. 로그 관찰 개요

`agent-leak-app`을 `MULTI_THREAD_ENABLE=false`, `MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=50` 환경에서 실행했을 때, "Healthy System Monitoring" 시나리오에서 스레드 작업 스케줄링 패턴을 관찰했다.

## 2. 증거 자료

`[Scheduler]`에 의해 등록된 3개의 태스크(Thread-A, Thread-B, Thread-C)의 실행 로그:

```
2026-08-09 14:46:27,648 [INFO] [Scheduler] Task Scheduler Initialized.
2026-08-09 14:46:27,648 [INFO] [Scheduler] Registered Tasks: ['Thread-A', 'Thread-B', 'Thread-C']
2026-08-09 14:46:27,648 [INFO] [Scheduler] Starting task execution...

2026-08-09 14:46:27,648 [INFO] [Thread-A] Task Started. Calculating... (20%)
2026-08-09 14:46:27,699 [INFO] [Thread-A] Calculating... (40%)
2026-08-09 14:46:27,750 [INFO] [Thread-A] Calculating... (60%)
2026-08-09 14:46:27,801 [INFO] [Thread-A] Calculating... (80%)
2026-08-09 14:46:27,851 [INFO] [Thread-A] Task Completed. (100%)

2026-08-09 14:46:27,902 [INFO] [Thread-B] Task Started. Calculating... (20%)
2026-08-09 14:46:27,953 [INFO] [Thread-B] Calculating... (40%)
2026-08-09 14:46:28,004 [INFO] [Thread-B] Calculating... (60%)
2026-08-09 14:46:28,054 [INFO] [Thread-B] Calculating... (80%)
2026-08-09 14:46:28,105 [INFO] [Thread-B] Task Completed. (100%)

2026-08-09 14:46:28,156 [INFO] [Thread-C] Task Started. Calculating... (20%)
2026-08-09 14:46:28,206 [INFO] [Thread-C] Calculating... (40%)
2026-08-09 14:46:28,257 [INFO] [Thread-C] Calculating... (60%)
2026-08-09 14:46:28,308 [INFO] [Thread-C] Calculating... (80%)
2026-08-09 14:46:28,358 [INFO] [Thread-C] Task Completed. (100%)

2026-08-09 14:46:28,409 [INFO] [Scheduler] All tasks completed.
```

## 3. 패턴 분석 및 결론

### 관찰된 특징

| 특징 | 관찰 내용 |
|------|-----------|
| **순차 처리** | Thread-A가 100% 완료된 후에만 Thread-B가 시작됨 |
| **비선점** | 한 스레드가 실행 중일 때 다른 스레드가 끼어들지 않음 |
| **등록 순서** | 등록된 순서(A → B → C)대로 실행됨 |
| **시간 할당량** | 각 스레드가 완료될 때까지 CPU를 독점 (시간 할당량 없음) |
| **우선순위** | 모든 스레드가 동일한 우선순위로 처리됨 |

### 알고리즘 후보 비교

| 알고리즘 | 순차 처리 | 비선점 | 등록 순서 | 시간 할당량 | 일치 여부 |
|----------|-----------|--------|-----------|------------|-----------|
| **FCFS (First Come First Served)** | ✅ | ✅ | ✅ | 없음 | **✅ 완전 일치** |
| Round-Robin | ❌ (시간 할당량으로 교체) | ❌ | 부분 | 있음 | ❌ |
| Priority | ✅ | ✅ | ❌ (우선순위 순) | 없음 | ❌ |

### 최종 결론

**FCFS (First Come First Served) 스케줄링 알고리즘**으로 추론된다.

근거:
1. Thread-A가 20% → 40% → 60% → 80% → 100%까지 중단 없이 실행됨 (비선점)
2. Thread-A 완료 후에만 Thread-B가 시작됨 (순차 처리)
3. 등록된 순서(A, B, C)가 실행 순서와 동일함 (FCFS)
4. Round-Robin과 달리 시간 할당량(time quantum)으로 인한 컨텍스트 스위칭이 관측되지 않음

## 4. 장단점 및 적합한 아키텍처 분석

### FCFS 장점
- **구현 단순**: FIFO 큐 하나로 구현 가능
- **오버헤드 적음**: 컨텍스트 스위칭이 없어 CPU 오버헤드 최소
- **공정성**: 먼저 들어온 작업이 먼저 완료됨 (기아(starvation) 없음)
- **예측 용이**: 실행 순서와 완료 시간을 쉽게 예측 가능

### FCFS 단점
- **_convoy effect_:** 긴 작업이 앞에 있으면 짧은 작업이 오래 대기
- **응답 시간 편차:** 첫 작업의 길이에 따라 후속 작업의 대기 시간이 크게 달라짐
- **인터랙티브 부적합:** 실시간 응답이 필요한 작업에 부적합

### 적합한 서비스 유형

| 서비스 유형 | 적합성 | 이유 |
|-------------|--------|------|
| **배치 처리 서비스** | ✅ 적합 | 처리량(throughput)이 중요하고 순서 보장이 필요한 일괄 작업에 적합 |
| **웹 서버 (실시간)** | ❌ 부적합 | 사용자 응답 시간이 중요한 환경에서 convoy effect가 심각한 지연 유발 |
| **로그 처리 파이프라인** | ✅ 적합 | 순서 보장이 중요한 로그/데이터 처리에 적합 |
| **실시간 모니터링** | ❌ 부적합 | 짧은 주기의 센서 데이터 처리에는 우선순위 기반 스케줄링이 더 적합 |

> 본 미션의 `agent-leak-app`은 시스템 상태를 점검하는 모니터링 에이전트로, 순차적 작업 처리가 보장되는 FCFS가 적합한 선택으로 판단된다. 단, 실시간 응답이 요구되는 환경에서는 Round-Robin 또는 Priority 스케줄링으로의 전환을 권장한다.

---

> 📎 첨부 파일: `evidence/deadlock/app_after_MULTI_THREAD_false.log` (Healthy System Monitoring 시나리오)
