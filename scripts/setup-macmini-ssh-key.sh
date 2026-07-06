#!/usr/bin/env bash
# 맥북 → 맥미니 SSH 키 인증 설정 (Connection closed by … 해결)
set -euo pipefail

KEY="${HOME}/.ssh/id_ed25519_macmini"
PUB="${KEY}.pub"
SSH_DIR="${HOME}/.ssh"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ ! -f "$KEY" ]]; then
  echo "==> SSH 키 생성: $KEY"
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "macbook-to-macmini"
else
  echo "==> 기존 키 사용: $KEY"
fi

# ~/.ssh/config 에 IdentityFile 반영
CONFIG="${SSH_DIR}/config"
if [[ -f "$CONFIG" ]] && grep -q '^Host macmini$' "$CONFIG"; then
  if ! grep -A5 '^Host macmini$' "$CONFIG" | grep -q 'id_ed25519_macmini'; then
    # macmini 블록에 IdentityFile 추가 (간단 치환)
    if grep -A5 '^Host macmini$' "$CONFIG" | grep -q '# IdentityFile'; then
      sed -i '' 's|# IdentityFile ~/.ssh/id_ed25519|IdentityFile ~/.ssh/id_ed25519_macmini|' "$CONFIG" 2>/dev/null || \
        sed -i 's|# IdentityFile ~/.ssh/id_ed25519|IdentityFile ~/.ssh/id_ed25519_macmini|' "$CONFIG"
    else
      awk '/^Host macmini$/{print; print "  IdentityFile ~/.ssh/id_ed25519_macmini"; print "  IdentitiesOnly yes"; next}1' \
        "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
    fi
    echo "==> ~/.ssh/config 에 IdentityFile 추가됨"
  fi
fi

chmod 600 "$KEY" "$PUB"
chmod 600 "$CONFIG" 2>/dev/null || true

echo ""
echo "==> 공개키 (맥미니에 등록 필요):"
echo ""
cat "$PUB"
echo ""
echo "────────────────────────────────────────"
echo "다음 중 하나를 진행하세요."
echo ""
echo "[A] 맥미니에서 비밀번호 로그인이 되면 (맥북):"
echo "    ssh-copy-id -i $PUB macmini"
echo ""
echo "[B] 맥미니 화면 앞에 있으면 (맥미니 터미널):"
echo "    mkdir -p ~/.ssh && chmod 700 ~/.ssh"
echo "    echo '$(cat "$PUB")' >> ~/.ssh/authorized_keys"
echo "    chmod 600 ~/.ssh/authorized_keys"
echo ""
echo "[C] 맥미니 Remote Login 확인:"
echo "    시스템 설정 → 일반 → 공유 → 원격 관리(또는 원격 로그인) ON"
echo "    사용자 'ieunsang' 허용 목록에 포함"
echo ""
echo "등록 후 확인 (맥북):"
echo "    ssh macmini 'hostname'"
echo "    ./scripts/compose-mini.sh ps"
