#!/usr/bin/env bash
# Install Mac git sync agent as a LaunchAgent (login + keepalive).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LABEL="com.eungsang.mac-git-sync"
PLIST_DST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$SCRIPT_DIR/logs"
RUN_AGENT="$SCRIPT_DIR/run_agent.sh"
TEMPLATE="$SCRIPT_DIR/${LABEL}.plist.template"

mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents"
chmod +x "$RUN_AGENT" "$SCRIPT_DIR/uninstall_launchd.sh"

# Ensure venv exists before launchd starts
if [[ ! -x "$SCRIPT_DIR/.venv/bin/python" ]]; then
  /usr/bin/python3 -m venv "$SCRIPT_DIR/.venv"
  "$SCRIPT_DIR/.venv/bin/pip" install -U pip
  "$SCRIPT_DIR/.venv/bin/pip" install -r "$SCRIPT_DIR/requirements.txt"
fi

sed \
  -e "s|__RUN_AGENT__|$RUN_AGENT|g" \
  -e "s|__REPO_ROOT__|$REPO_ROOT|g" \
  -e "s|__LOG_DIR__|$LOG_DIR|g" \
  "$TEMPLATE" >"$PLIST_DST"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed: $LABEL"
echo "  Plist : $PLIST_DST"
echo "  Run   : $RUN_AGENT"
echo "  Logs  : $LOG_DIR"
echo ""
echo "Test:"
echo "  curl -sS http://127.0.0.1:8427/health"
echo "  curl -sS -X POST http://127.0.0.1:8427/sync"
