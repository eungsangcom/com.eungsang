#!/usr/bin/env bash
# 대안 1: 맥북 셸에서 DOCKER_HOST=ssh://macmini 로 맥미니 Docker 데몬 사용
# 사용: source scripts/macmini-docker-env.sh
#
# 전제: ~/.ssh/config 에 macmini 호스트 등록 (scripts/ssh-config-macmini.snippet 참고)

: "${MACMINI_SSH_HOST:=macmini}"

export DOCKER_HOST="ssh://${MACMINI_SSH_HOST}"

echo "DOCKER_HOST=${DOCKER_HOST} (맥미니 Docker 데몬)"
echo "로컬 docker compose / docker 명령이 맥미니로 전달됩니다."
echo "해제: unset DOCKER_HOST"
