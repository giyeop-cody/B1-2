# B1-2 최종 런타임 검증 보고서

- 실행일: 2026-08-16
- 환경: 격리된 Debian 13, Linux 6.1, x86_64
- 실행 사용자: 일반 사용자 `user`
- gdb: 16.3
- 바이너리: `agent-leak-app-x86` (stripped ELF)
- 자동화: `scripts/run-final-validation.sh`

## 목적

기존 사전평가 18/20에서 남았던 실제 스레드 백트레이스 문제를 해결하고, OOM·CPU·Deadlock을 현재 커밋에서 다시 재현한다.

## 실행 명령

```bash
sudo apt-get install -y gdb procps psmisc
scripts/run-final-validation.sh
```

## 통제 변수

| 실험 | Before | After | 고정한 값 |
|---|---|---|---|
| OOM | Memory=256 | Memory=512 | CPU=50, Thread=false |
| CPU | CPU=100 | CPU=50 | Memory=512, Thread=false |
| Deadlock | Thread=true | Thread=false | Memory=512, CPU=50 |

## 실제 결과

| 시나리오 | 확인한 marker | 판정 |
|---|---|---:|
| OOM Before | `Memory limit exceeded` | PASS |
| OOM After | `MEMORY RECOVERED` | PASS |
| CPU Before | `CPU Threshold Violated` | PASS |
| CPU After | `Cooldown complete` | PASS |
| Deadlock Before | `Status: BLOCKED` | PASS |
| Deadlock gdb | 실제 스레드 3개와 `#0` 이후 프레임 | PASS |
| Deadlock After | `All tasks completed` | PASS |

원본 요약: `evidence/final-validation/verification-summary.txt`

## OOM 분석

Before는 Memory 256에서 Heap이 275MB에 도달해 MemoryGuard가 종료했다. After는 CPU를 50으로 고정한 상태에서 Memory만 512로 높였고, Heap 525MB에서 cleanup과 `MEMORY RECOVERED`를 확인했다.

기존 자동 실행 정의는 OOM After에서도 CPU=100을 사용해 CPU Watchdog이 먼저 개입할 수 있었다. 최종 검증에서는 OOM 비교의 CPU를 50으로 고정해 Memory만 비교했다.

## CPU 분석

Before는 CPU 100에서 부하가 55%대로 올라간 뒤 Watchdog이 종료했다. After는 CPU 50에서 peak 이후 cooldown과 5% 복귀를 확인했다. 기존 `CPU_MAX_OCCUPY_80` 파일명은 실제 내부 설정 100과 달라 100으로 정정했다.

## Deadlock 분석

Before 앱 로그:

- Thread-1: A 보유, B 대기
- Thread-2: B 보유, A 대기
- 두 스레드 모두 `Status: BLOCKED`

5회 표본:

- PID 계속 존재
- 세 스레드 모두 `futex_wait_queue`
- MEM 0.8% 정체
- CPU가 매우 낮은 상태

실제 gdb:

- Thread 1, 2, 3 백트레이스 수집
- 세 스레드 모두 `PyThread_acquire_lock_timed` 경로 포함

After는 멀티스레드를 false로 바꾸자 A→B→C가 순서대로 끝나고 `All tasks completed`를 출력했다.

## 해석의 한계

바이너리가 stripped 상태라 gdb 출력만으로 애플리케이션 락 이름과 내부 함수 이름을 직접 볼 수 없다. 락 이름과 상호 대기는 앱 로그, 실제 lock 대기는 gdb와 `ps -T`로 각각 확인했다. 세 자료를 합쳐 Deadlock으로 판단했다.

## 프로세스 정리

검증 스크립트는 각 시나리오가 끝날 때 프로세스 그룹과 남은 `agent-leak-app`을 종료한다. 최종 확인에서 15034 listen 포트와 앱 프로세스가 남지 않았다.

## 남은 외부 절차

- GitHub 원격 Issue 생성
- branch push와 PR
- 수정 후 외부 사전평가
- 실제 동료평가
- Codyssey 제출 및 공식 평가

외부 절차는 실제 수행 전 PASS로 표시하지 않는다.
