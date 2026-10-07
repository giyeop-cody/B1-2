# Current OrbStack experiment paths. Source from Linux scripts.
B12_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export B12_LAB="${B12_EVIDENCE_ROOT:-$B12_ROOT/rerun-evidence}"
export AGENT_ADMIN=agent-admin AGENT_DEV=agent-dev AGENT_TEST=agent-test
export GRP_COMMON=agent-common GRP_CORE=agent-core
export AGENT_HOME=/home/agent-admin/agent-app AGENT_PORT=15034
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEYS_DIR="$AGENT_HOME/api_keys"
export AGENT_LOG_DIR=/var/log/agent-app
export B12_APP="$AGENT_HOME/agent-leak-app"
export B12_PROCMON="$AGENT_HOME/bin/monitor-proc.sh"
export B12_STACKTRACE="$AGENT_HOME/bin/capture-stacktrace.sh"
