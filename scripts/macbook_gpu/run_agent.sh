#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_PY="$REPO_ROOT/macbook_gpu_agent.py"
VENV="$SCRIPT_DIR/.venv-agent"
PORT="${MACBOOK_METRICS_PORT:-8425}"

if [[ ! -f "$AGENT_PY" ]]; then
  echo "missing $AGENT_PY" >&2
  exit 1
fi

if [[ ! -x "$VENV/bin/python" ]]; then
  /usr/bin/python3 -m venv "$VENV"
  "$VENV/bin/pip" install -U pip
  "$VENV/bin/pip" install fastapi uvicorn psutil
fi

export MACBOOK_METRICS_PORT="$PORT"
exec "$VENV/bin/python" "$AGENT_PY"
