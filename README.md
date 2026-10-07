# B1-2 — OrbStack에서 수행한 장애 분석 과제

2026-10-07 KST에 **B1-1을 구축한 같은 Linux 머신**에서 앱을 `agent-leak-app`으로
교체하고 OOM·CPU·Deadlock을 재현했다. 각 실험에서 환경변수 하나만 조정해
변경 전후를 비교하고, 로그·관제·프로세스·스레드 스택으로 원인을 분석했다.

## 수행 환경

| 항목 | 실제 실행값 |
|---|---|
| 가상화 | OrbStack, 머신 `b1-lab` |
| OS / 아키텍처 | Ubuntu 24.04.5 LTS / amd64 |
| 커널 | `6.17.8-orbstack-00308-g8f9c941121b1` |
| 실행 계정 / 포트 | `agent-admin` / TCP 15034 |
| 선행 환경 | B1-1 계정·그룹·ACL·SSH 20022·UFW·cron·로그 구조 재사용 |
| 바이너리 입력 | `giyeop-cody/B1-2@7de53d7`의 `agent-leak-app-x86` |

## 결과와 제출물

| 과제 | 변경 전 | 변경 후 | 보고서 |
|---|---|---|---|
| OOM | MEMORY_LIMIT=256: Heap 275MB에서 자기 종료 | 512: 170초 생존 | [OOM 분석](issues/issue-1-oom.md) |
| CPU | CPU_MAX_OCCUPY=100: 내부 Load 54.76%에서 자기 종료 | 50: 170초 생존 | [CPU 분석](issues/issue-2-cpu.md) |
| Deadlock | MULTI_THREAD_ENABLE=true: BLOCKED 상태 지속 | false: 170초 생존 | [Deadlock 분석](issues/issue-3-deadlock.md) |
| 보너스 | SCHED_OTHER / nice=10, OS CPU 2.33% | 대조군 busy-loop 100.17% | [스케줄링 분석](issues/bonus-scheduling.md) |

생존 시간은 관측 창 안에서의 결과다. 장기 안정성이나 근본 해결을 입증하지 않는다.
CPU 실험의 내부 Load는 OS 실측 CPU 사용률과 다르다. 미션의 CPU 과점유 예시와
실제 바이너리 동작의 차이를 [CPU 보고서](issues/issue-2-cpu.md)에 명시했다.

## 증거와 재현

- [실험 전체 로그](evidence/phase2.log): 배치 → 실험 6종 → 보너스 → B1-1 원복.
- [증거 목록과 SHA-256](evidence/manifest.json): 이번 실행 원본 30개.
- [원복 후 검증](evidence/30-restore-b1-1.txt): **PASS=36 FAIL=0**.
- [재현 절차와 검증 한계](docs/reproduction.md).
- [증거 검사기](scripts/check-evidence.py): 해시, 변수 통제, 종료·생존 마커 검사.

```bash
python3 scripts/check-evidence.py
```

기존 B1-2 문서·평가 기록·이전 실증 자료는 현재 트리에서 제거했다.
이 README와 보고서는 이번 OrbStack 실행만 설명한다. 외부 동료평가와 공식 평가는 미실시다.
