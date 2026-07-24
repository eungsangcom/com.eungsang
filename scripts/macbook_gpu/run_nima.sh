#!/usr/bin/env bash
# NIMA server — launchd foreground runner (port 8428)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
NIMA_PORT="${NIMA_PORT:-8428}"

mkdir -p "$LOG_DIR"

PYTHON="$SCRIPT_DIR/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
  /usr/bin/python3 -m venv "$SCRIPT_DIR/.venv"
  "$SCRIPT_DIR/.venv/bin/pip" install -U pip
  "$SCRIPT_DIR/.venv/bin/pip" install -r "$SCRIPT_DIR/requirements.txt"
fi

"$PYTHON" -c "import pyiqa" >/dev/null 2>&1 || \
  "$SCRIPT_DIR/.venv/bin/pip" install -r "$SCRIPT_DIR/requirements-nima.txt"

export NIMA_PORT
export NIMA_LAZY_LOAD="${NIMA_LAZY_LOAD:-1}"
export NIMA_IDLE_UNLOAD_SEC="${NIMA_IDLE_UNLOAD_SEC:-300}"

if [[ -z "${NIMA_DEVICE:-}" ]]; then
  if "$PYTHON" -c "import torch; print(torch.backends.mps.is_available())" 2>/dev/null | grep -q True; then
    export NIMA_DEVICE=mps
  else
    export NIMA_DEVICE=cpu
  fi
fi

exec "$PYTHON" "$REPO_ROOT/scripts/nima_server/nima_server.py" >>"$LOG_DIR/nima.log" 2>&1
