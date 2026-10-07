# [Analysis] 로그·커널 전환·우선순위 대조를 통한 스케줄링 추론

## 1. 로그 관찰 개요

2026-10-07 OrbStack에서 정상 설정(CPU_MAX_OCCUPY=50)으로 실행했다.
최초 12초 CPU 측정에 더해 23:07에 정상 앱 로그와 45초 커널 sched_switch/sched_wakeup을
수집하고, 같은 CPU에 고정한 nice 0/10 대조 작업을 12초 비교했다.
제공 바이너리나 실제 앱 스레드의 스케줄링 정책은 변경하지 않았다.

## 2. 증거 자료

- 스레드 정책: SCHED_OTHER, 우선순위 0, nice=10.
- /proc 기반 OS 프로세스 CPU: 28틱 / 12.004초, **2.33%**.
- 단일 busy-loop 대조군: **100.17%**. 표본·시간 측정의 오차가 포함된다.
- 워커 syscall 표본: 270=pselect6. 자발적 컨텍스트 스위치가 비자발적 스위치보다 많다.
- 앱 로그: 내부 Load 상승, 50% peak, cooldown 패턴. OS 사용률과 수치가 다르다.

추가 증거:

- [앱 우선순위 설정](../evidence/policy-scheduling/signals.17834): `setpriority(PRIO_PROCESS, 0, 10) = 0`.
- [실제 정책/스레드 상태](../evidence/policy-scheduling/policies.txt): 부모 nice=0,
  앱 워커 nice=10, SCHED_OTHER. 스레드별 /proc/sched 통계도 포함.
- [정상 로그](../evidence/policy-scheduling/normal-app.log): MemoryWorker와 CpuWorker 출력이
  서로 끼어들며 계속 진행한다. 한 작업을 끝까지 실행하는 FCFS 패턴이 아니다.
- [간격 계산](../evidence/policy-scheduling/log-pattern.json): MemoryWorker 평균 3.0549초,
  CpuWorker 평균 3.1204초. 두 주기가 다르고 점차 상대 시점이 달라진다.
- [커널 전환 원본](../evidence/policy-scheduling/sched-trace.txt): 283개 이벤트,
  entries-written=entries-in-buffer로 수집 버퍼 유실 없음. wakeup 이후 실행되고 S/D 대기로
  전환한다. 로그의 약 3초 주기는 커널 고정 quantum이 아니라 앱의 작업·대기 주기다.
  trace의 PID는 커널 PID 네임스페이스 기준이며 VM의 ps PID와 숫자가 다를 수 있다.
- [우선순위 대조](../evidence/policy-scheduling/priority-control.json): 같은 CPU·같은 작업에서
  nice 0은 90.24%, nice 10은 9.67%, CPU 시간 배분 비율은 9.336:1이다.
  이 두 포화 작업은 앱과 구별되는 **스케줄러 대조군**이다.

## 3. 패턴 분석 및 결론

**미션의 세 선택지 중 Priority 계열, 정확히는 nice 우선순위를 가중치로 반영하는
공정 시분할 스케줄링으로 추론한다.** 근거는 앱의 nice=10 설정, 정상 정책 SCHED_OTHER,
실행/대기 전환, 동일 CPU 포화 대조군의 비대칭 배분이다.

FCFS처럼 작업 하나가 완전히 끝날 때까지 다른 작업이 기다리는 구조가 아니다.
SCHED_RR도 아니며 동일 quantum의 순환을 로그 간격만으로 주장하지 않는다.
여기서 Priority는 실시간 고정 우선순위가 CPU를 무조건 독점하는 방식과 구별되는
**우선순위 가중 공정 배분**이다. 따라서 실제 Linux 정책의 정확한 이름을 함께 제시한다.
공식 문서도 nice에 따른 상대 CPU 배분과 SCHED_OTHER/SCHED_RR의 차이를 설명한다.
[Linux Scheduler Nice Design](https://docs.kernel.org/scheduler/sched-nice-design.html),
[Linux sched(7)](https://www.man7.org/linux/man-pages/man7/sched.7.html).

## 4. 장단점과 서비스 적용

우선순위 가중 공정 배분은 여러 서비스가 공존할 때 중요 작업에 더 많은 CPU 몫을 주면서
낮은 우선순위 작업도 진행시키는 장점이 있다. 고정된 응답 시간 상한을 보장하지는 않는다.
웹 서버·대화형 서비스와 배치가 공존할 때 웹 작업의 우선순위를 높이고 배치의 nice를
높이는 구성이 적합하다. 강한 실시간 응답 보장이 필요한 제어 시스템에는 별도 실시간
정책·실행 예산 설계가 필요하다. 이 서비스 배치 방식은 측정 결과에 기반한 설계 제안이다.
