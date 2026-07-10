# 맥북 git 자동 pull

윈도우에서 push하면 맥북 `~/dev/com.eungsang`이 자동으로 `origin/macbook`을 따라갑니다.

## 동작

1. **폴링** — 30초마다 `git fetch` → 뒤처지면 `pull --ff-only` + submodule update
2. **즉시 동기화** — `POST http://100.118.66.51:8427/sync` (윈도우 push 직후)

로컬 변경이 있으면 pull을 **거부**합니다(덮어쓰기 방지).

포트: **8427** (윈도우 에이전트 8426과 분리)

## 맥북 1회 설치

```bash
cd ~/dev/com.eungsang/scripts/mac_git_sync
chmod +x *.sh
./install_launchd.sh

curl -sS http://127.0.0.1:8427/health
curl -sS -X POST http://127.0.0.1:8427/sync
```

제거:

```bash
./uninstall_launchd.sh
```

로그: `scripts/mac_git_sync/logs/`

## 윈도우에서 push 후 알림

```powershell
# 일반
git push; .\scripts\windows_git_sync\notify-mac-sync.ps1

# 한 번에
.\scripts\windows_git_sync\push-and-notify-mac.ps1
```

Tailscale IP가 다르면:

```powershell
$env:MAC_GIT_SYNC_URL = "http://100.118.66.51:8427/sync"
.\scripts\windows_git_sync\notify-mac-sync.ps1
```

알림이 실패해도 폴링이 ~30초 안에 pull합니다.

## API

| Method | Path | 설명 |
|--------|------|------|
| GET | `/health` | 에이전트 상태 |
| GET | `/status` | 마지막 sync 결과 |
| POST | `/sync` | 즉시 fetch/pull |
