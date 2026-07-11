# Windows GPU 서비스 기동 (Ollama · KURE 임베딩)

설비 담당 에이전트·맥미니 백엔드가 Tailscale로 원격 기동할 때 사용하는 작업 스케줄러 등록 스크립트입니다.

## 1회 설치 (윈도우 PC)

```powershell
Set-ExecutionPolicy -Scope Process Bypass
cd C:\path\to\com.eungsang\scripts\windows_services
.\install_tasks.ps1
```

등록되는 작업:
- `Eungsang-Ollama` — `ollama serve` (:11434)
- `Eungsang-KureEmbed` — `windows_kure_embed_server.py` (:8420)

## 수동 기동

```powershell
Start-ScheduledTask -TaskName Eungsang-Ollama
Start-ScheduledTask -TaskName Eungsang-KureEmbed
```

## 원격 기동 (맥미니 → 윈도우)

`windows_metrics_agent.py` (:8425) 에 `POST /services/start` 가 추가되어 있습니다.

```bash
curl -X POST "http://100.102.174.81:8425/services/start" \
  -H "Authorization: Bearer $WINDOWS_CONTROL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"service":"embedding"}'
```

`service`: `ollama` | `embedding` | `all`

## 환경 변수 (윈도우)

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `WINDOWS_CONTROL_TOKEN` | (없음) | 설정 시 Bearer 토큰 필수 |
| `WINDOWS_OLLAMA_TASK` | `Eungsang-Ollama` | 작업 스케줄러 이름 |
| `WINDOWS_EMBED_TASK` | `Eungsang-KureEmbed` | 작업 스케줄러 이름 |
| `WINDOWS_OLLAMA_START_CMD` | (작업 스케줄러) | 직접 실행 명령 fallback |
| `WINDOWS_EMBED_START_CMD` | python windows_kure_embed_server.py | 직접 실행 명령 fallback |

맥미니 `.env`에도 동일한 `WINDOWS_CONTROL_TOKEN` 을 설정하세요.
