#!/usr/bin/env bash
# 맥미니 backend 재기동 (맥북에서는 SSH 경유)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/macmini-remote.sh
source "$SCRIPT_DIR/lib/macmini-remote.sh"

if [[ -f "$ROOT/scripts/macmini.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/scripts/macmini.env"
fi

echo "==> 대상: $(macmini_is_local && echo '맥미니(로컬)' || echo "맥미니 SSH ($MACMINI_SSH_HOST)")"
echo "==> 프로젝트: $MACMINI_PROJECT_DIR"

if macmini_is_local; then
  echo "==> NAS DB 연결 테스트 (5433)"
  nc -zv 192.168.0.72 5433 || {
    echo "NAS Postgres(192.168.0.72:5433)에 연결되지 않습니다."
    echo "pgvector 폴백: POSTGRES_HOST=pgvector POSTGRES_PORT=5432 POSTGRES_PASSWORD=changeme POSTGRES_DB=eungsang ./scripts/compose-mini.sh up -d backend"
    exit 1
  }
else
  echo "==> NAS DB 연결 테스트 (맥미니에서 실행)"
  macmini_ssh "nc -zv 192.168.0.72 5433" || {
    echo "NAS Postgres(192.168.0.72:5433)에 연결되지 않습니다."
    echo "pgvector 폴백: POSTGRES_HOST=pgvector POSTGRES_PORT=5432 POSTGRES_PASSWORD=changeme POSTGRES_DB=eungsang ./scripts/compose-mini.sh up -d backend"
    exit 1
  }
fi

echo "==> 기존 backend 중지·재생성 (--build: 이미지에 코드 반영)"
macmini_compose stop backend 2>/dev/null || true
macmini_compose rm -f backend 2>/dev/null || true
macmini_compose up -d --build --force-recreate backend

echo "==> 컨테이너 command 확인"
macmini_docker inspect eungsang-api --format '{{json .Config.Cmd}}'
echo

echo "==> 로그 (60초 대기 후 40줄) — 'Application startup complete' 확인"
sleep 60
macmini_docker logs eungsang-api --tail 40
