# 추론 기록 #06: 네이토 사전평가 분석

## 평가 개요
- 네이토(AI) 사전평가 시스템을 통해 B1-2 산출물 자동 평가
- 20개 평가 항목 중 18개 PASS, 2개 FAIL (90%)
- API: POST /rest/ai/pre-evaluation → SSE 스트림 → 결과 조회

## FAIL 항목 분석

### #15: 스택 트레이스 미제출
- **원인**: Deadlock 리포트에 ps/log 증거는 있으나, 스레드별 스택 트레이스(pstack/jstack/gdb)가 없음
- **개선**: Deadlock 발생 시 스레드 스택 트레이스 캡처 스크립트 추가 + 증거에 첨부

### #18: 동시 장애 우선순위 문서 미제출
- **원인**: OOM/CPU/Deadlock이 동시에 발생할 경우의 우선순위 결정 기준이 없음
- **개선**: 동시 장애 우선순위 결정 매트릭스 문서 추가

## PASS 항목 중 주요 개선 제안 반영
1. 증거 파일 경로를 리포트 본문에 명시
2. 반복 실험 결과 추가
3. ps -p 출력 증거 추가
4. 환경변수 적용 절차 명시
5. 연속 ps 측정 (1s 간격) 추가
6. 실행 스크립트 완전한 stdout/stderr 첨부
7. 명령어 예시/옵션 표 요약
8. 판단 단계별 임계치 명시
9. 치명도 등급 매트릭 정의
10. 회고 TODO 정리

## 응용
- 사전평가 API 흐름:
  1. 평가데이터 저장 (newEvlBasToDataTxnByUqstnNoSave) → dataRegSn 획득
  2. 평가데이터 상세 조회 (evlDetail) → dataRegSn, evlNo 확인
  3. 사전평가 실행 (POST /rest/ai/pre-evaluation) → sessionId 획득
  4. SSE 스트림 수신 (/rest/ai/pre-evaluation/stream/{sessionId})
  5. 결과 조회 (GET /rest/ai/pre-evaluation/{dataRegSn}/attempts)
- 다른 과제에도 동일한 사전평가 흐름 적용 가능
