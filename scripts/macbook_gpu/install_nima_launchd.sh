#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LABEL="com.eungsang.macbook-nima"
PLIST_DST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$SCRIPT_DIR/logs"
RUN_NIMA="$SCRIPT_DIR/run_nima.sh"
TEMPLATE="$SCRIPT_DIR/${LABEL}.plist.template"

mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents"
chmod +x "$RUN_NIMA"

if [[ ! -x "$SCRIPT_DIR/.venv/bin/python" ]]; then
  /usr/bin/python3 -m venv "$SCRIPT_DIR/.venv"
  "$SCRIPT_DIR/.venv/bin/pip" install -U pip
  "$SCRIPT_DIR/.venv/bin/pip" install -r "$SCRIPT_DIR/requirements.txt"
fi
"$SCRIPT_DIR/.venv/bin/pip" install -r "$SCRIPT_DIR/requirements-nima.txt"

sed \
  -e "s|__RUN_NIMA__|$RUN_NIMA|g" \
  -e "s|__REPO_ROOT__|$REPO_ROOT|g" \
  -e "s|__LOG_DIR__|$LOG_DIR|g" \
  "$TEMPLATE" >"$PLIST_DST"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed: $LABEL"
echo "  curl http://127.0.0.1:8428/health"
echo "  log: $LOG_DIR/nima.log"
