# 윈도우 메트릭 에이전트

설비실 대시보드용. CPU·RAM·디스크·GPU·서비스(Ollama/임베딩) 상태를 `:8425/metrics`로 노출.

**원격 서비스 기동·중지** (`POST /services/start`, `POST /services/stop`) — 맥미니·설비 담당 에이전트가 Tailscale로 Ollama/임베딩을 켜거나 끌 수 있습니다.

## 원격 전원 제어

`POST /power/shutdown`, `POST /power/reboot` — PC가 켜져 있을 때 Tailscale로 종료·재부팅 예약 (`WINDOWS_CONTROL_TOKEN`).

맥미니 백엔드 `POST /facility/windows/power/wake` — WOL 매직 패킷 (`.env`의 `WINDOWS_WOL_MAC`, `WINDOWS_WOL_BROADCAST`).

설비 담당 에이전트·설비실 대시보드(최고 관리자): "윈도우 PC 켜줘", "윈도우 재부팅해줘", "윈도우 PC 꺼줘".

**WOL 전제:** BIOS Wake-on-LAN, 유선 LAN, 절전 시에도 WOL 허용. Tailscale만으로는 꺼진 PC를 깨울 수 없습니다.

## Ollama·임베딩 작업 스케줄러 (원격 기동용)

**먼저** `config.cmd` + `services\install_kure_deps.ps1` (아래 README 참고)

```powershell
cd G:\project\com.eungsang\scripts\windows_metrics_agent\services
# 상세: services\README.md
Set-ExecutionPolicy -Scope Process Bypass
.\install_service_tasks.ps1
```

등록: `Eungsang-Ollama`, `Eungsang-KureEmbed`  
맥미니 `.env` + 윈도우 환경 변수: `WINDOWS_CONTROL_TOKEN` (동일 값)

## 빠른 실행

PowerShell (conda `artimuse` 등 — **권장**):

```powershell
cd G:\project\com.eungsang\scripts\windows_metrics_agent
Set-ExecutionPolicy -Scope Process Bypass
.\run_agent.ps1
Invoke-WebRequest http://127.0.0.1:8425/health
```

또는 Python 직접 실행:

```powershell
cd G:\project\com.eungsang
pip install fastapi uvicorn psutil
python windows_metrics_agent.py
```

배치 (`run_agent.bat`)는 cmd 인코딩 이슈가 있으면 위 PowerShell 방식을 쓰세요.

## `config.cmd` (선택)

`config.cmd.example` → `config.cmd` 복사 후 **PY 경로만** 지정하면 됩니다.

```bat
set "PY=C:\Users\YOU\miniconda3\python.exe"
set "METRICS_AGENT_PORT=8425"
```

### 주의 — `'GPU'은(는) 내부 또는 외부 명령...` 오류

`config.cmd`에 **괄호 `()` 가 들어간 값을 따옴표 없이** 넣으면 cmd가 괄호 안을 명령으로 실행합니다.

```bat
REM 잘못된 예 (GPU 오류 발생)
set INFRASTRUCTURE_WINDOWS_LABEL=윈도우 (GPU 서버)

REM 올바른 예
set "INFRASTRUCTURE_WINDOWS_LABEL=윈도우 (GPU 서버)"
```

에이전트에는 `PY`·포트만 있으면 됩니다. `.env` 항목을 `config.cmd`에 복사하지 마세요.
문제 시 `config.cmd`를 삭제한 뒤 `run_agent.bat`을 다시 실행하세요.

## 자동 기동·방화벽

```powershell
.\open_firewall_port.ps1          # 관리자, TCP 8425
Set-ExecutionPolicy -Scope Process Bypass
.\install_task.ps1                # 로그온 시 자동 기동
```

로그: `logs\agent.log`
