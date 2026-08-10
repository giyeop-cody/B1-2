# 추론 기록 #01: 관제 스크립트 설계

## 목표
agent-leak-app의 CPU/MEM/RSS를 시계열로 수집하여 장애 패턴을 시각화.

## 설계 과정

### 1차 시도: pgrep -f 단일 PID 추적
- `pgrep -f agent-leak-app | head -1`로 단일 PID 추적
- 문제: agent-leak-app이 부모/자식 프로세스로 분기 → 부모(RSS 작음)만 추적하여 실제 worker 누락
- 관제 로그에 RSS가 3MB로 고정 → 메모리 증가가 안 보임

### 2차 수정: ps aux + RSS 정렬
- `ps aux | grep agent-leak-app | sort -k6 -rn | head -1`
- RSS 기준 내림차순 정렬하여 실제 메모리를 사용하는 worker PID 추적
- 결과: RSS 17MB → 273MB 선형 증가 패턴 포착 성공

### 핵심 교훈
- 프로세스가 분기(fork)하는 경우, 단일 PID 추적은 위험
- 관제 대상이 "어떤 자원을 소비하는가"에 따라 정렬 기준을 정해야 함
  - 메모리 장애 → RSS 기준
  - CPU 장애 → %CPU 기준
- `ps aux` 출력 필드: %cpu(3열) %mem(4열) rss(6열) vsz(5열)

## 응용
- 다른 멀티프로세스 앱 관제에도 동일 패턴 적용
- RSS 대신 %cpu 정렬로 CPU 스파이크 관제 변형 가능
