"""맥북 GPU 폴백 서비스 제어 에이전트 — 설비실·설비 담당 에이전트용.

수동:
    pip install fastapi uvicorn psutil
    python macbook_gpu_agent.py

launchd 자동 기동:
    scripts/macbook_gpu/install_agent_launchd.sh

맥미니 백엔드가 Tailscale로 POST /services/start|stop 호출 (MACBOOK_METRICS_URL)
"""

from __future__ import annotations

import os
import platform
import socket
import subprocess
import time
from pathlib import Path
from typing import Optional

import psutil
import uvicorn
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

app = FastAPI()

_REPO_ROOT = Path(__file__).resolve().parent
_MACBOOK_GPU_SCRIPTS = _REPO_ROOT / "scripts" / "macbook_gpu"
_CONTROL_TOKEN = os.getenv("MACBOOK_CONTROL_TOKEN", os.getenv("WINDOWS_CONTROL_TOKEN", "")).strip()
_LAUNCHD_DOMAIN = f"gui/{os.getuid()}"
_STOP_WAIT_SEC = float(os.getenv("MACBOOK_SERVICE_STOP_WAIT_SEC", "30"))
_EMBED_START_WAIT_SEC = float(os.getenv("MACBOOK_EMBED_START_WAIT_SEC", "180"))
_OLLAMA_START_WAIT_SEC = float(os.getenv("MACBOOK_OLLAMA_START_WAIT_SEC", "45"))
_START_WAIT_SEC = float(os.getenv("MACBOOK_SERVICE_START_WAIT_SEC", "90"))

SERVICE_KEYS: tuple[str, ...] = ("ollama", "siglip", "nima", "embedding")

SERVICE_PORTS: list[tuple[str, int]] = [
    ("Ollama", int(os.getenv("METRICS_OLLAMA_PORT", "11434"))),
    ("임베딩", int(os.getenv("METRICS_EMBED_PORT", "8420"))),
    ("SigLIP", int(os.getenv("METRICS_SIGLIP_PORT", "8437"))),
    ("NIMA", int(os.getenv("METRICS_NIMA_PORT", "8428"))),
]

_SERVICE_CONFIG: dict[str, dict[str, object]] = {
    "ollama": {
        "label": "Ollama",
        "port": int(os.getenv("METRICS_OLLAMA_PORT", "11434")),
        "launchd": os.getenv("MACBOOK_OLLAMA_LAUNCHD", "com.eungsang.macbook-ollama").strip(),
        "launchd_labels": [
            label
            for label in [
                os.getenv("MACBOOK_OLLAMA_LAUNCHD", "com.eungsang.macbook-ollama").strip(),
                os.getenv("MACBOOK_OLLAMA_APP_LAUNCHD", "com.ollama.ollama").strip(),
            ]
            if label
        ],
        "plist": os.getenv(
            "MACBOOK_OLLAMA_PLIST",
            str(Path.home() / "Library/LaunchAgents/com.eungsang.macbook-ollama.plist"),
        ).strip(),
        "stop_killall": ["Ollama", "ollama"],
        "stop_quit_app": os.getenv("MACBOOK_OLLAMA_START_APP", "Ollama").strip(),
        "start_app": os.getenv("MACBOOK_OLLAMA_START_APP", "Ollama").strip(),
    },
    "embedding": {
        "label": "임베딩",
        "port": int(os.getenv("METRICS_EMBED_PORT", "8420")),
        "launchd": os.getenv("MACBOOK_EMBED_LAUNCHD", "com.eungsang.macbook-gpu").strip(),
        "plist": os.getenv(
            "MACBOOK_EMBED_PLIST",
            str(Path.home() / "Library/LaunchAgents/com.eungsang.macbook-gpu.plist"),
        ).strip(),
        "run_script": os.getenv(
            "MACBOOK_EMBED_RUN_SCRIPT",
            str(_MACBOOK_GPU_SCRIPTS / "run_embed.sh"),
        ).strip(),
        "stop_pgrep": ["windows_kure_embed_server.py", "run_embed.sh"],
    },
    "siglip": {
        "label": "SigLIP",
        "port": int(os.getenv("METRICS_SIGLIP_PORT", "8437")),
        "launchd": os.getenv("MACBOOK_SIGLIP_LAUNCHD", "com.eungsang.macbook-siglip").strip(),
        "plist": os.getenv(
            "MACBOOK_SIGLIP_PLIST",
            str(Path.home() / "Library/LaunchAgents/com.eungsang.macbook-siglip.plist"),
        ).strip(),
        "run_script": os.getenv(
            "MACBOOK_SIGLIP_RUN_SCRIPT",
            str(_MACBOOK_GPU_SCRIPTS / "run_siglip.sh"),
        ).strip(),
        "stop_pgrep": ["siglip_server.py", "run_siglip.sh"],
    },
    "nima": {
        "label": "NIMA",
        "port": int(os.getenv("METRICS_NIMA_PORT", "8428")),
        "launchd": os.getenv("MACBOOK_NIMA_LAUNCHD", "com.eungsang.macbook-nima").strip(),
        "plist": os.getenv(
            "MACBOOK_NIMA_PLIST",
            str(Path.home() / "Library/LaunchAgents/com.eungsang.macbook-nima.plist"),
        ).strip(),
        "run_script": os.getenv(
            "MACBOOK_NIMA_RUN_SCRIPT",
            str(_MACBOOK_GPU_SCRIPTS / "run_nima.sh"),
        ).strip(),
        "stop_pgrep": ["nima_server.py", "run_nima.sh"],
    },
}


