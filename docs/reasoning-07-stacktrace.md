# 추론 기록 #07: 실제 gdb 스택 트레이스

## 사전평가 지적

> #15 FAIL: 스레드별 백트레이스가 포함되어 있지 않음. pstack 또는 gdb로 캡처해 첨부할 것.

기존에는 권한과 도구가 없어 `/proc`의 `wchan`, `syscall`만 수집했다. 이는 락 대기의 강한 증거지만 평가자가 요구한 사용자 영역 스택 프레임은 아니었다.

## 2026-08-16 보완 환경

- Debian 13 기반 격리 Linux
- Linux 6.1, x86_64
- gdb 16.3
- 바이너리: `agent-leak-app-x86` (stripped ELF)
- 실행 사용자는 일반 사용자
- gdb attach에만 `sudo` 사용

## 재현 조건

```text
MEMORY_LIMIT=512
CPU_MAX_OCCUPY=50
MULTI_THREAD_ENABLE=true
```

애플리케이션 로그에서 다음 순서를 확인한 뒤 PID에 attach했다.

1. Thread-1이 `Shared_Memory_A` 획득
2. Thread-2가 `Socket_Pool_B` 획득
3. Thread-1이 B를 기다리며 BLOCKED
4. Thread-2가 A를 기다리며 BLOCKED

## 실제 캡처

```bash
sudo vm/capture-stacktrace.sh \
  <PID> \
  evidence/final-validation/deadlock-before-gdb-stacktrace.txt
```

실제 결과:

- PID 4649에 스레드 3개
- Thread 1, 2, 3 모두 실제 `#0` 이후 스택 프레임 존재
- 세 스레드 모두 `PyThread_acquire_lock_timed` 경로 포함
- attach 종료 후 프로세스에서 정상 detach

실제 증거:

- `evidence/final-validation/deadlock-before-gdb-stacktrace.txt`
- `evidence/final-validation/deadlock-before-process-samples.txt`
- `evidence/final-validation/deadlock-before-app.log`

## 5회 프로세스 표본

2초 간격 5회 표본에서 PID는 계속 존재하고 세 스레드의 `WCHAN`이 모두 `futex_wait_queue`였다. CPU는 약 0.3%에서 0.1%로 낮은 상태이고 메모리는 0.8%로 유지됐다.

## 무엇을 증명하고 무엇은 증명하지 못하는가

### 직접 확인한 것

1. 프로세스와 세 스레드가 살아 있다.
2. 세 스레드가 futex/lock 대기 상태다.
3. 실제 gdb 사용자 영역 스택에 Python lock 획득 경로가 있다.
4. 애플리케이션 로그가 A/B 락의 상호 대기를 기록했다.

### gdb만으로 직접 확인하지 못한 것

바이너리가 stripped 상태이므로 gdb 출력에는 다음 이름이 직접 나오지 않는다.

- `Shared_Memory_A`
- `Socket_Pool_B`
- 애플리케이션 내부 Python 함수명

따라서 “gdb가 각 락 이름과 소유자를 직접 증명했다”고 작성하면 과장이다. 정확한 결론은 다음 세 증거를 결합해 얻는다.

```text
애플리케이션 로그의 상호 대기
+ 5회 ps 표본의 futex_wait_queue 정체
+ 실제 gdb의 PyThread_acquire_lock_timed 스택
= Deadlock 판단
```

## 이전 `/proc` 증거와의 관계

기존 `evidence/deadlock/stacktrace.txt`는 과거 실행 기록으로 보존한다. 최종 평가는 실제 gdb 결과인 `evidence/final-validation/deadlock-before-gdb-stacktrace.txt`를 우선 근거로 사용한다.
