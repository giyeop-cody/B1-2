# B1-2 동료평가 시나리오

## 1. 학습
- OOM (메모리 누수 → RSS 증가 → OOM Killer)
- CPU Spike (CPU 독점 → Watchdog SIGTERM)
- Deadlock (스레드 교착 → PID存活 but 무응답)

## 2. 고찰
- "로그 없으면 원인 추론 불가" — 데이터 기반 사고
- "Before/After 수치로 검증" — 수치로 증명

## 3. 시도
- monitor.sh로 1초 간격 수집
- OOM: MEMORY_LIMIT=256 → 5초 크래시 → 512로 변경
- CPU: CPU_MAX_OCCUPY=80 → Watchdog → 50으로 변경
- Deadlock: MULTI_THREAD_ENABLE=true → 블록 → false로 회피

## 4. 수정
- MEMORY_LIMIT 256→512, CPU_MAX_OCCUPY 80→50, MULTI_THREAD true→false

## 5. 선택과 선정
- 256 vs 512: 512 (충분한 로그, 2배 안전)
- 환경변수 vs 코드 수정: 환경변수 (재배포 불필요)

## 6. 트러블슈팅
- Deadlock 재현 안 됨 → export 문제
- 스택 트레이스 미제출 → pstack 캡처
- 동시 장애 우선순위 미제출 → 매트릭스 작성
