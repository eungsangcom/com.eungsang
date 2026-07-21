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
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import uvicorn
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

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

_CONTROL_TOKEN = os.getenv("WINDOWS_CONTROL_TOKEN", os.getenv("GIT_SYNC_CONTROL_TOKEN", "")).strip()

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


def _pids_on_port(port: int) -> list[int]:
    if sys.platform == "win32":
        try:
            import psutil

            pids: set[int] = set()
            for conn in psutil.net_connections(kind="inet"):
                if not conn.laddr or conn.laddr.port != port:
                    continue
                if conn.status != psutil.CONN_LISTEN:
                    continue
                if conn.pid:
                    pids.add(conn.pid)
            if pids:
                return sorted(pids)
        except Exception:
            pass
        try:
            out = subprocess.run(
                ["netstat", "-ano"],
                capture_output=True,
                text=True,
                check=False,
            )
            pids = set()
            for line in out.stdout.splitlines():
                upper = line.upper()
                if f":{port}" not in line or "LISTENING" not in upper:
                    continue
                parts = line.split()
                if parts and parts[-1].isdigit():
                    pids.add(int(parts[-1]))
            return sorted(pids)
        except OSError:
            return []

    try:
        out = subprocess.run(
            ["lsof", "-ti", f":{port}"],
            capture_output=True,
            text=True,
            check=False,
        )
        return [int(pid) for pid in out.stdout.split() if pid.strip().isdigit()]
    except OSError:
        return []


def _kill_pid(pid: int) -> None:
    try:
        if sys.platform == "win32":
            subprocess.run(["taskkill", "/PID", str(pid), "/F"], check=False, capture_output=True)
        else:
            os.kill(pid, 15)
    except OSError:
        pass


def _assert_control_auth(authorization: Optional[str]) -> None:
    if not _CONTROL_TOKEN:
        return
    expected = f"Bearer {_CONTROL_TOKEN}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="인증 토큰이 올바르지 않습니다.")


def _start_metrics_agent(*, force_restart: bool = False) -> dict:
    """윈도우 메트릭 에이전트(:8425)를 작업 스케줄러 또는 직접 기동."""
    port = int(os.getenv("METRICS_AGENT_PORT", "8425"))
    task_name = os.getenv("WINDOWS_METRICS_TASK", "Eungsang-WindowsMetricsAgent").strip()
    wait_sec = float(os.getenv("METRICS_AGENT_START_WAIT_SEC", "45"))

    pids = _pids_on_port(port)
    if pids and not force_restart:
        return {
            "ok": True,
            "alreadyRunning": True,
            "port": port,
            "pids": pids,
        }

    if pids:
        for pid in pids:
            _kill_pid(pid)
        time.sleep(1.5)

    started = False
    method: str | None = None
    if sys.platform == "win32" and task_name:
        proc = subprocess.run(
            ["schtasks", "/Run", "/TN", task_name],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        if proc.returncode == 0:
            started = True
            method = "scheduled-task"

    if not started:
        agent_py = REPO_ROOT / "windows_metrics_agent.py"
        if agent_py.is_file():
            creationflags = 0
            if sys.platform == "win32":
                creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
            subprocess.Popen(
                [sys.executable, str(agent_py)],
                cwd=str(REPO_ROOT),
                creationflags=creationflags,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            started = True
            method = "direct"

    if not started:
        return {
            "ok": False,
            "error": "메트릭 에이전트 기동 방법을 찾지 못했습니다 (작업 스케줄러·windows_metrics_agent.py).",
            "port": port,
        }

    deadline = time.time() + max(5.0, wait_sec)
    while time.time() < deadline:
        live = _pids_on_port(port)
        if live:
            return {
                "ok": True,
                "started": True,
                "alreadyRunning": False,
                "port": port,
                "method": method,
                "pids": live,
            }
        time.sleep(1.0)

    return {
        "ok": False,
        "error": f"포트 {port}에서 메트릭 에이전트 응답 대기 시간 초과",
        "port": port,
        "method": method,
    }


def _restart_metrics_agent_if_needed(previous: str, after: str) -> dict | None:
    if previous == after:
        return None

    changed = _git(["diff", "--name-only", previous, after], check=False).stdout
    if "windows_metrics_agent.py" not in changed:
        return None

    port = int(os.getenv("METRICS_AGENT_PORT", "8425"))
    killed = _pids_on_port(port)
    for pid in killed:
        _kill_pid(pid)
    time.sleep(1.5)

    result = _start_metrics_agent(force_restart=True)
    info = {
        "metricsAgentRestarted": bool(result.get("ok")),
        "metricsAgentPort": port,
        "killedPids": killed,
        "task": os.getenv("WINDOWS_METRICS_TASK", "Eungsang-WindowsMetricsAgent").strip() or None,
        **{k: result[k] for k in ("method", "error") if k in result},
    }
    logger.info("metrics agent restart: %s", info)
    return info


def _save_state(payload: dict) -> None:
    global _last
    _last = payload
    STATE_FILE.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def sync_repo(*, reason: str = "poll", force: bool = False) -> dict:
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
            if not force:
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
            stash = _git(["stash", "push", "-u", "-m", f"git-sync auto-stash ({reason})"], check=False)
            logger.warning("dirty working tree; stashed before pull: %s", (stash.stdout or stash.stderr).strip())

        pull = _git(["pull", "--ff-only", "origin", BRANCH])
        logger.info("pulled: %s", (pull.stdout or pull.stderr).strip())

        sub = _git(["submodule", "update", "--init", "--recursive"], check=False)
        if sub.returncode != 0:
            logger.warning("submodule update: %s", (sub.stdout or sub.stderr).strip())
        else:
            logger.info("submodules updated")

        after = _git(["rev-parse", "HEAD"]).stdout.strip()
        restart_info = _restart_metrics_agent_if_needed(local, after)
        result = {
            "ok": True,
            "changed": True,
            "previous": local,
            "local": after,
            "remote": remote,
            "reason": reason,
            "synced_at": datetime.now(timezone.utc).isoformat(),
        }
        if restart_info:
            result["metricsAgent"] = restart_info
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



class SyncRequest(BaseModel):
    force: bool = Field(default=False, description="dirty working tree 일 때 stash 후 pull")


@app.post("/sync")
def sync_now(body: SyncRequest = SyncRequest()):
    result = sync_repo(reason="http", force=body.force)
    status_code = 200 if result.get("ok") else 409
    return JSONResponse(content=result, status_code=status_code)


@app.post("/services/metrics-agent/start")
def start_metrics_agent(authorization: Optional[str] = Header(default=None)) -> dict:
    """메트릭 에이전트(:8425) 기동 — 에이전트가 꺼져 있을 때 git sync 경유 원격 제어."""
    _assert_control_auth(authorization)
    result = _start_metrics_agent()
    status_code = 200 if result.get("ok") else 503
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
