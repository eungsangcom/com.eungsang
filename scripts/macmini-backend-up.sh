#!/usr/bin/env bash
# 맥미니 backend 배포 (레거시 래퍼 — git pull / --build 사용 안 함)
#
# 맥북에서:
#   ./scripts/macmini-backend-up.sh
#
# 실제 동작: ./scripts/docker/deploy-backend-to-macmini.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/docker/deploy-backend-to-macmini.sh" "$@"
