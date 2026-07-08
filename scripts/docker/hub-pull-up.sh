#!/usr/bin/env bash
# 맥미니: Docker Hub에서 pull 후 기동 (로컬 빌드 없음)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/macmini-remote.sh
source "$SCRIPT_DIR/../lib/macmini-remote.sh"

: "${IMAGE_TAG:=latest}"
export IMAGE_TAG

# 맥미니 본체에서 직접 실행하면 이 스크립트가 있는 저장소 루트를 사용
if macmini_is_local; then
  PROJECT_DIR="$ROOT"
else
  PROJECT_DIR="$MACMINI_PROJECT_DIR"
fi

hub_compose() {
  local args
  args=$(printf '%q ' "$@")
  macmini_exec "cd $(printf %q "$PROJECT_DIR") && IMAGE_TAG=$(printf %q "$IMAGE_TAG") docker compose -f $(printf %q "$PROJECT_DIR/Docker-compose.yaml") -f $(printf %q "$PROJECT_DIR/docker-compose.hub.yaml") ${args}"
}

echo "==> pull (IMAGE_TAG=${IMAGE_TAG})"
hub_compose pull

echo "==> up -d"
hub_compose up -d

echo "==> ps"
hub_compose ps
