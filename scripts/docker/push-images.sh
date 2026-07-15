#!/usr/bin/env bash
# 커스텀 서비스 이미지 빌드 → Docker Hub (eungsang/*) push
# 사용: docker login && ./scripts/docker/push-images.sh
# 태그: IMAGE_TAG=$(git rev-parse --short HEAD) ./scripts/docker/push-images.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

: "${DOCKERHUB_USER:=eungsang}"
: "${IMAGE_TAG:=latest}"

build_push() {
  local name=$1
  shift
  local image="${DOCKERHUB_USER}/${name}:${IMAGE_TAG}"
  echo "==> build $image"
  docker build -t "$image" "$@"
  echo "==> push $image"
  docker push "$image"
}

build_push eungsang-api ./eungsang
build_push eungsang-ontology-mcp ./ontology_mcp
build_push eungsang-code-rag ./rag_code
build_push eungsang-novel-rag ./rag_novel
build_push eungsang-books-rag ./rag_books
build_push eungsang-n8n ./docker/n8n
build_push eungsang-moderation -f eungsang/apps/moderation_service/Dockerfile ./eungsang

echo "==> done (tag=${IMAGE_TAG})"
echo "맥미니: IMAGE_TAG=${IMAGE_TAG} ./scripts/docker/hub-pull-up.sh"
