#!/usr/bin/env bash
# 맥미니 Docker 미사용 리소스 정리
#
# 사용 (맥북):
#   ./scripts/docker/macmini-prune.sh
#   SKIP_PRUNE=1 ./scripts/docker/macmini-prune.sh   # no-op
#
# 정리 대상: 중지된 컨테이너, 미사용 이미지/네트워크/빌드 캐시
# 유지: named volume, 실행 중 컨테이너가 참조하는 이미지
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/macmini-remote.sh
source "$SCRIPT_DIR/../lib/macmini-remote.sh"

if [[ -f "$ROOT/scripts/macmini.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/scripts/macmini.env"
fi

echo "==> 대상: $(macmini_is_local && echo '맥미니(로컬)' || echo "맥미니 SSH ($MACMINI_SSH_HOST)")"
macmini_docker_prune
echo "==> done"
