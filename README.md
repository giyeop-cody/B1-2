# B1-2: 리눅스 프로세스 및 시스템 리소스 트러블슈팅

> Memory Leak, CPU Spike, Deadlock — 시스템 장애 3종을 관제 데이터와 로그로 분석하고 GitHub Issue 형태의 기술 리포트로 작성

## 📌 과제 정보

| 항목 | 내용 |
|------|------|
| **과목** | Linux와 OS |
| **난이도** | ★★☆ (Lv.2) |
| **학습 시간** | 40시간 |
| **필수 여부** | ✅ 필수 |
| **과제 번호** | 185005 |
| **실행 환경** | OrbStack Linux VM + cloud-init |

## 🎯 프로젝트 개요

Memory Leak, CPU Spike, Deadlock. 이 세 가지 중 하나가 실서버에서 터지면 어떻게 해야 할까요? 관제 데이터를 근거로 원인을 추론하고, GitHub Issue 형태의 기술 리포트로 남기는 것까지 직접 해봅니다.

## 🎓 학습 목표

이 과제를 완료한 뒤, 다음을 설명할 수 있어야 한다:

1. 메모리 구조를 이해하고, 메모리 누수가 시스템 전체에 미치는 영향을 설명할 수 있다
2. 특정 프로세스의 CPU 과점유가 시스템 지연을 유발하는 원리를 설명할 수 있다
3. 교착상태(Deadlock)의 개념을 이해하고, 프로세스가 멈춘 상태를 시스템 도구로 식별하여 진단할 수 있다
4. 로그와 관제 데이터를 증거로 제시하여 육하원칙에 맞게 장애 상황을 기술하고, GitHub Issue를 통해 동료 개발자와 명확하게 소통할 수 있다

## ⚠️ 제약 사항

- monitor.sh, ps, top, htop, pstree, kill 등 리눅스 표준 명령어 및 라이브러리 사용
- 바이너리 디컴파일 및 리버스 엔지니어링 시도 금지


---

## 🏗️ 접근 방법

**컨테이너가 아닌 VM을 선택한 이유**: B1-2의 본질은 시스템 자원 관측(OOM/CPU/deadlock)이다. 컨테이너는 host 커널을 공유하여 `ps`/`top`/`/proc/meminfo`가 host 기준 수치를 보이지만, VM은 격리된 커널을 가지므로 관측이 깔끔하다. cloud-init으로 프로비저닝하면 "운영 서버에 에이전트 배포 후 장애 관측" 시나리오에 가장 근사한다.

> 상세 비교는 [docs/reasoning-00-approach.md](docs/reasoning-00-approach.md) 참조

---

## 📂 산출물 구조

```
B1-2/
├── vm/                           # VM 프로비저닝 + 시나리오 스크립트
│   ├── user-data.yml             # cloud-init (OrbStack VM)
│   ├── setup-env.sh              # 수동 환경 구성 (cloud-init 대체)
│   ├── monitor.sh                # 프로세스 관제 스크립트
│   ├── run-oom.sh                # OOM 시나리오 재현
│   ├── run-cpu.sh                # CPU 시나리오 재현
│   └── run-deadlock.sh           # Deadlock 시나리오 재현
├── scripts/
│   ├── run-final-validation.sh   # 6개 시나리오 + 실제 gdb 자동 수집
│   └── check-final-validation.sh # 증거·통제 변수·프로세스 정리 검사
├── issues/                       # GitHub Issue 리포트
│   ├── issue-1-oom.md            # [Bug] OOM - MemoryGuard 강제 종료
│   ├── issue-2-cpu.md            # [Bug] CPU - Watchdog 보호 조치
│   ├── issue-3-deadlock.md       # [Bug] Deadlock - 교착상태 무응답
│   └── bonus-scheduling.md       # [Analysis] FCFS 스케줄링 추론
├── evidence/                     # 증거 로그 (Before/After)
│   ├── oom/                      # 기존 OOM 증거
│   ├── cpu/                      # 기존 CPU 증거
│   ├── deadlock/                 # 기존 Deadlock 증거
│   └── final-validation/         # 최신 6개 실행·관제·실제 gdb 증거
├── docs/                         # 추론 과정 기록
│   ├── reasoning-00-approach.md  # 컨테이너 vs VM 선정
│   ├── reasoning-01-monitoring.md# 관제 스크립트 설계
│   ├── reasoning-02-oom.md       # OOM 분석 추론
│   ├── reasoning-03-cpu.md       # CPU 분석 추론
│   ├── reasoning-04-deadlock.md  # Deadlock 분석 추론
│   ├── reasoning-05-scheduling.md# 스케줄링 추론 (보너스)
│   └── reproducibility.md        # 전체 재현 가이드
├── QUEST.md                      # 과제 설명
├── B1-2.md                       # 원본 과제 가이드
└── mission.jpg                   # 미션 설명 이미지
```

---

## 🔍 장애 분석 요약

### Case 1: OOM (Memory Leak)
| | Before | After |
|--|--------|-------|
| **환경변수** | `MEMORY_LIMIT=256` | `MEMORY_LIMIT=512` |
| **결과** | 30초 후 MemoryGuard 강제 종료 | 60초+ 정상 (자체 cleanup) |
| **Heap** | 275MB 크래시 | 525MB → cleanup → 25MB 리셋 |

