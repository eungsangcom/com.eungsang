#!/usr/bin/env bash
# 맥북에서 git push 직후 윈도우에 POST /sync 호출
#
# 사용:
#   ./scripts/windows_git_sync/notify-windows-sync.sh
#   git push && ./scripts/windows_git_sync/notify-windows-sync.sh
#
# 환경 (선택):
#   WINDOWS_GIT_SYNC_URL=http://100.102.174.81:8426/sync
set -euo pipefail

: "${WINDOWS_GIT_SYNC_URL:=http://100.102.174.81:8426/sync}"

echo "==> POST $WINDOWS_GIT_SYNC_URL"
FORCE_BODY='{}'
if [[ "${FORCE_SYNC:-0}" == "1" ]]; then
  FORCE_BODY='{"force":true}'
fi
curl -sS -X POST "$WINDOWS_GIT_SYNC_URL" \
  -H "Content-Type: application/json" \
  -d "$FORCE_BODY" \
  -w "\nHTTP %{http_code}\n" \
  --connect-timeout 5 \
  --max-time 120 || {
  echo "warn: windows sync notify failed (poll will still catch up within ~30s)" >&2
  exit 0
}
