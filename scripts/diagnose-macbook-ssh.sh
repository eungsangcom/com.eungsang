#!/usr/bin/env bash
# 맥북에서: 맥미니 SSH 연결 진단
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS="${ROOT}/scripts/.macmini-ssh-status.txt"

echo "==> 맥북 SSH config (Host macmini)"
grep -A6 '^Host macmini$' "${HOME}/.ssh/config" 2>/dev/null || echo "(config 없음)"

if [[ -f "$STATUS" ]]; then
  echo ""
  echo "==> 맥미니가 쓴 상태 파일 (Synology Drive)"
  cat "$STATUS"
else
  echo ""
  echo "==> 상태 파일 없음: 맥미니에서 ./scripts/macmini-install-authorized-key.sh 실행 필요"
fi

echo ""
echo "==> SSH 테스트 (publickey만)"
if ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o ConnectTimeout=8 \
  -i "${HOME}/.ssh/id_ed25519_macmini" macmini 'hostname' 2>&1; then
  echo "OK"
else
  echo ""
  echo "실패 시 맥미니에서:"
  echo "  cd \"${ROOT}\""
  echo "  ./scripts/macmini-install-authorized-key.sh"
  echo "  ./scripts/macmini-diagnose-ssh.sh"
  echo "  cat scripts/.macmini-ssh-status.txt  # User 이름 확인 후 맥북 config 수정"
fi
