# 재현 가이드

## 전제 조건
- OrbStack (macOS) 또는 Linux 환경
- agent-leak-app 바이너리 (x86 또는 arm64)

## 방법 A: OrbStack VM + cloud-init

### 1. VM 생성
```bash
orb create vm --user-data vm/user-data.yml ubuntu:22.04 b1-2-lab
```

### 2. 바이너리 배치
```bash
scp agent-leak-app-x86 agent-admin@<vm-ip>:/home/agent-admin/agent-app/agent-leak-app
ssh agent-admin@<vm-ip> "chmod +x ~/agent-app/agent-leak-app"
```

### 3. 시나리오 실행
```bash
# OOM
ssh agent-admin@<vm-ip> "~/run-scenario.sh oom before"   # 256MB, 크래시
ssh agent-admin@<vm-ip> "~/run-scenario.sh oom after"    # 512MB, 정상

# CPU
ssh agent-admin@<vm-ip> "~/run-scenario.sh cpu before"   # 100%, 크래시
ssh agent-admin@<vm-ip> "~/run-scenario.sh cpu after"    # 50%, 정상

# Deadlock
ssh agent-admin@<vm-ip> "~/run-scenario.sh deadlock before"  # true, 교착
ssh agent-admin@<vm-ip> "~/run-scenario.sh deadlock after"   # false, 정상
```

### 4. 관제 동시 실행 (별명 터미널)
```bash
ssh agent-admin@<vm-ip> "./vm/monitor.sh 2"
```

## 방법 B: 수동 환경

### 1. 환경 구성
```bash
./vm/setup-env.sh
cp agent-leak-app-x86 ~/agent-app/agent-leak-app
chmod +x ~/agent-app/agent-leak-app
```

### 2. 환경 변수 로드
```bash
source ~/.bash_profile
```

### 3. 시나리오 실행
```bash
# OOM Before
MEMORY_LIMIT=256 CPU_MAX_OCCUPY=100 MULTI_THREAD_ENABLE=false \
  ~/agent-app/agent-leak-app

# CPU After
MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50 MULTI_THREAD_ENABLE=false \
  ~/agent-app/agent-leak-app

# Deadlock Before
MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50 MULTI_THREAD_ENABLE=true \
  ~/agent-app/agent-leak-app
```

## 증거 수집 체크리스트

| Case | 필수 증거 | 확인 방법 |
|------|-----------|-----------|
| OOM | monitor.sh 메모리 상승 수치 | `ps` RSS 선형 증가 |
| OOM | 종료 로그 | `MemoryGuard... SELF-TERMINATED` |
| OOM | MEMORY_LIMIT 변경 전후 | Before 30초 종료 / After 60초+ 생존 |
| CPU | CPU 급상승 구간 | `CpuWorker Current Load` 증가 |
| CPU | 종료 로그 | `CPU Threshold Violated` |
| CPU | CPU_MAX_OCCUPY 변경 전후 | Before 크래시 / After cooldown |
| Deadlock | PID 존재 | `ps -ef \| grep agent` |
| Deadlock | CPU/MEM 정체 | `ps -p` 반복 측정 변화 없음 |
| Deadlock | 마지막 로그 | `WAITING... BLOCKED` |
| Deadlock | MULTI_THREAD 변경 전후 | Before 교착 / After 정상 |
