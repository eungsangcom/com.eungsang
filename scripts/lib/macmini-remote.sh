#!/usr/bin/env bash
# 맥북 → 맥미니 SSH / Docker 원격 실행 공통 설정
# 사용: source "$(dirname "$0")/lib/macmini-remote.sh"

: "${MACMINI_SSH_HOST:=macmini}"
: "${MACMINI_SSH_USER:=leeeunsang}"
: "${MACMINI_TAILSCALE_IP:=100.84.118.21}"
: "${MACMINI_PROJECT_DIR:=/Volumes/project/eungsang.com/deploy}"
: "${MACMINI_COMPOSE_FILE:=Docker-compose.yaml}"

# 맥미니 본체에서 직접 실행할 때만 1 (맥미니 ~/.zshrc 등)
: "${MACMINI_LOCAL:=0}"

_macmini_ssh_target() {
  printf '%s@%s' "$MACMINI_SSH_USER" "$MACMINI_SSH_HOST"
}

macmini_is_local() {
  [[ "$MACMINI_LOCAL" == "1" ]]
}

macmini_ssh() {
  ssh "$(_macmini_ssh_target)" "$@"
}

macmini_exec() {
  local cmd=$1
  # 비대화형 SSH는 PATH 미로드 → login shell로 docker 등 실행
  local wrapped="zsh -lic $(printf %q "$cmd")"
  if macmini_is_local; then
    zsh -lic "$cmd"
  else
    macmini_ssh "$wrapped"
  fi
}

macmini_docker() {
  if macmini_is_local; then
    docker "$@"
  else
    macmini_ssh "zsh -lic $(printf %q "docker $*")"
  fi
}

macmini_compose() {
  macmini_exec "cd $(printf %q "$MACMINI_PROJECT_DIR") && docker compose -f $(printf %q "$MACMINI_PROJECT_DIR/$MACMINI_COMPOSE_FILE") $*"
}
