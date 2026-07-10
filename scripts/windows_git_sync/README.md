# 윈도우 git 자동 pull

맥북에서 push하면 윈도우 `G:\project\com.eungsang`이 자동으로 `origin/main`을 따라갑니다.

반대 방향(윈도우 → 맥북)은 [`scripts/mac_git_sync/README.md`](../mac_git_sync/README.md) 참고.

## 동작

1. **폴링** — 30초마다 `git fetch` → 뒤처지면 `pull --ff-only` + submodule update  
2. **즉시 동기화** — `POST http://100.102.174.81:8426/sync` (맥북 push 직후)

로컬 변경이 있으면 pull을 **거부**합니다(덮어쓰기 방지).

## 윈도우 1회 설치

PowerShell:

```powershell
cd G:\project\com.eungsang\scripts\windows_git_sync
Set-ExecutionPolicy -Scope Process Bypass

# (관리자) 방화벽
.\open_firewall_port.ps1

# 로그온 시 자동 기동
.\install_task.ps1

# 바로 테스트
Start-ScheduledTask -TaskName 'Eungsang-WindowsGitSync'
Invoke-WebRequest http://127.0.0.1:8426/health
Invoke-WebRequest -Method POST http://127.0.0.1:8426/sync
```

수동 실행:

```powershell
.\run_agent.ps1
```

선택: `config.cmd.example` → `config.cmd` 복사 후 `PY` / 포트 지정.

로그: `scripts/windows_git_sync/logs/sync.log`

## 맥북에서 push 후 알림

```bash
# 일반
git push && ./scripts/windows_git_sync/notify-windows-sync.sh

# 한 번에
./scripts/windows_git_sync/push-and-notify.sh
```

Tailscale IP가 다르면:

```bash
WINDOWS_GIT_SYNC_URL=http://100.102.174.81:8426/sync ./scripts/windows_git_sync/notify-windows-sync.sh
```

알림이 실패해도 폴링이 ~30초 안에 pull합니다.

## 윈도우에서 push 후 맥북 알림

```powershell
git push; .\scripts\windows_git_sync\notify-mac-sync.ps1
.\scripts\windows_git_sync\push-and-notify-mac.ps1
```

## API

| Method | Path | 설명 |
|--------|------|------|
| GET | `/health` | 에이전트 상태 |
| GET | `/status` | 마지막 sync 결과 |
| POST | `/sync` | 즉시 fetch/pull |

## 사전 조건 (윈도우)

- `git` PATH 등록
- `origin` remotes가 맥북과 동일 (SSH key 또는 HTTPS credential)
- working tree가 clean 해야 pull 성공
