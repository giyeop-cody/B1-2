# B1-2: 리눅스 프로세스 및 시스템 리소스 트러블슈팅

> Memory Leak, CPU Spike, Deadlock — 시스템 장애 3종을 관제 데이터와 로그로 분석하고 GitHub Issue 형태의 기술 리포트로 작성

## 📌 과제 정보

| 항목 | 내용 |
|------|------|
| **과목** | Linux와 OS |
| **난이도** | ★★☆ (Lv.2) |
| **학습 시간** | 40분 |
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
├── issues/                       # GitHub Issue 리포트
│   ├── issue-1-oom.md            # [Bug] OOM - MemoryGuard 강제 종료
│   ├── issue-2-cpu.md            # [Bug] CPU - Watchdog 보호 조치
│   ├── issue-3-deadlock.md       # [Bug] Deadlock - 교착상태 무응답
│   └── bonus-scheduling.md       # [Analysis] FCFS 스케줄링 추론
├── evidence/                     # 증거 로그 (Before/After)
│   ├── oom/                      # OOM: 3개 로그
│   ├── cpu/                      # CPU: 2개 로그
│   └── deadlock/                 # Deadlock: 2개 로그
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

### VM 프로비저닝 (OrbStack)
```bash
# 1. VM 생성 (cloud-init)
orb create vm --user-data vm/user-data.yml ubuntu:22.04 b1-2-lab

# 2. 바이너리 배치
scp agent-leak-app-x86 agent-admin@<vm-ip>:/home/agent-admin/agent-app/agent-leak-app
ssh agent-admin@<vm-ip> "chmod +x ~/agent-app/agent-leak-app"

# 3. 시나리오 실행 (각 Before/After)
ssh agent-admin@<vm-ip> "~/run-scenario.sh oom before"
ssh agent-admin@<vm-ip> "~/run-scenario.sh cpu after"
# ... 또는 개별 스크립트: vm/run-oom.sh, vm/run-cpu.sh, vm/run-deadlock.sh
```

### 수동 환경 (cloud-init 없이)
```bash
./vm/setup-env.sh
# 바이너리 배치 후
MEMORY_LIMIT=256 ./agent-leak-app-x86  # OOM Before
```

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

## 🚀 실행 방법

### 사전 준비
- Docker 설치, B1-1에서 구성한 Linux 환경

### 시나리오 실행
```bash
# OOM 시나리오
cd vm && MEMORY_LIMIT=256 bash run-scenario.sh oom

# CPU 시나리오
cd vm && CPU_MAX_OCCUPY=80 bash run-scenario.sh cpu

# Deadlock 시나리오
cd vm && MULTI_THREAD_ENABLE=true bash run-scenario.sh deadlock
```

---

## 🧪 테스트 방법

### 장애 재현 + 분석
1. OOM: `MEMORY_LIMIT=256` 실행 → 모니터링 로그에서 RSS 선형 증가 확인 → `MEMORY_LIMIT=512`로 변경 후 Before/After 비교
2. CPU: `CPU_MAX_OCCUPY=80` 실행 → CPU 급상승 + Watchdog SIGTERM 확인 → `CPU_MAX_OCCUPY=50`으로 변경 후 비교
3. Deadlock: `MULTI_THREAD_ENABLE=true` 실행 → PID는 존재하나 무응답 확인 → `false`로 변경 후 해결

### 증거 확인
```bash
# 관제 로그
cat evidence/monitoring.log

# 각 장애별 이슈 리포트
cat issues/issue-1-oom.md
cat issues/issue-2-cpu.md
cat issues/issue-3-deadlock.md
```
