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
: "${MACMINI_APP_NETWORK:=comeungsang_app-network}"

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

# 공유 app-network 는 external. compose up 이 네트워크를 지우지 않도록 보장.
ensure_app_network() {
  echo "==> ensure network: $MACMINI_APP_NETWORK"
  macmini_exec "docker network inspect $(printf %q "$MACMINI_APP_NETWORK") >/dev/null 2>&1 || docker network create --label com.docker.compose.network=app-network --label com.docker.compose.project=$(printf %q "$MACMINI_COMPOSE_PROJECT") $(printf %q "$MACMINI_APP_NETWORK")"
}

# backend 컨테이너만 교체. 공유 네트워크·다른 서비스는 건드리지 않음.
recreate_backend_container() {
  echo "==> recreate backend only (--no-deps, network untouched)"
  # 기존 컨테이너만 제거 후 compose 로 재생성 (network external 이면 remove 시도 없음)
  macmini_exec "docker rm -f eungsang-api >/dev/null 2>&1 || true"
  # --no-deps: redis/neo4j/n8n 재기동 안 함
  # --pull never: 방금 load 한 로컬 태그 사용
  if ! macmini_compose_backend up -d --no-deps --no-build --pull never backend; then
    echo "warn: compose up failed — falling back to docker run with network-alias backend" >&2
    macmini_exec "$(cat <<EOF
set -euo pipefail
cd $(printf %q "$MACMINI_PROJECT_DIR")
TMPENV=\$(mktemp)
trap 'rm -f "\$TMPENV"' EXIT
grep -E '^[A-Za-z_][A-Za-z0-9_]*=' eungsang/.env >> "\$TMPENV" 2>/dev/null || true
grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env >> "\$TMPENV" 2>/dev/null || true
set -a
# shellcheck disable=SC1091
source .env 2>/dev/null || true
set +a
UPLOADS_HOST_PATH=\${UPLOADS_HOST_PATH:-./eungsang/apps/uploads}
NAS_PHOTO_HOST_PATH=\${NAS_PHOTO_HOST_PATH:-/Volumes/photo}
BGM_HOST_PATH=\${BGM_HOST_PATH:-/Volumes/project/eungsang.com}
docker rm -f eungsang-api >/dev/null 2>&1 || true
docker run -d \\
  --name eungsang-api \\
  --restart on-failure:5 \\
  --network $(printf %q "$MACMINI_APP_NETWORK") \\
  --network-alias backend \\
  -p 8000:8000 \\
  --env-file "\$TMPENV" \\
  -v "\$UPLOADS_HOST_PATH:/app/apps/uploads" \\
  -v "\$NAS_PHOTO_HOST_PATH:/Volumes/photo" \\
  -v "\$BGM_HOST_PATH:/Volumes/project/eungsang.com" \\
  --add-host=host.docker.internal:host-gateway \\
  $(printf %q "$TARGET_IMAGE") \\
  uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
EOF
)"
  fi
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

ensure_app_network
recreate_backend_container

if [[ "$SKIP_ALEMBIC" != "1" ]]; then
  echo "==> alembic upgrade head"
  sleep 5
  macmini_ssh 'zsh -lic "docker exec eungsang-api alembic upgrade head"'
else
  echo "==> alembic skipped (SKIP_ALEMBIC=1)"
fi

echo "==> health"
macmini_ssh 'zsh -lic "
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  code=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 3 http://127.0.0.1:8000/ || true)
  if [[ \"\$code\" == \"200\" ]]; then
    echo \"backend: \$code\"
    break
  fi
  sleep 3
done
docker ps --filter name=eungsang-api --format \"{{.Names}} {{.Status}} {{.Image}}\"
docker logs eungsang-api --tail 12
"' || true

macmini_docker_prune

echo "==> done"
