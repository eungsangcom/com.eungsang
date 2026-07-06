#!/usr/bin/env bash
# 맥북 최초 1회: ~/.ssh/config 생성 + macmini 호스트 등록
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SNIPPET="$SCRIPT_DIR/ssh-config-macmini.snippet"
SSH_DIR="${HOME}/.ssh"
CONFIG="${SSH_DIR}/config"

if [[ ! -f "$SNIPPET" ]]; then
  echo "스니펫 없음: $SNIPPET" >&2
  echo "com.ragwatson 루트에서 실행하세요: ./scripts/setup-macmini-ssh.sh" >&2
  exit 1
fi

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ ! -f "$CONFIG" ]]; then
  touch "$CONFIG"
  chmod 600 "$CONFIG"
  echo "생성: $CONFIG"
fi

if grep -q '^Host macmini$' "$CONFIG" 2>/dev/null; then
  echo "이미 등록됨: Host macmini ($CONFIG)"
else
  echo "" >> "$CONFIG"
  echo "# com.ragwatson — 맥미니 Docker (Tailscale)" >> "$CONFIG"
  cat "$SNIPPET" >> "$CONFIG"
  echo "추가 완료: Host macmini → $(grep '^  HostName' "$SNIPPET" | awk '{print $2}')"
fi

echo ""
echo "다음: ssh macmini"
echo "  (최초 연결 시 'yes' 입력 → 호스트 키 등록)"
echo "확인: ssh macmini 'hostname && docker ps --format \"{{.Names}}\"'"
