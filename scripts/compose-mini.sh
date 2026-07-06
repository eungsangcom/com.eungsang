#!/usr/bin/env bash
# 맥미니에서 docker compose 실행 (맥북 Cursor·터미널용)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/macmini-remote.sh
source "$SCRIPT_DIR/lib/macmini-remote.sh"

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <docker compose args...>" >&2
  echo "Example: $0 up -d backend cloudflared" >&2
  exit 1
fi

macmini_compose "$@"
