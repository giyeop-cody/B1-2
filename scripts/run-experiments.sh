#!/usr/bin/env bash
# Requires the B1-1 environment already provisioned on the same Linux machine.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
[[ $EUID -eq 0 ]] || { echo 'Run with sudo on the lab machine'; exit 1; }
APP_SOURCE=${1:?Usage: sudo bash scripts/run-experiments.sh /path/to/agent-leak-app-x86}
[[ -f "$APP_SOURCE" && -f "$AGENT_HOME/env.sh" && -f "$AGENT_KEYS_DIR/secret.key" ]]
id "$AGENT_ADMIN" >/dev/null
pkill -f '/usr/local/bin/agent-app' || true
pkill -f "$B12_APP" || true
sleep 2
install -m 755 -o "$AGENT_ADMIN" -g "$GRP_COMMON" "$APP_SOURCE" "$B12_APP"
install -m 750 -o "$AGENT_DEV" -g "$GRP_CORE" "$B12_ROOT/scripts/monitor.sh" "$B12_PROCMON"
install -m 750 -o "$AGENT_DEV" -g "$GRP_CORE" "$B12_ROOT/scripts/capture-stacktrace.sh" "$B12_STACKTRACE"
mkdir -p "$B12_LAB"
for scenario in oom cpu deadlock; do
  for mode in before after; do
    bash "$B12_ROOT/scripts/20-run-scenario.sh" "$scenario" "$mode"
  done
done
bash "$B12_ROOT/scripts/40-scheduling-probe.sh" 12
cp "$AGENT_LOG_DIR/b1-2/bonus/scheduling-probe.txt" "$B12_LAB/evidence/40-scheduling-probe.txt"
echo "New evidence: $B12_LAB/evidence (historical evidence preserved)"
