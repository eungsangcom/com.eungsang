#!/usr/bin/env bash
# 맥미니: 기존 로컬 uploads → NAS 마운트 경로로 rsync (1회)
#
# 사전:
#   1) NAS에 eungsang.com/upload 경로 준비
#   2) 맥미니에서 /Volumes/project/eungsang.com/upload 접근 가능
#   3) 루트 .env: UPLOADS_HOST_PATH=/Volumes/project/eungsang.com/upload
#
# 사용:
#   ./scripts/nas/migrate-uploads-to-nas.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${SRC:-$ROOT/eungsang/apps/uploads}"
DEST="${NAS_UPLOADS:-/Volumes/project/eungsang.com/upload}"

if [[ ! -d "$SRC" ]]; then
  echo "소스 없음: $SRC" >&2
  exit 1
fi
if [[ ! -d "$(dirname "$DEST")" ]]; then
  echo "NAS 경로 없음: $(dirname "$DEST")" >&2
  echo "먼저 /Volumes/project/eungsang.com 이 마운트돼 있는지 확인하세요." >&2
  exit 1
fi

mkdir -p "$DEST"
echo "==> rsync $SRC/ → $DEST/"
rsync -av --progress "$SRC/" "$DEST/"
echo "==> 완료. 루트 .env에 UPLOADS_HOST_PATH=$DEST 확인 후:"
echo "    export MACMINI_LOCAL=1 && IMAGE_TAG=latest ./scripts/docker/hub-pull-up.sh"
