#!/usr/bin/env bash
# ★ 맥미니 본체 터미널에서 실행 ★
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS="${ROOT}/scripts/.macmini-ssh-status.txt"
PUB="${SCRIPT_DIR}/macmini-authorized-key.pub"
AUTH="${HOME}/.ssh/authorized_keys"

{
  echo "=== macmini SSH 진단 $(date -Iseconds) ==="
  echo "hostname: $(hostname -s)"
  echo "whoami: $(whoami)"
  echo "home: $HOME"
  echo "home_perms: $(stat -f '%Lp' "$HOME" 2>/dev/null || stat -c '%a' "$HOME" 2>/dev/null || echo '?')"
  echo ""
  echo "--- Remote Login ---"
  systemsetup -getremotelogin 2>/dev/null || echo "(systemsetup 실패 — 관리자 권한 필요)"
  if dscl . -read /Groups/com.apple.access_ssh GroupMembership 2>/dev/null; then
    :
  else
    echo "com.apple.access_ssh: (없음 또는 읽기 실패)"
  fi
  echo ""
  echo "--- ~/.ssh ---"
  if [[ -d "${HOME}/.ssh" ]]; then
    ls -la "${HOME}/.ssh"
  else
    echo "~/.ssh 없음"
  fi
  echo ""
  echo "--- authorized_keys (macbook 키 포함 여부) ---"
  if [[ -f "$AUTH" ]]; then
    if grep -q 'macbook-to-macmini' "$AUTH" 2>/dev/null; then
      echo "OK: macbook-to-macmini 키 있음"
    else
      echo "MISSING: macbook-to-macmini 키 없음"
    fi
    wc -l < "$AUTH" | xargs echo "lines:"
  else
    echo "MISSING: authorized_keys 파일 없음"
  fi
  echo ""
  echo "--- Tailscale IP ---"
  if command -v tailscale >/dev/null 2>&1; then
    tailscale ip -4 2>/dev/null || true
  else
    echo "(tailscale CLI 없음)"
  fi
  echo ""
  echo "--- localhost SSH 자가 테스트 ---"
  if ssh -o BatchMode=yes -o ConnectTimeout=3 -i "$PUB" "$(whoami)@127.0.0.1" 'echo ok' 2>/dev/null; then
    echo "localhost: OK"
  else
    echo "localhost: FAIL (키·sshd 설정 재확인)"
  fi
} | tee "$STATUS"

echo ""
echo "상태 파일 (Synology Drive → 맥북에서 읽기):"
echo "  $STATUS"
