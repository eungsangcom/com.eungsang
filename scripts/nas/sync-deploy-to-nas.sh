#!/usr/bin/env bash
# 맥북 → NAS 배포 디렉터리 동기화 (맥미니 git clone 불필요)
#
# NAS에 compose·hub override·실행 스크립트·env 만 두고,
# 맥미니는 Docker Hub 이미지만 pull 해서 기동합니다.
#
# 사용 (맥북, 프로젝트 루트):
#   ./scripts/nas/sync-deploy-to-nas.sh
#   ./scripts/nas/sync-deploy-to-nas.sh --restore-env   # NAS env 백업 → deploy/.env
#
# 맥미니:
#   cd /Volumes/project/eungsang.com/deploy
#   IMAGE_TAG=latest ./macmini-hub-up.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${NAS_DEPLOY_DIR:-/Volumes/project/eungsang.com/deploy}"
RESTORE_ENV=0

for arg in "$@"; do
  case "$arg" in
    --restore-env) RESTORE_ENV=1 ;;
    -h|--help)
      echo "Usage: $0 [--restore-env]"
      echo "  DEST=\$NAS_DEPLOY_DIR (default: /Volumes/project/eungsang.com/deploy)"
      exit 0
      ;;
  esac
done

if [[ ! -d "$(dirname "$DEST")" ]]; then
  echo "NAS 경로 없음: $(dirname "$DEST")" >&2
  echo "/Volumes/project/eungsang.com 이 마운트돼 있는지 확인하세요." >&2
  exit 1
fi

mkdir -p "$DEST/eungsang"

copy_file() {
  local src=$1
  local rel=$2
  install -m 0644 "$src" "$DEST/$rel"
  echo "ok: $rel"
}

echo "==> sync deploy bundle to $DEST"
copy_file "$ROOT/Docker-compose.yaml" "Docker-compose.yaml"
copy_file "$ROOT/docker-compose.hub.yaml" "docker-compose.hub.yaml"
copy_file "$ROOT/scripts/docker/macmini-hub-up.sh" "macmini-hub-up.sh"
chmod +x "$DEST/macmini-hub-up.sh"

if [[ $RESTORE_ENV -eq 1 ]]; then
  ENV_DIR="${NAS_ENV_DIR:-/Volumes/project/eungsang.com/env}"
  if [[ -f "$ENV_DIR/root.env" ]]; then
    cp "$ENV_DIR/root.env" "$DEST/.env"
    chmod 600 "$DEST/.env"
    echo "ok: .env ← $ENV_DIR/root.env"
  fi
  if [[ -f "$ENV_DIR/eungsang.env" ]]; then
    cp "$ENV_DIR/eungsang.env" "$DEST/eungsang/.env"
    chmod 600 "$DEST/eungsang/.env"
    echo "ok: eungsang/.env ← $ENV_DIR/eungsang.env"
  fi
elif [[ -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env" "$DEST/.env"
  chmod 600 "$DEST/.env"
  echo "ok: .env (로컬 복사)"
fi

if [[ -f "$ROOT/eungsang/.env" ]]; then
  cp "$ROOT/eungsang/.env" "$DEST/eungsang/.env"
  chmod 600 "$DEST/eungsang/.env"
  echo "ok: eungsang/.env (로컬 복사)"
fi

cat > "$DEST/README.txt" <<EOF
eungsang.com deploy bundle ($(date -Iseconds))
- git clone 없이 Docker Hub 이미지 + compose 만으로 맥미니 기동
- 업데이트: 맥북에서 ./scripts/nas/sync-deploy-to-nas.sh 후 맥미니에서 ./macmini-hub-up.sh
- env 백업: ./scripts/nas/backup-env-to-nas.sh
EOF

echo "==> 완료"
echo "맥미니: cd $DEST && IMAGE_TAG=latest ./macmini-hub-up.sh"
