# B1-2 재현 가이드

## 1. 목적

현재 저장소의 바이너리를 디컴파일하지 않고 실행 로그, 프로세스 상태, 실제 gdb 백트레이스로 OOM·CPU Spike·Deadlock을 확인한다.

## 2. 권장 환경

- 격리된 x86_64 또는 arm64 Linux
- `bash`, `ps`, `pgrep`, `gdb`
- 실험 중 약 600MB 이상의 여유 메모리
- 15034 포트를 다른 프로세스가 사용하지 않는 환경

CPU에 따라 자동으로 바이너리를 선택한다.

| `uname -m` | 바이너리 |
|---|---|
| `x86_64`, `amd64` | `agent-leak-app-x86` |
| `arm64`, `aarch64` | `agent-leak-app-arm64` |

## 3. 한 번에 전체 검증

Ubuntu/Debian 계열 격리 환경에서:

```bash
sudo apt-get update
sudo apt-get install -y gdb procps psmisc
scripts/run-final-validation.sh
```

스크립트는 다음 순서로 실행한다.

1. OOM Before: Memory 256, CPU 50, Thread false
2. OOM After: Memory 512, CPU 50, Thread false
3. CPU Before: Memory 512, CPU 100, Thread false
4. CPU After: Memory 512, CPU 50, Thread false
5. Deadlock Before: Memory 512, CPU 50, Thread true
6. 실제 `gdb thread apply all bt` 및 5회 프로세스 표본
7. Deadlock After: Memory 512, CPU 50, Thread false

성공 문구:

```text
B1-2 FINAL RUNTIME VALIDATION: ALL PASS
```

증거 위치:

```text
evidence/final-validation/
```

## 4. 실험 변수를 한 개씩 바꾸는 이유

### OOM

| 값 | Before | After |
|---|---:|---:|
| `MEMORY_LIMIT` | 256 | 512 |
| `CPU_MAX_OCCUPY` | 50 | 50 |
| `MULTI_THREAD_ENABLE` | false | false |

OOM 비교에서는 Memory만 바꾼다. CPU를 100으로 설정하면 Memory cleanup 전에 CPU Watchdog이 개입할 수 있으므로 잘못된 비교가 된다.

### CPU

| 값 | Before | After |
|---|---:|---:|
| `MEMORY_LIMIT` | 512 | 512 |
| `CPU_MAX_OCCUPY` | 100 | 50 |
| `MULTI_THREAD_ENABLE` | false | false |

### Deadlock

| 값 | Before | After |
|---|---:|---:|
| `MEMORY_LIMIT` | 512 | 512 |
| `CPU_MAX_OCCUPY` | 50 | 50 |
| `MULTI_THREAD_ENABLE` | true | false |

## 5. 실제 gdb 증거의 해석 범위

현재 바이너리는 stripped ELF이므로 내부 Python 함수명이나 `Shared_Memory_A`, `Socket_Pool_B` 같은 애플리케이션 락 이름이 gdb에 직접 나오지 않는다.

실제 gdb 결과에서 확인할 수 있는 것:

- 프로세스에 스레드 3개가 존재
- 각 스레드에 실제 프레임 `#0` 이후가 존재
- 세 스레드 모두 `PyThread_acquire_lock_timed` 경로에서 대기

프로세스 표본에서 확인할 수 있는 것:

- 세 스레드 모두 `futex_wait_queue`
- CPU와 메모리가 여러 표본 동안 정체
- PID는 계속 존재

애플리케이션 로그에서 확인할 수 있는 것:

- Thread-1이 A를 보유하고 B를 대기
- Thread-2가 B를 보유하고 A를 대기
- 마지막 상태가 `BLOCKED`

따라서 gdb가 락 이름을 직접 보여줬다고 과장하지 않고, **애플리케이션 로그 + 프로세스 표본 + 실제 gdb 백트레이스**를 함께 근거로 사용한다.

## 6. OrbStack VM을 사용하는 경우

현재 CLI 형식:

```bash
orb create ubuntu b1-2-lab -c vm/user-data.yml
orb -m b1-2-lab -u root cloud-init status --wait
```

파일 전송 예:

```bash
orb push -m b1-2-lab agent-leak-app-arm64 /tmp/agent-leak-app
orb -m b1-2-lab -u root install -o agent-admin -g agent-admin -m 0755 \
  /tmp/agent-leak-app /home/agent-admin/agent-app/agent-leak-app
```

OrbStack VM 안에 저장소를 배치한 뒤 `scripts/run-final-validation.sh`를 실행하는 방법이 가장 단순하다.

## 7. 자동 검사 결과

2026-08-16 실행 결과:

```text
oom_before=PASS
oom_after=PASS
cpu_before=PASS
cpu_after=PASS
deadlock_before=PASS
deadlock_gdb_backtrace=PASS
deadlock_after=PASS
B1-2 FINAL RUNTIME VALIDATION: ALL PASS
```

원본: `evidence/final-validation/verification-summary.txt`

## 8. 주의

- 바이너리를 root로 실행하지 않는다. gdb attach에만 `sudo`를 사용한다.
- 디컴파일·리버스 엔지니어링을 하지 않는다.
- 공유 네트워크에서 15034 포트를 외부에 공개하지 않는다.
- 실험 종료 후 `agent-leak-app` 프로세스와 15034 포트가 남지 않았는지 확인한다.
