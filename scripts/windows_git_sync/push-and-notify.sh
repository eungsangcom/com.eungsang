#!/usr/bin/env bash
# 맥북: origin으로 push 후 윈도우 자동 pull 알림
#
# 사용:
#   ./scripts/windows_git_sync/push-and-notify.sh
#   ./scripts/windows_git_sync/push-and-notify.sh HEAD
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

REF="${1:-HEAD}"
git push origin "$REF"

"$ROOT/scripts/windows_git_sync/notify-windows-sync.sh"
