# OrbStack 제출용 실증 기록

2026-10-07 KST, Ubuntu 24.04.5 amd64 `b1-lab`에서 B1-1을 구축하고 같은 머신에서
B1-2 장애 실험 6종과 보너스 측정을 수행한 뒤 B1-1로 원복했다.
이 폴더의 30개 증거는 이번 실행 결과만 선별했다. 파일별 SHA-256은 `manifest.json`이다.

## B1-1

최종 `evidence/verification.txt`: **PASS=36 FAIL=0**.
`b1-run.log`의 cron 관측: **+2줄 / 125초**. 실제 10MB 로그를 12회 회전하고
gzip 회전본 10개 유지와 무결성을 확인했다. SSH 20022 및 앱 15034가 리슨하며
22 리스너는 없다. UFW active, incoming deny, 두 포트만 허용한다.
초기 전체 실행 로그에는 검증기 수정 전 FAIL=1이 남아 있다. 당시 실패는
샌드박스 예외 포트 49983을 요구하던 조건이며 최종 검증 및 원복 검증으로 해결을 확인했다.

## 장애 보고서

| 이슈 | 설정 변경 | 이번 실행의 증거와 결과 |
|---|---|---|
| OOM | MEMORY_LIMIT 256 → 512 | `b1-2/evidence/oom/app_before.log`: Heap 275MB에서 MemoryGuard 자기 종료. after metadata: 170초 생존. 앱 내부 메모리 보호 종료이며 커널 OOM kill로 판정하지 않는다. |
| CPU | CPU_MAX_OCCUPY 100 → 50 | `b1-2/evidence/cpu/app_before.log`: 앱 내부 Load 54.76%에서 임계값 위반 종료. after metadata: 170초 생존. 이 수치는 OS CPU 사용률과 구별한다. |
| Deadlock | MULTI_THREAD_ENABLE true → false | `b1-2/evidence/deadlock/app_before.log`: 두 스레드의 자원 교차 요청 및 BLOCKED. stacktrace: 4스레드 중 3 futex 대기, gdb 사용자 영역 스택 확보. before는 관측 후 강제 종료, after는 170초 생존. 락 주소 소유 관계까지 직접 증명한 것은 아니다. |

각 실험의 변수, 시각, PID, 결과는 해당 `metadata_before/after.txt`에 있다.
이번 결과는 관측 창 안에서의 회피 성공이며 영구 해결이나 장기 안정성을 입증하지 않는다.

## 보너스 측정

`b1-2/evidence/40-scheduling-probe.txt`: OrbStack 커널 6.17.8,
워커 스레드는 SCHED_OTHER, nice=10. 12초 측정에서 앱의 OS CPU 사용률은 **2.33%**,
단일 busy-loop 대조군은 **100.17%**(표본·시간 측정 오차 포함)였다.
워커 syscall 표본은 pselect6 대기이며 앱의 내부 Load와 OS 사용률이 일치하지 않는다.
SCHED_OTHER 관측만으로 커널 구현 알고리즘을 CFS로 확정하지 않는다.

## 최종 상태

`b1-2/evidence/30-restore-b1-1.txt`: 원복 후 **PASS=36 FAIL=0**.
SSH는 이후 systemd 서비스 enabled/active로 전환하고 36개 항목을 다시 통과했다.
IPv6 방화벽과 UFW 로깅은 꺼진 상태이며 미검증이다. 외부 동료평가·공식 평가는 미실시다.
