#!/usr/bin/env bash
# Mac git auto-sync agent (poll + POST /sync on :8427)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_PY="$REPO_ROOT/windows_git_sync_agent.py"
LOG_DIR="${MAC_GIT_SYNC_LOG_DIR:-$SCRIPT_DIR/logs}"
VENV_DIR="${MAC_GIT_SYNC_VENV:-$SCRIPT_DIR/.venv}"
REQ="$SCRIPT_DIR/requirements.txt"

mkdir -p "$LOG_DIR"

if [[ ! -f "$AGENT_PY" ]]; then
  echo "ERROR: agent not found: $AGENT_PY" >&2
  exit 1
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  echo "Creating venv at $VENV_DIR"
  /usr/bin/python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install -U pip
  "$VENV_DIR/bin/pip" install -r "$REQ"
fi

export GIT_SYNC_REPO="${GIT_SYNC_REPO:-$REPO_ROOT}"
export GIT_SYNC_BRANCH="${GIT_SYNC_BRANCH:-main}"
export GIT_SYNC_POLL_SECONDS="${GIT_SYNC_POLL_SECONDS:-30}"
export GIT_SYNC_PORT="${GIT_SYNC_PORT:-8427}"
export GIT_SYNC_SERVICE="${GIT_SYNC_SERVICE:-mac-git-sync}"
export GIT_SYNC_LOG_DIR="$LOG_DIR"
# backward-compatible aliases
export MAC_GIT_SYNC_REPO="$GIT_SYNC_REPO"
export MAC_GIT_SYNC_BRANCH="$GIT_SYNC_BRANCH"
export MAC_GIT_SYNC_POLL_SECONDS="$GIT_SYNC_POLL_SECONDS"
export MAC_GIT_SYNC_PORT="$GIT_SYNC_PORT"
export MAC_GIT_SYNC_SERVICE="$GIT_SYNC_SERVICE"
export MAC_GIT_SYNC_LOG_DIR="$GIT_SYNC_LOG_DIR"

cd "$REPO_ROOT"
stamp="$(date '+%Y-%m-%d %H:%M:%S')"
echo "[$stamp] Starting mac-git-sync on port $GIT_SYNC_PORT" >>"$LOG_DIR/agent.log"
exec "$VENV_DIR/bin/python" "$AGENT_PY"
