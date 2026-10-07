# taskmap B1-2 요구사항·제출목록 대조

기준: [taskmap 원문 사본](../docs/mission.md), 원본 과제 번호 185005.
2026-10-07 최초 실험과 23:02–23:08 추가 실험을 합쳐 요구사항을 수행했다.
아래 “완료”는 요구된 수행·측정·보고서 제출물의 완료이며 공식 평가 합격을 뜻하지 않는다.

## 최종 제출물

| 원문 제출 목록 | 제출 위치 | 상태 |
|---|---|---|
| 시스템 장애 분석 및 이슈 리포트 3건 | [OOM](../issues/issue-1-oom.md), [CPU](../issues/issue-2-cpu.md), [Deadlock](../issues/issue-3-deadlock.md) | 완료 |
| 현상·증거·원인·조치·before/after를 갖춘 마크다운 구조 | 보고서 3건의 1–4절, [재사용 템플릿](../docs/issue-template.md) | 완료 |
| PDF 또는 GitHub Repository 링크 | B1-2 저장소의 eval 브랜치; README가 제출 진입점 | 완료 |
| 평가문항별 답변·증거 제시 순서 | [21문항 답변](answers.md), [진행 순서](README.md) | 작성 완료 |

## 기능·최소 증거

| ID | 원문 요구사항 | 확인 증거 | 상태 |
|---|---|---|---|
| P1 | root가 아닌 일반 계정으로 실행 | 각 app 로그의 Running as service user agent-admin / uid=1000 | 완료 |
| P2 | AGENT_HOME, PORT=15034, UPLOAD_DIR, KEY_PATH, LOG_DIR 구성 | app 로그 boot 1–6 OK, [사전조건 감사](../evidence/policy-scheduling/prerequisites.txt) | 완료 |
| P3 | secret.key 존재·지정 문자열 검증 | app 로그 `Verified 'secret.key' with correct key string.`; 키 내용은 제출하지 않음 | 완료 |
| P4 | 로그 쓰기 및 포트 바인딩 가능 | boot 로그 4/6·5/6, `Agent listening at port 15034`, LOG_WRITE_CHECK=PASS | 완료 |
| P5 | MEMORY_LIMIT 50–512, CPU_MAX_OCCUPY 10–100, THREAD 허용값 | 여섯 metadata의 정수·bool 설정, boot 6/6 OK | 완료 |
| O1 | monitor.sh로 실제 메모리 상승 관측 | [OOM 관제 before](../evidence/oom/monitor_before.log), RSS 18,376→274,416 KB | 완료 |
| O2 | 임계값 초과 보호 정책 종료 로그 | [OOM app](../evidence/oom/app_before.log), MemoryGuard / Self-terminating process | 완료 |
| O3 | MEMORY_LIMIT 변경 전후 최소 2회 비교 | [before](../evidence/oom/metadata_before.txt), [after](../evidence/oom/metadata_after.txt), after 170초 생존 | 완료 |
| C1 | 특정 프로세스 CPU 급상승 캡처 | [20ms CPU CSV](../evidence/cpu-resolution/cpu_before.csv), PID 17645 부트 후 98.809% 피크 | 완료 |
| C2 | 보호 정책에 따른 종료 입증 | [앱 정책 로그](../evidence/policy-scheduling/cpu-policy-before.log), [자기 SIGTERM](../evidence/policy-scheduling/signals.17834), exit 143 | 완료 |
| C3 | CPU_MAX_OCCUPY before/after | [100 요약](../evidence/cpu-resolution/summary_before.json), [50 요약](../evidence/cpu-resolution/summary_after.json): 약27초 종료→170초 생존 | 완료 |
| D1 | PID 존재 + CPU/MEM·로그 진행 정체 | [ps -L](../evidence/deadlock/process-samples_before.txt), [관제](../evidence/deadlock/monitor_before.log), [마지막 로그](../evidence/deadlock/app_before.log) | 완료 |
| D2 | 상호 자원 대기 논리·스레드/락 대기 근거 | 앱의 A획득→B대기 / B획득→A대기, [gdb/futex 스택](../evidence/deadlock/stacktrace_before.txt) | 완료 |
| D3 | MULTI_THREAD_ENABLE true/false 비교 | [before](../evidence/deadlock/metadata_before.txt), [after](../evidence/deadlock/metadata_after.txt), false에서170초생존 | 완료 |
| B1 | 로그 타임스탬프·실행 순서·교체 주기 패턴화 | [정상 로그](../evidence/policy-scheduling/normal-app.log), [간격 계산](../evidence/policy-scheduling/log-pattern.json), [커널 전환](../evidence/policy-scheduling/sched-trace.txt) | 완료 |
| B2 | RR/FCFS/Priority 중 논리적 추론 | [보너스 보고서](../issues/bonus-scheduling.md): Priority 계열의 우선순위 가중 공정 배분; SCHED_OTHER/nice 및 동일CPU 대조로 검증 | 완료 |
| B3 | 추론 방식의 장단점·적합한 서비스 설명 | 보너스 보고서 4절, 웹·배치 공존 및 실시간 요구 구분 | 완료 |

## 측정 해석 규칙

20ms CPU 피크는 CPU 틱 해상도의 영향을 받는 짧은 구간 사용률이다.
앱의 내부 Load 임계값과 커널 CPU 쿼터는 서로 다르다. CPU_MAX_OCCUPY=50에서도
짧은 실제 CPU 피크가 50%를 넘을 수 있다. 두 지표를 혼동하지 않아야 한다.
after의 170초는 실험 관측 창이며 종료는 수집기의 정리 신호다.
보너스의 Priority 계열 분류는 실제 Linux SCHED_OTHER와 nice 기반 가중 배분을
추상 선택지에 대응한 추론이며 SCHED_FIFO/RR로 정책을 바꾸어 얻은 결과가 아니다.

최종 원복 검증: [restore-final.txt](../evidence/policy-scheduling/restore-final.txt), **PASS=36 FAIL=0**.
