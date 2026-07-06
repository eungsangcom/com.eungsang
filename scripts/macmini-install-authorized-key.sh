#!/usr/bin/env bash
# ★ 맥미니 본체 터미널에서 실행 (SSH 없이) ★
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PUB="${SCRIPT_DIR}/macmini-authorized-key.pub"
AUTH="${HOME}/.ssh/authorized_keys"
STATUS="${ROOT}/scripts/.macmini-ssh-status.txt"

if [[ ! -f "$PUB" ]]; then
  echo "공개키 없음: $PUB" >&2
  echo "Synology Drive 동기화 대기 후 다시 실행하세요." >&2
  exit 1
fi

# SSH 는 홈 디렉터리·.ssh 권한에 민감함
chmod go-w "$HOME" 2>/dev/null || true
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
touch "$AUTH"
chmod 600 "$AUTH"

KEY_LINE="$(grep -v '^[[:space:]]*$' "$PUB" | head -1)"
if grep -qF 'macbook-to-macmini' "$AUTH" 2>/dev/null; then
  echo "이미 등록됨: macbook-to-macmini"
else
  echo "$KEY_LINE" >> "$AUTH"
  echo "등록 완료: $AUTH"
fi

# 원격 로그인 켜기 (관리자 비밀번호 필요)
if systemsetup -getremotelogin 2>/dev/null | grep -q Off; then
  echo ""
  echo "원격 로그인이 꺼져 있습니다. 켜려면:"
  echo "  sudo systemsetup -setremotelogin on"
  echo "또는: 시스템 설정 → 일반 → 공유 → 원격 관리 ON"
fi

MINI_USER="$(whoami)"
MINI_HOST="$(hostname -s)"
TS_IP=""
command -v tailscale >/dev/null 2>&1 && TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"

{
  echo "installed_at=$(date -Iseconds)"
  echo "user=${MINI_USER}"
  echo "hostname=${MINI_HOST}"
  echo "tailscale_ip=${TS_IP:-unknown}"
  echo "pubkey=registered"
  echo ""
  echo "맥북 ~/.ssh/config 의 User 를 아래와 같이 설정:"
  echo "  User ${MINI_USER}"
} | tee "$STATUS"

echo ""
echo "=== 맥미니 사용자: ${MINI_USER} @ ${MINI_HOST} ==="
echo "Tailscale: ${TS_IP:-(확인 불가)}"
echo ""
echo "진단 실행:"
echo "  ./scripts/macmini-diagnose-ssh.sh"
echo ""
echo "맥북에서 (동기화 후):"
echo "  cat scripts/.macmini-ssh-status.txt"
echo "  ssh ${MINI_USER}@100.84.118.21 hostname"