### Case 2: CPU Spike
| | Before | After |
|--|--------|-------|
| **환경변수** | `CPU_MAX_OCCUPY=100` | `CPU_MAX_OCCUPY=50` |
| **결과** | 37초 후 Watchdog 강제 종료 | 50% cooldown, 정상 동작 |
| **CPU** | 55.73% 크래시 | 50% → cooldown → 5% 재상승 |

### Case 3: Deadlock
| | Before | After |
|--|--------|-------|
| **환경변수** | `MULTI_THREAD_ENABLE=true` | `MULTI_THREAD_ENABLE=false` |
| **결과** | 두 스레드 BLOCKED, 무응답 | 순차 실행, 정상 동작 |
| **진단** | PID 존재 + CPU/MEM 정체 + 로그 중단 | 교착상태 없음 |

### Bonus: FCFS 스케줄링 추론
Thread-A → B → C 순차 실행 (비선점, 등록 순서) → FCFS

---

## 🚀 재현 방법

### 권장: 격리된 Linux에서 전체 자동 검증

`gdb`, `ps`, `bash`가 있는 격리된 Linux에서 실행한다. 스크립트가 CPU 종류에 맞는 바이너리를 고르고 OOM·CPU·Deadlock 6개 시나리오와 실제 gdb 백트레이스를 순서대로 수집한다.

```bash
sudo apt-get update
sudo apt-get install -y gdb procps psmisc
scripts/run-final-validation.sh
```

성공 문구:

```text
B1-2 FINAL RUNTIME VALIDATION: ALL PASS
```

새 증거는 `evidence/final-validation/`에 저장된다. 실행 후 증거와 프로세스 정리를 다시 검사한다.

```bash
scripts/check-final-validation.sh
```

```text
B1-2 FINAL EVIDENCE CHECK: ALL PASS
```

### OrbStack VM 생성

현재 OrbStack CLI 형식은 다음과 같다.

```bash
orb create ubuntu b1-2-lab -c vm/user-data.yml
orb -m b1-2-lab -u root cloud-init status --wait
```

Apple Silicon은 `agent-leak-app-arm64`, Intel은 `agent-leak-app-x86`을 사용한다. 파일 전송은 `orb push`, 회수는 `orb pull`을 사용한다.

> 상세 재현 가이드: [docs/reproducibility.md](docs/reproducibility.md)

---

## 🌿 Git 브랜치 구조

| 브랜치 | 목적 | 산출물 |
|--------|------|--------|
| `setup/vm-provisioning` | VM 환경 구축 | cloud-init, setup-env.sh |
| `tooling/monitoring` | 관제 도구 | monitor.sh |
| `analysis/oom` | OOM 분석 | evidence + issue + run script |
| `analysis/cpu` | CPU 분석 | evidence + issue + run script |
| `analysis/deadlock` | Deadlock 분석 | evidence + issue + run script |
| `analysis/bonus-scheduling` | 보너스 | scheduling 추론 |
| `docs/readme` | 문서 정리 | README + 재현 가이드 |

---

> *Codyssey AI/SW 기초 B1-2 과제 산출물*

---

## ✅ 2026-08-16 최종 런타임 검증

격리된 x86_64 Linux에서 현재 커밋의 자동 검증 스크립트를 실행했다.

| 시나리오 | 통제 조건 | 실제 결과 |
|---|---|---|
| OOM Before | CPU=50, Thread=false, Memory=256 | MemoryGuard 종료 PASS |
| OOM After | CPU=50, Thread=false, Memory=512 | 525MB cleanup 후 복구 PASS |
| CPU Before | Memory=512, Thread=false, CPU=100 | Watchdog 종료 PASS |
| CPU After | Memory=512, Thread=false, CPU=50 | cooldown 후 복구 PASS |
| Deadlock Before | Memory=512, CPU=50, Thread=true | BLOCKED·futex 대기·실제 gdb backtrace PASS |
| Deadlock After | Memory=512, CPU=50, Thread=false | A→B→C 작업 완료 PASS |

검증 요약:

```text
B1-2 FINAL RUNTIME VALIDATION: ALL PASS
```

핵심 증거:

- `evidence/final-validation/verification-summary.txt`
- `evidence/final-validation/deadlock-before-gdb-stacktrace.txt`
- `evidence/final-validation/deadlock-before-process-samples.txt`
- `evidence/final-validation/*-app.log`
- `evidence/final-validation/*-monitor.log`

실제 gdb 출력은 바이너리가 stripped 상태이므로 애플리케이션 내부 함수·락 이름을 직접 보여주지 않는다. 대신 세 스레드 모두 `PyThread_acquire_lock_timed` 경로에서 대기함을 확인했고, 애플리케이션 로그의 두 락 대기 기록과 함께 Deadlock을 판단했다.

## 증거와 보고서 확인

```bash
cat evidence/final-validation/verification-summary.txt
cat evidence/final-validation/deadlock-before-gdb-stacktrace.txt
cat issues/issue-1-oom.md
cat issues/issue-2-cpu.md
cat issues/issue-3-deadlock.md
```
