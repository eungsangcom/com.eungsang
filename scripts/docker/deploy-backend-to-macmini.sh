#!/usr/bin/env bash
# 맥북 → 맥미니 backend 배포 (git pull 없음 · 이미지 전송만)
#
# 맥미니에는 compose·env만 두고, 코드는 Docker 이미지로만 반영합니다.
#
# 사용 (맥북, 프로젝트 루트):
#   ./scripts/docker/deploy-backend-to-macmini.sh
#   SKIP_BUILD=1 ./scripts/docker/deploy-backend-to-macmini.sh   # 기존 로컬 이미지 재전송
#   SKIP_ALEMBIC=1 ./scripts/docker/deploy-backend-to-macmini.sh
#   SKIP_PRUNE=1 ./scripts/docker/deploy-backend-to-macmini.sh   # docker prune 생략
#
# 설정 (scripts/macmini.env):
#   MACMINI_PROJECT_DIR=/Volumes/incloser/project/com.eungsang
#   MACMINI_BACKEND_IMAGE=comeungsang-backend:latest   # 미설정 시 실행 중 컨테이너에서 추론
#   MACMINI_LOCAL_IMAGE=eungsang-api:deploy              # 맥북 빌드 태그
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/macmini-remote.sh
source "$SCRIPT_DIR/../lib/macmini-remote.sh"

if [[ -f "$ROOT/scripts/macmini.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/scripts/macmini.env"
fi

: "${MACMINI_LOCAL_IMAGE:=eungsang-api:deploy}"
: "${SKIP_BUILD:=0}"
: "${SKIP_ALEMBIC:=0}"
: "${COMPOSE_FILE:=docker-compose.yaml}"
: "${MACMINI_COMPOSE_PROJECT:=comeungsang}"

resolve_backend_image() {
  if [[ -n "${MACMINI_BACKEND_IMAGE:-}" ]]; then
    printf '%s' "$MACMINI_BACKEND_IMAGE"
    return
  fi
  local detected
  detected="$(macmini_ssh 'zsh -lic "docker inspect eungsang-api --format \"{{.Config.Image}}\" 2>/dev/null || true"')" || true
  if [[ -n "$detected" ]]; then
    printf '%s' "$detected"
    return
  fi
  printf '%s' "comeungsang-backend:latest"
}

macmini_compose_backend() {
  macmini_exec "cd $(printf %q "$MACMINI_PROJECT_DIR") && COMPOSE_PROJECT_NAME=$(printf %q "$MACMINI_COMPOSE_PROJECT") docker compose -p $(printf %q "$MACMINI_COMPOSE_PROJECT") -f $(printf %q "$MACMINI_PROJECT_DIR/$COMPOSE_FILE") $*"
}

echo "==> 대상: $(macmini_is_local && echo '맥미니(로컬)' || echo "맥미니 SSH ($MACMINI_SSH_HOST)")"
echo "==> compose: $MACMINI_PROJECT_DIR/$COMPOSE_FILE"
echo "==> git pull 없음 · 이미지 전송 배포"

TARGET_IMAGE="$(resolve_backend_image)"
echo "==> backend image tag: $TARGET_IMAGE"

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "==> build (local): $MACMINI_LOCAL_IMAGE"
  docker build -t "$MACMINI_LOCAL_IMAGE" "$ROOT/eungsang"
else
  echo "==> build skipped (SKIP_BUILD=1)"
  if ! docker image inspect "$MACMINI_LOCAL_IMAGE" >/dev/null 2>&1; then
    echo "로컬 이미지 없음: $MACMINI_LOCAL_IMAGE" >&2
    exit 1
  fi
fi

echo "==> transfer image → macmini"
if macmini_is_local; then
  docker tag "$MACMINI_LOCAL_IMAGE" "$TARGET_IMAGE"
else
  docker save "$MACMINI_LOCAL_IMAGE" | macmini_ssh 'zsh -lic "docker load"'
  macmini_ssh "zsh -lic $(printf %q "docker tag $MACMINI_LOCAL_IMAGE $TARGET_IMAGE")"
fi

echo "==> recreate backend (--no-build)"
macmini_compose_backend up -d --no-build --force-recreate backend

if [[ "$SKIP_ALEMBIC" != "1" ]]; then
  echo "==> alembic upgrade head"
  sleep 5
  macmini_ssh 'zsh -lic "docker exec eungsang-api alembic upgrade head"'
else
  echo "==> alembic skipped (SKIP_ALEMBIC=1)"
fi

echo "==> health"
macmini_ssh 'zsh -lic "curl -sS -o /dev/null -w \"backend: %{http_code}\\n\" http://127.0.0.1:8000/"' || true
macmini_ssh 'zsh -lic "docker logs eungsang-api --tail 12"'

macmini_docker_prune

echo "==> done"
