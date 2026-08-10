# B1-2: 컴퓨터가 갑자기 느려지거나 멈췄을 때 원인 찾아 고치기

## 📋 과제 정보

| 항목 | 내용 |
|------|------|
| **과목** | Linux와 OS (Linux & OS) |
| **난이도** | ★★☆ (Lv.2) |
| **학습 시간** | 40분 |
| **필수 여부** | ✅ 필수 |
| **진행 상태** | 평가전 |
| **과제 번호** | 185005 |

---

## 🎯 미션 소개

Memory Leak, CPU Spike, Deadlock. 이 세 가지 중 하나가 실서버에서 터지면 어떻게 해야 할까요? 로그 없이 재부팅부터 하면 원인이 묻히고, 같은 장애가 두 번, 세 번 반복됩니다. 관제 데이터를 근거로 원인을 추론하고, GitHub Issue 형태의 기술 리포트로 남기는 것까지 직접 해봅니다.

개발자가 작성한 코드는 운영체제 위에서 프로세스 형태로 실행됩니다. 이 미션에서는 빌드된 프로그램을 운영 환경에서 실행하며 발생하는 시스템 장애(Memory Leak/OOM, CPU Spike, Deadlock) 분석을 다룹니다.

단순히 "프로그램이 꺼졌다!"는 결과만 보는 것이 아니라, 관제 데이터와 로그를 통해 장애의 원인을 추론해야 합니다. 이를 바탕으로 현업 개발자처럼 GitHub Issue 형태의 기술 리포트를 작성하며 실전적인 트러블슈팅 및 협업 커뮤니케이션 역량을 기르는 것이 최종 목표입니다.

![미션 설명 이미지](mission.jpg)

---

## 🎓 학습 목표

이 미션을 완료한 뒤, 학습자는 아래를 스스로 설명할 수 있어야 한다:

- 메모리 구조를 이해하고, 메모리 누수가 시스템 전체에 미치는 영향을 설명할 수 있다
- 특정 프로세스의 CPU 과점유가 시스템 지연을 유발하는 원리를 설명할 수 있다
- 자원 경쟁으로 인해 발생하는 교착상태(Deadlock)의 개념을 이해하고, 프로세스가 멈춘 상태를 시스템 도구로 식별하여 진단할 수 있다
- 로그와 관제 데이터를 증거로 제시하여 육하원칙에 맞게 장애 상황을 기술하고, GitHub Issue를 통해 동료 개발자와 명확하게 소통할 수 있다

---

## 📦 최종 결과물

PDF 또는 GitHub Repository 링크 형태로 제출:

### 1. 시스템 장애 분석 및 이슈 리포트 (3건)
- 3가지 장애 유형(OOM Crash, CPU Latency, Deadlock) 각각에 대해 작성된 GitHub Issue 형태의 기술 보고서
- 각 리포트 필수 포함 항목:
    - 발생 현상: 장애가 어떻게 관측되었는지 서술
    - 재현 경로 및 증거: 로그/명령어 출력/스크린샷 등 객관적 증거 첨부
    - 근본 원인: 장애의 기술적 원인 분석
    - 조치 내용: 환경변수 조정 등 임시 조치와 그 결과
    - 결과 확인: 조치 후 Before & After 비교 결과

### 2. 이슈 리포트 마크다운 템플릿
```css
[Bug] {장애 유형} - {한 줄 요약}

## 1. Description (현상 설명)
## 2. Evidence & Logs (증거 자료)
## 3. Root Cause Analysis (원인 분석)
## 4. Workaround & Verification (조치 및 검증)
```

### 3. 케이스별 필수 증거 최소 요건
- **OOM**: monitor.sh 결과(메모리 상승 수치), 종료 로그("Memory limit exceeded…"), MEMORY_LIMIT 변경 전후 비교(최소 2회)
- **CPU**: CPU 급상승 구간 캡처, 종료 로그("WATCHDOG… SIGTERM"), CPU_MAX_OCCUPY 변경 전후 비교
- **Deadlock**: PID 존재 증거(ps -ef), CPU/MEM 정체 증거(top -H), 마지막 로그("WAITING… BLOCKED"), 스레드/락 대기 추론 근거

