# 재현 절차와 검증 범위

## 실제 수행 순서

1. OrbStack에 `b1-lab` Ubuntu 24.04 amd64 머신 생성.
2. openssh-server, ufw, acl, cron, bc, git, procps, psmisc, gzip, jq,
   nftables, iproute2, sudo, python3, gdb, strace 설치.
3. B1-1 계정·그룹·디렉터리·키·ACL·앱·관제·cron을 구축하고 자동 누적 확인.
4. 같은 머신에서 기존 agent-app 종료, agent-leak-app 배치, 실험 6종 수행.
5. 정상 설정으로 보너스 측정. B1-1 앱으로 원복하고 36개 검증 통과.

원본 실행 로그의 경로 `/root/b1/B1-1`, `/root/b1/B1-2`는 당시 taskmap 복사본이다.
이번 저장소의 `scripts/`는 그 B1-2 실험 스크립트를 독립 레포 경로에 맞춰 정리한 것이다.
초기 환경 구축 로그는 [setup.log](../evidence/b1-1/setup.log), 최종 검증은
[verification.txt](../evidence/b1-1/verification.txt), 왕복 결과는
[30-restore-b1-1.txt](../evidence/30-restore-b1-1.txt)에 있다.

## 이 저장소에서 실험 다시 실행

B1-1 계정·그룹·키·환경변수·ACL·cron·SSH·UFW가 이미 구성된 **실습 머신**에서 실행한다.
기존 작업용 서버에서는 실행하지 않는다. 앱 종료와 로그 변경을 수반한다.
이번 저장소는 B1-2 실험을 다루며 B1-1 환경을 새로 구축하는 실행기는 포함하지 않는다.

바이너리는 이전 Git 입력 커밋에서 정확히 꺼낼 수 있다. Git 이력을 포함해 clone한 뒤:

```bash
mkdir -p local-inputs
git show 7de53d7:agent-leak-app-x86 > local-inputs/agent-leak-app-x86
# Linux 실습 머신 안에서, 저장소 루트 기준
sudo bash scripts/run-experiments.sh "$PWD/local-inputs/agent-leak-app-x86"
```

새 실험 결과는 `rerun-evidence/evidence/`에 기록해 제출 증거를 덮어쓰지 않는다.
새 실행기는 실험 종료 후 B1-1을 자동 원복하지 않는다. 현재 B1-1 구성의 실행/검증 스크립트로
원복해야 한다. 체크아웃 정리 후 실행기 수정본은 셸 문법을 검사했으며 전체 재실험은 하지 않았다.
제출 원본은 앞서 실제 수행한 실험에서 나온 파일이다.

## 실행 중 발견·수정한 사항

- Ubuntu 홈 0750으로 인한 공용 계정 접근 실패: 상위 홈에 공용 그룹 통과 ACL 추가.
- root 실행기의 sudo가 LAB_SRC/CONTROL_PORT를 제거: root 확인 후 직접 bash 호출.
- 검증기의 샌드박스 예외 포트 고정 요구: VM에서는 20022/15034 두 개만 요구.
- 원복 스크립트의 고정 `/home/user/codyssey-taskmap` 경로 제거.
- SSH를 수동 프로세스에서 systemd enabled/active로 전환 후 36개 항목 재검증.

## 한계

- after의 170초 생존은 장기 안정성 검증이 아니다.
- CPU 과점유·시스템 지연은 실제 OS 표본으로 입증하지 못했다.
- gdb 스택을 확보했지만 락 소유자와 주소의 완전한 대응까지 검증하지 않았다.
- 보너스 알고리즘을 RR/FCFS/Priority 중 하나로 확정할 근거가 부족하다.
- UFW IPv6 및 로깅은 꺼진 상태이며 미검증이다.
- SSH 서비스 활성화는 확인했으나 머신 재부팅 실험은 수행하지 않았다.
- 공식 평가·외부 동료평가는 미실시다.

원본 로그에는 최초 검증기의 FAIL=1 기록이 남는다. 당시 실패는 VM에 필요 없는
샌드박스 예외 포트 요구였다. 수정 후 최종 및 원복 검증은 PASS=36 FAIL=0이다.
공백 등도 보존했으므로 raw 로그의 trailing whitespace는 원본 출력이다.
