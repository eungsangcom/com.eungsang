#!/usr/bin/env bash
# 맥북 eungsang/.env 의 WOL 변수를 맥미니 compose env에 반영 (값 출력 없음)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/macmini-remote.sh
source "$SCRIPT_DIR/lib/macmini-remote.sh"

if [[ -f "$ROOT/scripts/macmini.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/scripts/macmini.env"
fi

LOCAL_ENV="$ROOT/eungsang/.env"
REMOTE_EUNG_ENV="${MACMINI_PROJECT_DIR:?}/eungsang/.env"
REMOTE_ROOT_ENV="${MACMINI_PROJECT_DIR:?}/.env"
ENV_KEYS='^(WINDOWS_WOL_)'

if [[ ! -f "$LOCAL_ENV" ]]; then
  echo "local env 없음: $LOCAL_ENV" >&2
  exit 1
fi

if ! grep -qE "$ENV_KEYS" "$LOCAL_ENV"; then
  echo "local .env에 WINDOWS_WOL_* 변수가 없습니다." >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
grep -E "$ENV_KEYS" "$LOCAL_ENV" > "$TMP"

_apply_remote_env() {
  local target="$1"
  macmini_exec "$(cat <<EOF
set -euo pipefail
ENV_FILE=$(printf %q "$target")
if [[ ! -f "\$ENV_FILE" ]]; then
  exit 0
fi
grep -v -E $(printf %q "$ENV_KEYS") "\$ENV_FILE" > "\${ENV_FILE}.tmp"
mv "\${ENV_FILE}.tmp" "\$ENV_FILE"
cat >> "\$ENV_FILE"
EOF
)" < "$TMP"
}

_apply_remote_env "$REMOTE_EUNG_ENV"
_apply_remote_env "$REMOTE_ROOT_ENV"

echo "==> WOL env synced → $REMOTE_EUNG_ENV (+ root .env if present)"