---

## ✅ 기능 요구사항

### 1. 사전 준비 사항
agent-leak-app 실행 조건:

|항목|조건|
|------|------|
|실행 계정|root가 아닌 일반 사용자|
|AGENT_HOME|필수 환경변수 설정|
|AGENT_PORT|15034 (고정)|
|AGENT_UPLOAD_DIR|$AGENT_HOME/upload_files (디렉터리 존재 필수)|
|AGENT_KEY_PATH|$AGENT_HOME/api_keys (경로 존재 필수)|
|AGENT_LOG_DIR|로그 디렉터리 (존재 + 쓰기 권한)|
|MEMORY_LIMIT|정수, 50~512 범위 (단위: MB)|
|CPU_MAX_OCCUPY|정수, 10~100 범위 (단위: %)|
|MULTI_THREAD_ENABLE|true/false (1/0, yes/no 허용)|
|secret.key 파일|$AGENT_HOME/api_keys/secret.key 존재, 내용: agent_api_key_test|
|네트워크|0.0.0.0:15034 바인딩 가능|

### 2. 메모리 누수 원인 규명 및 리포팅
- monitor.sh로 물리 메모리 사용량 증가 패턴 관측
- MemoryGuard 강제 종료 핵심 로그 식별
- MEMORY_LIMIT 조정 → Before & After 기록

### 3. CPU 과점유 분석 및 리포팅
- 특정 프로세스 CPU 급상승 구간 식별
- Watchdog 보호 조치 로그 입증
- CPU_MAX_OCCUPY 조정 → Before & After 기록

### 4. 교착상태(DeadLock) 진단 및 리포팅
- PID 존재 + 무응답 상태 식별
- 스레드 간 순환 대기 상태 논리적 증명
- MULTI_THREAD_ENABLE 조정 → 재현/회피 비교

### 5. 보너스 (선택): 스케줄링 알고리즘 추론
- 로그 타임스탬프 기반 실행 순서 패턴화
- Round-Robin, FCFS, Priority 중 추론
- 장단점 및 적합한 아키텍처 분석

---

## 🛠️ 개발 환경

- 제공된 바이너리(Python 기반)를 실행할 수 있는 리눅스 환경
- 로컬 또는 격리된 환경(Docker 컨테이너 등)에서 실행 권장
- 공유 네트워크 환경에서는 방화벽 설정에 유의
- 바이너리 디컴파일 및 리버스 엔지니어링 시도 금지

---

## ⚠️ 제약 사항

- `monitor.sh`, `ps`, `top`, `htop`, `pstree`, `kill` 등 리눅스 표준 명령어 및 라이브러리 사용

---

## 📦 제공 파일

- agent-app-leak-x86 (Intel chip)
- agent-app-leak-arm64 (Apple chip)

---

## 📝 결과 예시

아래는 정답이 아니라 참고 예시다. 실제 문구와 디자인은 달라도 된다.

### 커밋 메시지 자동 생성 예시 (OOM Case)
```css
[Bug] 프로세스 실행 10분 후 메모리 보호 정책에 의한 비정상 강제 종료

## 1. Description (현상 설명)
`agent-leak-app` 실행 후 약 10분 경과 시 SELF-TERMINATED 메시지 출력 후 종료

## 2. Evidence & Logs (증거 자료)
monitor.sh 관제 로그: MEM 5.1% → 96.8% 선형 증가
[CRITICAL] [MemoryGuard] Memory limit exceeded (256MB >= 256MB)

## 3. Root Cause Analysis (원인 분석)
힙 메모리 해제 없이 지속 할당 → MemoryGuard SIGKILL

## 4. Workaround & Verification (조치 및 검증)
MEMORY_LIMIT 256→512 상향 → 30분+ 생존 확인
```

> 상세 결과 예시는 과제 가이드 원문(B1-2.md) 참조

---

## 📊 평가 정보

- 평가 대상: 예

---

> *이 문서는 Codyssey AI/SW 기초 과정의 과제 내용을 기반으로 작성되었습니다.*
