#!/usr/bin/env bash
# B1-2 수동 환경 구성 스크립트 (cloud-init 대체)
# 사용: ./setup-env.sh
set -euo pipefail

AGENT_USER="agent-admin"
AGENT_HOME="/home/$AGENT_USER/agent-app"
LOG_DIR="/var/log/agent-app"

echo "[1/5] 서비스 계정 생성"
id -u "$AGENT_USER" &>/dev/null || sudo useradd -m -s /bin/bash "$AGENT_USER"

echo "[2/5] 디렉토리 구조 생성"
sudo -u "$AGENT_USER" mkdir -p "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys"
sudo mkdir -p "$LOG_DIR"
sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME" "$LOG_DIR"

echo "[3/5] secret.key 생성"
echo -n "agent_api_key_test" | sudo -u "$AGENT_USER" tee "$AGENT_HOME/api_keys/secret.key" >/dev/null
sudo -u "$AGENT_USER" chmod 600 "$AGENT_HOME/api_keys/secret.key"

echo "[4/5] 환경 변수 (.bash_profile)"
sudo -u "$AGENT_USER" tee "$AGENT_HOME/../.bash_profile" >/dev/null << 'ENVEOF'
export AGENT_HOME="/home/agent-admin/agent-app"
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys"
export AGENT_LOG_DIR="/var/log/agent-app"
export MEMORY_LIMIT=256
export CPU_MAX_OCCUPY=80
export MULTI_THREAD_ENABLE=false
ENVEOF

echo "[5/5] 바이너리 배치"
echo "  agent-leak-app-x86(또는 arm64)을 $AGENT_HOME/agent-leak-app 으로 복사하세요"
echo "  chmod +x $AGENT_HOME/agent-leak-app"
echo ""
echo "=== 환경 구성 완료 ==="
