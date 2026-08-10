# 회고 및 후속 작업 TODO

> 사전평가 #20 suggestion 대응: 회고 항목별 후속 작업(Owner/기한) 정리

## 회고 요약

### 잘한 점
- 3가지 장애(OOM/CPU/Deadlock)를 실제 실행으로 재현하고 Before/After 증거 수집
- 관제 스크립트(monitor.sh)로 시계열 데이터 확보
- GitHub Issue 포맷으로 구조화된 리포트 작성
- 교착상태 4대 조건 검증으로 논리적 증명
- cloud-init VM 환경으로 재현 가능한 셋업 구축
- 보너스: FCFS 스케줄링 알고리즘 추론

### 개선 필요
- 스택 트레이스 캡처 누락 (사전평가 #15 FAIL)
- 동시 장애 우선순위 문서 누락 (사전평가 #18 FAIL)
- 반복 실험 샘플 부족
- 시스템 레벨 로그(dmesg/syslog) 미연계

## 후속 작업 TODO

| # | 작업 | 우선순위 | 상태 | 비고 |
|---|------|---------|------|------|
| 1 | 스택 트레이스 캡처 스크립트 추가 | High | ✅ 완료 | vm/capture-stacktrace.sh |
| 2 | 동시 장애 우선순위 매트릭스 작성 | High | ✅ 완료 | docs/incident-priority-matrix.md |
| 3 | 치명도 등급 매트릭스 정의 | Medium | ✅ 완료 | docs/severity-matrix.md |
| 4 | Deadlock 리포트에 스택 트레이스 섹션 추가 | High | ✅ 완료 | issues/issue-3-deadlock.md |
| 5 | 증거 파일 경로를 리포트 본문에 명시 | Medium | ✅ 완료 | 각 issue에 evidence 경로 추가 |
| 6 | 환경변수 적용 절차 명시 | Low | ✅ 완료 | 각 issue의 조치 섹션 |
| 7 | 회고 TODO 정리 | Low | ✅ 완료 | 본 문서 |
| 8 | 반복 실험 (복수 샘플) | Low | ⏳ 추후 | VM 환경에서 3회 이상 실행 |
| 9 | 시스템 레벨 로그(dmesg) 연계 | Low | ⏳ 추후 | VM에서 dmesg 캡처 추가 |
| 10 | 알림 연동 예시 (curl/ssmtp) | Low | ⏳ 추후 | monitor.sh 확장 |
