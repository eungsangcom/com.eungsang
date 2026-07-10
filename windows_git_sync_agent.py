"""Git 자동 동기화 에이전트 (Windows / Mac 공용).

상대 머신에서 push 하면:
  1) 주기 fetch/pull (기본 30초)
  2) POST /sync 즉시 동기화 (권장)

수동:
    python windows_git_sync_agent.py

Windows 작업 스케줄러:
    scripts/windows_git_sync/install_task.ps1

Mac launchd:
    scripts/mac_git_sync/install_launchd.sh
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

import uvicorn
from fastapi import FastAPI
from fastapi.responses import JSONResponse

_HERE = Path(__file__).resolve().parent


def _env(*names: str, default: str) -> str:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    return default


REPO_ROOT = Path(
    _env("GIT_SYNC_REPO", "WINDOWS_GIT_SYNC_REPO", "MAC_GIT_SYNC_REPO", default=str(_HERE))
).expanduser()
BRANCH = _env("GIT_SYNC_BRANCH", "WINDOWS_GIT_SYNC_BRANCH", "MAC_GIT_SYNC_BRANCH", default="main")
POLL_SECONDS = int(
    _env(
        "GIT_SYNC_POLL_SECONDS",
        "WINDOWS_GIT_SYNC_POLL_SECONDS",
        "MAC_GIT_SYNC_POLL_SECONDS",
        default="30",
    )
)
PORT = int(_env("GIT_SYNC_PORT", "WINDOWS_GIT_SYNC_PORT", "MAC_GIT_SYNC_PORT", default="8426"))
SERVICE = _env(
    "GIT_SYNC_SERVICE",
    "WINDOWS_GIT_SYNC_SERVICE",
    "MAC_GIT_SYNC_SERVICE",
    default="git-sync",
)
LOG_DIR = Path(
    _env(
        "GIT_SYNC_LOG_DIR",
        "WINDOWS_GIT_SYNC_LOG_DIR",
        "MAC_GIT_SYNC_LOG_DIR",
        default=str(_HERE / "scripts" / "windows_git_sync" / "logs"),
    )
)
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / "sync.log"
STATE_FILE = LOG_DIR / "last_sync.json"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(SERVICE)

app = FastAPI(title=SERVICE)
_lock = threading.Lock()
_last: dict = {}


def _git(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=check,
    )


def _save_state(payload: dict) -> None:
    global _last
    _last = payload
    STATE_FILE.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def sync_repo(*, reason: str = "poll") -> dict:
    if not _lock.acquire(blocking=False):
        return {"ok": False, "skipped": True, "reason": "busy"}

    try:
        if not (REPO_ROOT / ".git").exists():
            raise RuntimeError(f"not a git repo: {REPO_ROOT}")

        logger.info("sync start reason=%s repo=%s branch=%s", reason, REPO_ROOT, BRANCH)
        _git(["fetch", "origin", BRANCH])

        local = _git(["rev-parse", "HEAD"]).stdout.strip()
        remote = _git(["rev-parse", f"origin/{BRANCH}"]).stdout.strip()

        if local == remote:
            result = {
                "ok": True,
                "changed": False,
                "local": local,
                "remote": remote,
                "reason": reason,
                "synced_at": datetime.now(timezone.utc).isoformat(),
            }
            _save_state(result)
            logger.info("already up to date %s", local[:7])
            return result

        dirty = _git(["status", "--porcelain"], check=False).stdout.strip()
        if dirty:
            logger.warning("dirty working tree; refusing pull")
            result = {
                "ok": False,
                "changed": False,
                "error": "dirty working tree",
                "local": local,
                "remote": remote,
                "reason": reason,
                "synced_at": datetime.now(timezone.utc).isoformat(),
            }
            _save_state(result)
            return result

        pull = _git(["pull", "--ff-only", "origin", BRANCH])
        logger.info("pulled: %s", (pull.stdout or pull.stderr).strip())

        sub = _git(["submodule", "update", "--init", "--recursive"], check=False)
        if sub.returncode != 0:
            logger.warning("submodule update: %s", (sub.stdout or sub.stderr).strip())
        else:
            logger.info("submodules updated")

        after = _git(["rev-parse", "HEAD"]).stdout.strip()
        result = {
            "ok": True,
            "changed": True,
            "previous": local,
            "local": after,
            "remote": remote,
            "reason": reason,
            "synced_at": datetime.now(timezone.utc).isoformat(),
        }
        _save_state(result)
        logger.info("sync done %s -> %s", local[:7], after[:7])
        return result
    except Exception as exc:
        logger.exception("sync failed")
        result = {
            "ok": False,
            "changed": False,
            "error": str(exc),
            "reason": reason,
            "synced_at": datetime.now(timezone.utc).isoformat(),
        }
        _save_state(result)
        return result
    finally:
        _lock.release()


def _poll_loop() -> None:
    while True:
        try:
            sync_repo(reason="poll")
        except Exception:
            logger.exception("poll loop error")
        time.sleep(max(5, POLL_SECONDS))


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "service": SERVICE,
        "repo": str(REPO_ROOT),
        "branch": BRANCH,
        "poll_seconds": POLL_SECONDS,
    }


@app.get("/status")
def status() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    return {"ok": True, "message": "no sync yet", **_last}


@app.post("/sync")
def sync_now():
    result = sync_repo(reason="http")
    status_code = 200 if result.get("ok") else 409
    return JSONResponse(content=result, status_code=status_code)


def main() -> None:
    logger.info(
        "starting %s port=%s repo=%s branch=%s poll=%ss",
        SERVICE,
        PORT,
        REPO_ROOT,
        BRANCH,
        POLL_SECONDS,
    )
    # first sync before serving
    sync_repo(reason="startup")
    threading.Thread(target=_poll_loop, name="git-sync-poll", daemon=True).start()
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")


if __name__ == "__main__":
    main()
