#!/usr/bin/env bash
# 맥미니: Docker Hub에서 pull 후 기동 (로컬 빌드·git clone 불필요)
#
# 맥북에서 원격 실행:
#   IMAGE_TAG=latest ./scripts/docker/hub-pull-up.sh
#
# 맥북에서 backend만 이미지 전송 배포(권장 · git pull 없음):
#   ./scripts/docker/deploy-backend-to-macmini.sh
#
# 맥미니 NAS 배포 디렉터리에서 직접:
#   export MACMINI_LOCAL=1
#   cd /Volumes/project/eungsang.com/deploy
#   IMAGE_TAG=latest ./macmini-hub-up.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/macmini-remote.sh
source "$SCRIPT_DIR/../lib/macmini-remote.sh"

: "${IMAGE_TAG:=latest}"
export IMAGE_TAG

if macmini_is_local; then
  exec "$SCRIPT_DIR/macmini-hub-up.sh"
fi

PROJECT_DIR="$MACMINI_PROJECT_DIR"
DEPLOY_SCRIPT="$PROJECT_DIR/macmini-hub-up.sh"

if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
  echo "배포 스크립트 없음: $DEPLOY_SCRIPT" >&2
  echo "맥북에서 ./scripts/nas/sync-deploy-to-nas.sh 를 먼저 실행하세요." >&2
  exit 1
fi

macmini_exec "cd $(printf %q "$PROJECT_DIR") && IMAGE_TAG=$(printf %q "$IMAGE_TAG") ./macmini-hub-up.sh"
