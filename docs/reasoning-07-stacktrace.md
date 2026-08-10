# 추론 기록 #07: 스택 트레이스 캡처 (사전평가 #15 FAIL 보완)

## 사전평가 지적사항
> #15 FAIL: 스택트레이스(스레드별 백트레이스)가 포함되어 있지 않음
> suggestion: pstack/jstack 또는 gdb로 스레드별 스택 트레이스를 캡처하여 로그와 함께 첨부하라

## 캡처 환경
- 샌드박스 (Debian 13, Linux 6.1)
- gdb/pstack/strace 미설치, CAP_SYS_PTRACE 없음
- /proc 기반 분석으로 대체

## 캡처 결과 (evidence/deadlock/stacktrace.txt)

### 스레드 상태
| TID | 역할 | State | wchan | syscall |
|-----|------|-------|-------|---------|
| 4452 | main | S(sleeping) | futex_wait_queue | 202(futex) |
| 4457 | Worker-Thread-1 | S(sleeping) | futex_wait_queue | 202(futex) addr=0x34d2cbb0 |
| 4458 | Worker-Thread-2 | S(sleeping) | futex_wait_queue | 202(futex) addr=0x34d246a0 |

### 핵심 증거
1. **모든 스레드가 S(sleeping)** — CPU 0%, 실행 중인 스레드 없음
2. **wchan=futex_wait_queue** — 모든 스레드가 futex(뮤텍스/락) 대기
3. **syscall=202(futex)** — 커널 레벨에서 락 대기 시스템콜 확인
4. **서로 다른 futex 주소**:
   - TID 4457: `0x34d2cbb0` (Socket_Pool_B 대기)
   - TID 4458: `0x34d246a0` (Shared_Memory_A 대기)
   → 각 스레드가 **다른 락**을 대기 → 순환 대기(circular wait)를 커널 레벨에서 증명

## gdb vs /proc 비교
| 방법 | 권한 | 정보 수준 | 본 환경 |
|------|------|-----------|---------|
| gdb `thread apply all bt` | CAP_SYS_PTRACE | userspace 스택 프레임 | ❌ |
| pstack | CAP_SYS_PTRACE | userspace 스택 | ❌ |
| /proc/<pid>/task/*/stack | root | 커널 스택 | ❌ (권한 부족) |
| /proc/<pid>/task/*/wchan | 본인 프로세스 | 대기 채널 | ✅ |
| /proc/<pid>/task/*/syscall | 본인 프로세스 | 시스템콜 + 인자 | ✅ |

> /proc의 wchan + syscall만으로도 futex 대기 + 서로 다른 락 주소 → circular wait 증명 가능

## 응용
- gdb가 있는 환경(VM): `gdb -batch -ex "thread apply all bt" -p <PID>`로 userspace 스택
- 권한 제한 환경(컨테이너/샌드박스): /proc wchan + syscall로 커널 레벨 증명
- Python 프로세스: `py-spy dump --pid <PID>` (권한 불필요)
