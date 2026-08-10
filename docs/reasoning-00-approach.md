# 추론 기록 #00: 접근 방법 선정

## 질문: 컨테이너 vs VM?

### 초기 상황
- B1-1은 Docker 컨테이너(Ubuntu 22.04) 기반으로 수행됨
- B1-2 과제 가이드: "로컬 또는 격리된 환경(Docker 컨테이너 등)에서 실행을 권장"
- B1-1 레포에 이미 cloud-init user-data.yml 존재 (VM 프로비저닝 경험 있음)

### 비교 분석

| 기준 | 컨테이너 | VM (OrbStack) |
|------|----------|---------------|
| 커널 | host 공유 | 격리된 커널 |
| ps/top 수치 | host 기준 섞임 | VM 독립 수치 |
| /proc/meminfo | host 메모리 | VM 메모리 |
| 실서버 재현도 | 낮음 | 높음 |
| 프로비저닝 | Dockerfile | cloud-init (IaC) |

### 결정: VM + OrbStack + cloud-init

**핵심 근거**: B1-2의 본질은 **시스템 자원 관측**(OOM/CPU/deadlock)이다.
- 컨테이너는 host 커널을 공유하여 `ps`/`top`/`/proc/meminfo`가 host 기준 수치를 보임
  → MEMORY_LIMIT(앱 내부 한계)는 동일하게 트리거되지만, **관측 수치가 섞여 분석이 불명확**
- VM은 격리된 커널/메모리를 가지므로 관측이 깔끔
  → "운영 서버에서 에이전트 실행 후 장애 관측" 시나리오에 가장 근사
- cloud-init으로 프로비저닝하면 실제 인프라 워크플로(IaC)를 학습
- B1-1에서 이미 cloud-init(user-data.yml) 사용 → 기술적 연속성

### 응용 포인트
- 동일한 cloud-init 템플릿으로 시나리오별 VM을 빠르게 재생성 가능
- env var만 바꿔서 OOM/CPU/Deadlock 3가지를 한 VM에서 순차 재현
- 다른 트러블슈팅 과제에도 cloud-init + run-scenario.sh 패턴 재사용 가능
