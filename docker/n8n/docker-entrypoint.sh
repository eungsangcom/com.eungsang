#!/bin/sh
set -e

WORKFLOW_VERSION="v3"

import_and_publish_workflow() {
  marker="$1"
  workflow="$2"
  workflow_id="$3"
  name="$4"

  if [ ! -f "$workflow" ]; then
    echo "[n8n-entrypoint] ${name} 파일 없음: $workflow" >&2
    return 0
  fi

  if [ ! -f "$marker" ]; then
    echo "[n8n-entrypoint] ${name} 워크플로 import (${WORKFLOW_VERSION})..."
    if n8n import:workflow --input="$workflow"; then
      touch "$marker"
      echo "[n8n-entrypoint] ${name} import 완료"
    else
      echo "[n8n-entrypoint] ${name} import 실패 (n8n UI에서 수동 import 가능)" >&2
      return 0
    fi
  fi

  echo "[n8n-entrypoint] ${name} publish..."
  if n8n publish:workflow --id="$workflow_id"; then
    echo "[n8n-entrypoint] ${name} publish 완료"
  else
    echo "[n8n-entrypoint] ${name} publish 실패 — n8n UI에서 워크플로를 활성화해 주세요." >&2
  fi
}

import_and_publish_workflow \
  "/home/node/.n8n/.relay_faker_email_imported_${WORKFLOW_VERSION}" \
  "/import/workflows/relay-faker-email.json" \
  "RelayFakerEmailWorkflow" \
  "relay-faker-email"

import_and_publish_workflow \
  "/home/node/.n8n/.relay_spam_classify_imported_${WORKFLOW_VERSION}" \
  "/import/workflows/relay-spam-classify.json" \
  "RelaySpamClassifyWorkflow" \
  "relay-spam-classify"

exec n8n start
