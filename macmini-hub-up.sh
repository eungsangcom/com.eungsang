#!/usr/bin/env bash
# 맥미니 NAS 배포 디렉터리에서 실행 — git clone 불필요, Docker Hub 이미지만 pull
#
# 사전 준비 (맥북, 1회):
#   ./scripts/nas/sync-deploy-to-nas.sh
#
# 맥미니에서:
#   cd /Volumes/project/eungsang.com/deploy
#   IMAGE_TAG=latest ./macmini-hub-up.sh
#
# 환경:
#   MACMINI_DEPLOY_DIR  — compose·env 위치 (기본: 스크립트 디렉터리)
#   IMAGE_TAG           — Hub 태그 (기본: latest)
#   SKIP_ALEMBIC        — 1이면 DB 마이그레이션 생략
#   SKIP_PRUNE          — 1이면 docker system prune 생략
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${MACMINI_DEPLOY_DIR:=$SCRIPT_DIR}"
: "${IMAGE_TAG:=latest}"
: "${SKIP_ALEMBIC:=0}"
: "${SKIP_PULL:=0}"
: "${SKIP_PRUNE:=0}"

COMPOSE_MAIN="$MACMINI_DEPLOY_DIR/Docker-compose.yaml"
COMPOSE_HUB="$MACMINI_DEPLOY_DIR/docker-compose.hub.yaml"

if [[ ! -f "$COMPOSE_MAIN" || ! -f "$COMPOSE_HUB" ]]; then
  echo "compose 파일 없음: $MACMINI_DEPLOY_DIR" >&2
  echo "맥북에서 ./scripts/nas/sync-deploy-to-nas.sh 를 실행하세요." >&2
  exit 1
fi

if [[ ! -f "$MACMINI_DEPLOY_DIR/.env" ]]; then
  echo ".env 없음: $MACMINI_DEPLOY_DIR/.env" >&2
  echo "NAS env 백업에서 복원하거나 sync-deploy-to-nas.sh --restore-env 를 사용하세요." >&2
  exit 1
fi

compose() {
  (
    cd "$MACMINI_DEPLOY_DIR"
    IMAGE_TAG="$IMAGE_TAG" docker compose -f "$COMPOSE_MAIN" -f "$COMPOSE_HUB" "$@"
  )
}

echo "==> deploy dir: $MACMINI_DEPLOY_DIR"
if [[ "$SKIP_PULL" != "1" ]]; then
  echo "==> pull (IMAGE_TAG=${IMAGE_TAG})"
  compose pull
else
  echo "==> pull skipped (SKIP_PULL=1)"
fi

echo "==> up -d"
compose up -d

if [[ "$SKIP_ALEMBIC" != "1" ]]; then
  echo "==> alembic upgrade head"
  sleep 3
  if docker ps --format '{{.Names}}' | grep -qx 'eungsang-api'; then
    docker exec eungsang-api alembic upgrade head
  else
    echo "warn: eungsang-api 컨테이너 없음 — alembic 생략" >&2
  fi
fi

echo "==> ps"
compose ps

if [[ "$SKIP_PRUNE" != "1" ]]; then
  echo "==> docker prune (unused containers/images/networks/build cache)"
  docker system prune -af || echo "warn: docker prune failed (ignored)" >&2
else
  echo "==> docker prune skipped (SKIP_PRUNE=1)"
fi