class ServiceRequest(BaseModel):
    service: str = Field(..., description="ollama | siglip | nima | embedding | all")


def _assert_control_auth(authorization: Optional[str]) -> None:
    if not _CONTROL_TOKEN:
        return
    expected = f"Bearer {_CONTROL_TOKEN}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="인증 토큰이 올바르지 않습니다.")


def _port_open(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1.5):
            return True
    except OSError:
        return False


def _wait_port(port: int, *, timeout_sec: float) -> bool:
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        if _port_open(port):
            return True
        time.sleep(1.0)
    return False


def _wait_port_closed(port: int, *, timeout_sec: float) -> bool:
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        if not _port_open(port):
            return True
        time.sleep(1.0)
    return False


def _pids_on_port_lsof(port: int) -> list[int]:
    proc = subprocess.run(
        ["lsof", "-ti", f"TCP:{port}", "-sTCP:LISTEN"],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if proc.returncode != 0:
        return []
    pids: list[int] = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.isdigit():
            pids.append(int(line))
    return pids


def _pids_by_cmdline_substrings(patterns: list[str] | tuple[str, ...]) -> list[int]:
    needles = [p for p in patterns if p]
    if not needles:
        return []
    pids: set[int] = set()
    for proc in psutil.process_iter(["pid", "cmdline"]):
        try:
            cmdline = proc.info.get("cmdline") or []
        except (psutil.Error, PermissionError):
            continue
        joined = " ".join(str(part) for part in cmdline)
        if any(needle in joined for needle in needles):
            pid = proc.info.get("pid")
            if pid:
                pids.add(int(pid))
    return sorted(pids)


def _pids_listening_on_port(port: int) -> list[int]:
    pids: set[int] = set()
    try:
        for conn in psutil.net_connections(kind="inet"):
            try:
                laddr = conn.laddr
                if not laddr or laddr.port != port:
                    continue
                if conn.status != psutil.CONN_LISTEN:
                    continue
                if conn.pid:
                    pids.add(conn.pid)
            except (psutil.Error, PermissionError):
                continue
    except (psutil.Error, PermissionError):
        pass
    if not pids:
        pids.update(_pids_on_port_lsof(port))
    return sorted(pids)


def _kill_pid(pid: int) -> bool:
    try:
        proc = psutil.Process(pid)
    except psutil.NoSuchProcess:
        return True
    try:
        proc.terminate()
        proc.wait(timeout=8)
        return True
    except psutil.TimeoutExpired:
        try:
            proc.kill()
            proc.wait(timeout=5)
            return True
        except (psutil.Error, OSError):
            return False
    except (psutil.Error, OSError):
        return False


def _launchd_target(label: str) -> str:
    return f"{_LAUNCHD_DOMAIN}/{label}"


def _launchd_loaded(label: str) -> bool:
    if not label:
        return False
    proc = subprocess.run(
        ["launchctl", "print", _launchd_target(label)],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    return proc.returncode == 0


def _launchd_bootstrap(label: str, plist: str) -> tuple[bool, Optional[str]]:
    if not label or not plist or not Path(plist).is_file():
        return False, "launchd plist가 없습니다. install_*_launchd.sh 를 실행하세요."

    subprocess.run(
        ["launchctl", "bootout", _launchd_target(label)],
        capture_output=True,
        timeout=10,
        check=False,
    )
    subprocess.run(
        ["launchctl", "bootout", _LAUNCHD_DOMAIN, plist],
        capture_output=True,
        timeout=10,
        check=False,
    )
    proc = subprocess.run(
        ["launchctl", "bootstrap", _LAUNCHD_DOMAIN, plist],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        return False, detail or f"launchctl bootstrap failed (exit {proc.returncode})"
    subprocess.run(["launchctl", "enable", _launchd_target(label)], capture_output=True, check=False)
    return True, None


def _launchd_kickstart(label: str) -> bool:
    if not label:
        return False
    if not _launchd_loaded(label):
        return False
    proc = subprocess.run(
        ["launchctl", "kickstart", "-k", _launchd_target(label)],
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    return proc.returncode == 0


def _launchd_stop(label: str) -> bool:
    if not label or not _launchd_loaded(label):
        return False
    proc = subprocess.run(
        ["launchctl", "kill", "SIGTERM", _launchd_target(label)],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    return proc.returncode == 0


def _launchd_labels_for_config(config: dict[str, object]) -> list[str]:
    raw = config.get("launchd_labels")
    if isinstance(raw, list):
        labels = [str(item).strip() for item in raw if str(item).strip()]
        if labels:
            return labels
    launchd = str(config.get("launchd") or "").strip()
    return [launchd] if launchd else []


def _launchd_bootout_all(config: dict[str, object]) -> bool:
    plist = str(config.get("plist") or "")
    primary = str(config.get("launchd") or "")
    ok = True
    for label in _launchd_labels_for_config(config):
        label_plist = plist if label == primary else ""
        ok = _launchd_bootout(label, label_plist) and ok
    return ok


def _killall_processes(names: list[str] | tuple[str, ...]) -> None:
    for name in names:
        if not name:
            continue
        subprocess.run(["killall", name], capture_output=True, timeout=10, check=False)


def _quit_mac_app(app_name: str) -> None:
    if not app_name:
        return
    subprocess.run(["killall", app_name], capture_output=True, timeout=5, check=False)
    try:
        subprocess.run(
            ["osascript", "-e", f'tell application "{app_name}" to quit'],
            capture_output=True,
            timeout=3,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pass
    subprocess.run(["killall", "-9", app_name], capture_output=True, timeout=5, check=False)


def _start_ollama_app(app_name: str) -> bool:
    if not app_name:
        return False
    proc = subprocess.run(["open", "-a", app_name], capture_output=True, text=True, timeout=15, check=False)
    return proc.returncode == 0


def _start_via_run_script(run_script: str) -> bool:
    """launchd bootstrap 실패 시 run_*.sh 로 직접 기동 (Ollama open -a 폴백과 동일 패턴)."""
    path = Path(run_script)
    if not path.is_file():
        return False
    subprocess.Popen(
        ["/bin/bash", str(path)],
        cwd=str(_REPO_ROOT),
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return True


def _launchd_bootout(label: str, plist: str = "") -> bool:
    """KeepAlive launchd job을 내린다 — kill만으로는 즉시 재기동된다."""
    if not label:
        return False
    if not _launchd_loaded(label):
        return True
    subprocess.run(["launchctl", "disable", _launchd_target(label)], capture_output=True, check=False)
    proc = subprocess.run(
        ["launchctl", "bootout", _launchd_target(label)],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    if proc.returncode == 0:
        return True
    if plist and Path(plist).is_file():
        fallback = subprocess.run(
            ["launchctl", "bootout", _LAUNCHD_DOMAIN, plist],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        return fallback.returncode == 0
    return False


def _resolve_service_keys(service: str) -> list[str]:
    key = service.strip().lower()
    if key == "all":
        return list(SERVICE_KEYS)
    if key not in _SERVICE_CONFIG:
        raise HTTPException(
            status_code=400,
            detail="service는 ollama, siglip, nima, embedding, all 중 하나여야 합니다.",
        )
    return [key]


def _dedupe_launchd_keys(keys: list[str]) -> list[str]:
    seen: set[str] = set()
    unique: list[str] = []
    for key in keys:
        label = str(_SERVICE_CONFIG[key].get("launchd") or "")
        dedupe_key = label or key
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        unique.append(key)
    return unique


def _service_start_wait_sec(key: str) -> float:
    waits = {
        "embedding": _EMBED_START_WAIT_SEC,
        "ollama": _OLLAMA_START_WAIT_SEC,
        "siglip": 120.0,
        "nima": 120.0,
    }
    return waits.get(key, _START_WAIT_SEC)


def _start_one_service(key: str) -> dict:
    config = _SERVICE_CONFIG.get(key)
    if not config:
        return {"service": key, "ok": False, "error": "알 수 없는 서비스입니다."}

    label = str(config["label"])
    port = int(config["port"])
    launchd = str(config.get("launchd") or "")
    plist = str(config.get("plist") or "")

    if not launchd:
        return {
            "service": key,
            "label": label,
            "ok": False,
            "configured": False,
            "error": f"{label}은(는) 맥북 GPU에 설치되지 않았습니다.",
            "port": port,
        }

    if _port_open(port):
        return {
            "service": key,
            "label": label,
            "ok": True,
            "alreadyRunning": True,
            "port": port,
        }

    started = False
    method = ""
    boot_ok, boot_err = (False, None)
    if not _launchd_loaded(launchd):
        boot_ok, boot_err = _launchd_bootstrap(launchd, plist)
        if boot_ok:
            method = f"bootstrap:{launchd}"
            started = True
    elif _launchd_kickstart(launchd):
        method = f"kickstart:{launchd}"
        started = True

    if not started and _launchd_kickstart(launchd):
        method = f"kickstart:{launchd}"
        started = True

    if not started:
        start_app = str(config.get("start_app") or "")
        run_script = str(config.get("run_script") or "")
        if key == "ollama" and start_app and _start_ollama_app(start_app):
            method = f"open:{start_app}"
            started = True
        elif run_script and _start_via_run_script(run_script):
            method = f"script:{run_script}"
            started = True
        else:
            detail = boot_err or "launchd 기동에 실패했습니다."
            hint = "install_*_launchd.sh 를 실행하거나 run_embed.sh / run_siglip.sh / run_nima.sh 를 확인하세요."
            return {
                "service": key,
                "label": label,
                "ok": False,
                "error": f"{detail} ({hint})",
                "port": port,
            }

    if _wait_port(port, timeout_sec=_service_start_wait_sec(key)):
        return {
            "service": key,
            "label": label,
            "ok": True,
            "started": True,
            "method": method,
            "port": port,
        }

    return {
        "service": key,
        "label": label,
        "ok": False,
        "started": True,
        "method": method,
        "port": port,
        "error": f"{label} 기동을 시도했지만 {int(_service_start_wait_sec(key))}초 내 포트 {port} 응답이 없습니다.",
    }


def _stop_one_service(key: str) -> dict:
    config = _SERVICE_CONFIG.get(key)
    if not config:
        return {"service": key, "ok": False, "error": "알 수 없는 서비스입니다."}

    label = str(config["label"])
    port = int(config["port"])
    launchd = str(config.get("launchd") or "")
    plist = str(config.get("plist") or "")

    if not launchd:
        return {
            "service": key,
            "label": label,
            "ok": False,
            "configured": False,
            "error": f"{label}은(는) 맥북 GPU에 설치되지 않았습니다.",
            "port": port,
        }

    if not _port_open(port):
        return {
            "service": key,
            "label": label,
            "ok": True,
            "alreadyStopped": True,
            "port": port,
        }

    _launchd_stop(launchd)
    booted_out = _launchd_bootout_all(config)
    quit_app = str(config.get("stop_quit_app") or "")
    if quit_app:
        _quit_mac_app(quit_app)
    killall_names = config.get("stop_killall")
    if isinstance(killall_names, list):
        _killall_processes(killall_names)
    pgrep_patterns = config.get("stop_pgrep")
    cmdline_pids: list[int] = []
    if isinstance(pgrep_patterns, list):
        cmdline_pids = _pids_by_cmdline_substrings(pgrep_patterns)
    pids = sorted(set(_pids_listening_on_port(port)) | set(cmdline_pids))
    killed: list[int] = []
    failed: list[int] = []
    for pid in pids:
        if _kill_pid(pid):
            killed.append(pid)
        else:
            failed.append(pid)

    if failed:
        return {
            "service": key,
            "label": label,
            "ok": False,
            "port": port,
            "killedPids": killed,
            "error": f"일부 프로세스를 종료하지 못했습니다: {failed}",
        }

    if _wait_port_closed(port, timeout_sec=_STOP_WAIT_SEC):
        return {
            "service": key,
            "label": label,
            "ok": True,
            "stopped": True,
            "port": port,
            "killedPids": killed,
            "launchdBootout": booted_out,
        }

    # 포트가 아직 열려 있으면 lsof로 재탐색 후 SIGKILL
    for pid in _pids_listening_on_port(port):
        if pid in killed:
            continue
        try:
            psutil.Process(pid).kill()
            killed.append(pid)
        except (psutil.Error, OSError):
            failed.append(pid)

    if _wait_port_closed(port, timeout_sec=10.0):
        return {
            "service": key,
            "label": label,
            "ok": True,
            "stopped": True,
            "port": port,
            "killedPids": killed,
            "launchdBootout": booted_out,
            "forceKill": True,
        }

    if not killed:
        return {
            "service": key,
            "label": label,
            "ok": False,
            "port": port,
            "error": f"{label} 포트 {port}를 사용하는 프로세스를 찾지 못했습니다.",
        }

    return {
        "service": key,
        "label": label,
        "ok": False,
        "stopped": True,
        "port": port,
        "killedPids": killed,
        "launchdBootout": booted_out,
        "error": f"{label} 프로세스는 종료했지만 {int(_STOP_WAIT_SEC)}초 내 포트 {port}가 닫히지 않았습니다.",
    }


def _start_services(service: str) -> dict:
    keys = _dedupe_launchd_keys(_resolve_service_keys(service))
    results = [_start_one_service(name) for name in keys if str(_SERVICE_CONFIG[name].get("launchd") or "")]
    skipped = [
        {
            "service": name,
            "label": _SERVICE_CONFIG[name]["label"],
            "ok": False,
            "configured": False,
            "error": "맥북에 미설치",
        }
        for name in _resolve_service_keys(service)
        if name in _SERVICE_CONFIG and not str(_SERVICE_CONFIG[name].get("launchd") or "")
    ]
    results.extend(skipped)
    ok = all(item.get("ok") for item in results) if results else False
    return {"ok": ok, "results": results}


def _stop_services(service: str) -> dict:
    keys = _dedupe_launchd_keys(list(reversed(_resolve_service_keys(service))))
    results = [_stop_one_service(name) for name in keys if str(_SERVICE_CONFIG[name].get("launchd") or "")]
    skipped = [
        {
            "service": name,
            "label": _SERVICE_CONFIG[name]["label"],
            "ok": False,
            "configured": False,
            "error": "맥북에 미설치",
        }
        for name in _resolve_service_keys(service)
        if name in _SERVICE_CONFIG and not str(_SERVICE_CONFIG[name].get("launchd") or "")
    ]
    results.extend(skipped)
    ok = all(item.get("ok") for item in results) if results else False
    return {"ok": ok, "results": results}


def _services() -> list[dict]:
    rows: list[dict] = []
    health_paths = {
        "Ollama": "/api/tags",
        "임베딩": "/health",
        "SigLIP": "/health",
        "NIMA": "/health",
    }
    for label, port in SERVICE_PORTS:
        started = time.perf_counter()
        reachable = False
        latency_ms: int | None = None
        path = health_paths.get(label, "/health")
        try:
            import urllib.error
            import urllib.request

            with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=1.5) as res:
                reachable = res.status < 500
                if reachable:
                    latency_ms = int((time.perf_counter() - started) * 1000)
        except (OSError, urllib.error.URLError, ValueError):
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=1.5):
                    reachable = True
                    latency_ms = int((time.perf_counter() - started) * 1000)
            except OSError:
                reachable = False
        rows.append({"label": label, "port": port, "reachable": reachable, "latencyMs": latency_ms})
    return rows


@app.get("/metrics")
def metrics() -> dict:
    return {
        "platform": platform.platform(),
        "services": _services(),
    }


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/services/start")
def start_services(body: ServiceRequest, authorization: Optional[str] = Header(default=None)) -> dict:
    _assert_control_auth(authorization)
    return _start_services(body.service)


@app.post("/services/stop")
def stop_services(body: ServiceRequest, authorization: Optional[str] = Header(default=None)) -> dict:
    _assert_control_auth(authorization)
    return _stop_services(body.service)


if __name__ == "__main__":
    port = int(os.getenv("MACBOOK_METRICS_PORT", os.getenv("METRICS_AGENT_PORT", "8425")))
    uvicorn.run(app, host="0.0.0.0", port=port)
