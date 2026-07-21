# 맥북 GPU 폴백 서비스

윈도우 GPU PC가 꺼져 있고 맥북이 켜져 있을 때, 맥미니 백엔드가 **임베딩·LLM 추론**을 맥북 Tailscale IP로 자동 전환합니다.

## 맥미니 `.env` (필수)

```env
GPU_FALLBACK_ENABLED=1
MACBOOK_GPU_HOST=100.118.66.51
# Windows와 동일 포트 — Tailscale로 맥북에 접속
# WINDOWS_EMBED_URL / OLLAMA_HOST / SIGLIP_URL 은 기존 윈도우 주소 유지
```

라우팅 확인: `GET /facility/gpu/routing` (관리자)

## 설비 담당 원격 제어 (맥미니 → 맥북)

```bash
./install_agent_launchd.sh   # :8425 제어 에이전트
curl -sS http://127.0.0.1:8425/health
```

맥미니 `.env`: `MACBOOK_METRICS_URL`, `MACBOOK_CONTROL_TOKEN` (또는 `WINDOWS_CONTROL_TOKEN` 공유)

대화 예: "맥북 임베딩 켜줘", "윈도우 SigLIP 꺼줘", "양쪽 올라마 켜줘"

## 맥북 1회 설치

```bash
cd ~/dev/com.eungsang/scripts/macbook_gpu
chmod +x *.sh
./install_launchd.sh
./install_ollama_launchd.sh   # Ollama 0.0.0.0:11434 (Tailscale 원격)
./install_siglip_launchd.sh
```

기동 확인:

```bash
curl -sS http://127.0.0.1:8420/health   # KURE 임베딩
curl -sS http://127.0.0.1:11434/api/tags  # Ollama
```

## 서비스

| 포트 | 서비스 | 스크립트 |
|------|--------|----------|
| 8420 | KURE-v1 임베딩 | `windows_kure_embed_server.py` |
| 11434 | Ollama LLM | `install_ollama_launchd.sh` (`OLLAMA_HOST=0.0.0.0`) |
| 8437 | SigLIP / NIMA 프록시 | `install_siglip_launchd.sh` |

> **8427** 은 `mac_git_sync` 전용입니다. SigLIP·NIMA는 **8437** (윈도우·맥북 동일).

SigLIP 설치:

```bash
./install_siglip_launchd.sh
curl -sS http://127.0.0.1:8437/health
```

## Ollama 모델 (윈도우와 동일 권장)

```bash
ollama pull qwen2.5:14b
ollama pull qwen2.5-coder:14b
```

## 수동 기동

```bash
./start-gpu-services.sh
```

## 제거

```bash
./uninstall_launchd.sh
```

로그: `scripts/macbook_gpu/logs/`
