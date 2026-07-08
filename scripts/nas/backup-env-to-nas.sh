#!/usr/bin/env bash
# .env 백업 → NAS /Volumes/project/eungsang.com/env
#
# 사용 (맥미니, 프로젝트 루트):
#   ./scripts/nas/backup-env-to-nas.sh
#   ./scripts/nas/backup-env-to-nas.sh --timestamp   # 날짜 폴더에도 보관
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${NAS_ENV_DIR:-/Volumes/project/eungsang.com/env}"
USE_TIMESTAMP=0

for arg in "$@"; do
  case "$arg" in
    --timestamp|-t) USE_TIMESTAMP=1 ;;
    -h|--help)
      echo "Usage: $0 [--timestamp]"
      echo "  DEST=\$NAS_ENV_DIR (default: /Volumes/project/eungsang.com/env)"
      exit 0
      ;;
  esac
done

if [[ ! -d "$(dirname "$DEST")" ]]; then
  echo "NAS 경로 없음: $(dirname "$DEST")" >&2
  echo "/Volumes/project/eungsang.com 이 마운트돼 있는지 확인하세요." >&2
  exit 1
fi

mkdir -p "$DEST"
chmod 700 "$DEST" 2>/dev/null || true

_backup_one() {
  local src=$1
  local name=$2
  if [[ ! -f "$src" ]]; then
    echo "skip (없음): $src"
    return 0
  fi
  cp "$src" "$DEST/$name"
  chmod 600 "$DEST/$name" 2>/dev/null || true
  echo "ok: $src → $DEST/$name"
}

echo "==> backup to $DEST"
_backup_one "$ROOT/.env" "root.env"
_backup_one "$ROOT/eungsang/.env" "eungsang.env"
_backup_one "$ROOT/scripts/macmini.env" "macmini.env"

if [[ $USE_TIMESTAMP -eq 1 ]]; then
  stamp="$(date +%Y-%m-%d_%H%M%S)"
  archive="$DEST/archive/$stamp"
  mkdir -p "$archive"
  for f in root.env eungsang.env macmini.env; do
    [[ -f "$DEST/$f" ]] && cp "$DEST/$f" "$archive/$f"
  done
  chmod -R 700 "$DEST/archive" 2>/dev/null || true
  echo "==> archive: $archive"
fi

cat > "$DEST/README.txt" <<EOF
eungsang.com env backup ($(date -Iseconds))
- root.env      ← 프로젝트 루트 .env (compose, tunnel, UPLOADS_HOST_PATH)
- eungsang.env  ← eungsang/.env (API, DB, ARTIMUSE, GEMINI)
- macmini.env   ← scripts/macmini.env (SSH 원격, 있을 때만)

복원 예:
  cp root.env $ROOT/.env
  cp eungsang.env $ROOT/eungsang/.env
EOF
chmod 600 "$DEST/README.txt" 2>/dev/null || true

echo "==> 완료"
