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
| CPU | 워커의 짧은 CPU 피크 98.809%, 임계값 위반 후 자기 SIGTERM 확인 | CPU_MAX_OCCUPY 100 → 50: 약 27초 종료 → 170초 생존 | [CPU 분석](issues/issue-2-cpu.md) |
| Deadlock | MULTI_THREAD_ENABLE=true: BLOCKED 상태 지속 | false: 170초 생존 | [Deadlock 분석](issues/issue-3-deadlock.md) |
| 보너스 | 앱 setpriority(nice=10), 실제 sched_switch/wakeup 수집 | 동일 CPU nice 0/10 대조군 90.24%/9.67%, 우선순위 가중 공정 스케줄링 추론 | [스케줄링 분석](issues/bonus-scheduling.md) |

생존 시간은 관측 창 안에서의 결과다. 장기 안정성이나 근본 해결을 입증하지 않는다.
CPU의 내부 Load와 OS 사용률은 구별한다. 추가 20ms 측정으로 프로세스의 짧은 급상승을
확보하고 strace로 보호 정책의 자기 SIGTERM을 확인했다.

- [taskmap 원문 사본](docs/mission.md) · [전체 요구사항·제출물 대조표](eval/requirements.md)
- [평가 진행 안내](eval/README.md) · [21문항 답변과 증거](eval/answers.md)

## 증거와 재현

- [실험 전체 로그](evidence/phase2.log): 배치 → 실험 6종 → 보너스 → B1-1 원복.
- [증거 목록과 SHA-256](evidence/manifest.json): 이번 실행 원본 30개.
- [추가 실험 증거 목록](evidence/supplemental-manifest.json): 고해상도 CPU·SIGTERM·커널 전환·우선순위 대조·최종 원복.
- [원복 후 검증](evidence/30-restore-b1-1.txt): **PASS=36 FAIL=0**.
- [재현 절차와 측정 해석](docs/reproduction.md).
- [증거 검사기](scripts/check-evidence.py): 해시, 변수 통제, 종료·생존 마커 검사.

```bash
python3 scripts/check-evidence.py
```

기존 B1-2 문서·평가 기록·이전 실증 자료는 현재 트리에서 제거했다.
이 README와 보고서는 이번 OrbStack 실행만 설명한다. 외부 동료평가와 공식 평가는 미실시다.
