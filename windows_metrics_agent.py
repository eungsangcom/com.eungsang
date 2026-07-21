"""윈도우 GPU 서버 메트릭 에이전트 — 설비실 대시보드용.

윈도우 PC(Ollama·임베딩 GPU 서버)에서 실행한다.

수동:
    pip install fastapi uvicorn psutil
    python windows_metrics_agent.py

재부팅 후 자동 기동 (작업 스케줄러):
    scripts/windows_metrics_agent/install_task.ps1

맥미니 백엔드가 /metrics 를 Tailscale로 폴링한다. (WINDOWS_METRICS_URL)
"""

from __future__ import annotations

import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

import psutil
import uvicorn
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

app = FastAPI()

_REPO_ROOT = Path(__file__).resolve().parent
_CONTROL_TOKEN = os.getenv("WINDOWS_CONTROL_TOKEN", "").strip()
_START_WAIT_SEC = float(os.getenv("WINDOWS_SERVICE_START_WAIT_SEC", "45"))
_STOP_WAIT_SEC = float(os.getenv("WINDOWS_SERVICE_STOP_WAIT_SEC", "30"))
_EMBED_START_WAIT_SEC = float(os.getenv("WINDOWS_EMBED_START_WAIT_SEC", "180"))
_OLLAMA_START_WAIT_SEC = float(os.getenv("WINDOWS_OLLAMA_START_WAIT_SEC", "45"))
_SERVICES_DIR = _REPO_ROOT / "scripts" / "windows_metrics_agent" / "services"
_EMBED_START_BAT = _SERVICES_DIR / "start_embedding.bat"
_SIGLIP_START_BAT = _SERVICES_DIR / "start_siglip.bat"
_NIMA_START_BAT = _SERVICES_DIR / "start_nima.bat"
_AGENT_CONFIG_CMD = _SERVICES_DIR / "config.cmd"

_GPU_CONFIG_DEFAULTS: dict[str, dict[str, str]] = {
    "siglip": {
        "dir": "siglip_server",
        "vars": {
            "SIGLIP_PORT": "8437",
            "SIGLIP_DEVICE": "cuda:0",
            "SIGLIP_LAZY_LOAD": "1",
            "SIGLIP_DTYPE": "float16",
            "HF_HOME": r"G:\hf_cache",
        },
    },
    "nima": {
        "dir": "nima_server",
        "vars": {
            "NIMA_DEVICE": "cuda:0",
            "NIMA_METRIC": "nima",
            "NIMA_PORT": "8428",
            "NIMA_LAZY_LOAD": "1",
            "NIMA_IDLE_UNLOAD_SEC": "300",
        },
    },
}

_GPU_PYTHON_CANDIDATES = (
    r"C:\ProgramData\anaconda3\envs\artimuse\python.exe",
    r"C:\ProgramData\anaconda3\python.exe",
)

SERVICE_KEYS: tuple[str, ...] = ("ollama", "siglip", "nima", "embedding")
_ALLOWED_SERVICES = frozenset({*SERVICE_KEYS, "all"})

# 윈도우에서 노출 중인 서비스 (포트 → 라벨)
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
        "task": os.getenv("WINDOWS_OLLAMA_TASK", "Eungsang-Ollama").strip(),
        "cmd": os.getenv("WINDOWS_OLLAMA_START_CMD", "").strip()
        or (f'cmd /c "{_SERVICES_DIR / "start_ollama.bat"}"' if (_SERVICES_DIR / "start_ollama.bat").is_file() else ""),
    },
    "embedding": {
        "label": "임베딩",
        "port": int(os.getenv("METRICS_EMBED_PORT", "8420")),
        "task": os.getenv("WINDOWS_EMBED_TASK", "Eungsang-KureEmbed").strip(),
        "cmd": os.getenv("WINDOWS_EMBED_START_CMD", "").strip()
        or (f'cmd /c "{_EMBED_START_BAT}"' if _EMBED_START_BAT.is_file() else "")
        or f'"{sys.executable}" "{_REPO_ROOT / "windows_kure_embed_server.py"}"',
    },
    "siglip": {
        "label": "SigLIP",
        "port": int(os.getenv("METRICS_SIGLIP_PORT", "8437")),
        "task": os.getenv("WINDOWS_SIGLIP_TASK", "Eungsang-SiglipServer").strip(),
        "cmd": os.getenv("WINDOWS_SIGLIP_START_CMD", "").strip()
        or (f'cmd /c "{_SIGLIP_START_BAT}"' if _SIGLIP_START_BAT.is_file() else ""),
    },
    "nima": {
        "label": "NIMA",
        "port": int(os.getenv("METRICS_NIMA_PORT", "8428")),
        "task": os.getenv("WINDOWS_NIMA_TASK", "Eungsang-NimaServer").strip(),
        "cmd": os.getenv("WINDOWS_NIMA_START_CMD", "").strip()
        or (f'cmd /c "{_NIMA_START_BAT}"' if _NIMA_START_BAT.is_file() else ""),
    },
}

_SERVICE_STOP_MATCH: dict[str, tuple[str, ...]] = {
    "ollama": ("ollama",),
    "embedding": ("kure_embed", "windows_kure_embed", "embed_server"),
    "siglip": ("siglip_server", "siglip"),
    "nima": ("nima_server", "nima"),
}

_PORT_PROTECTED_MATCH: dict[int, tuple[str, ...]] = {
    8426: ("windows_git_sync_agent", "git_sync", "git-sync"),
}


class StartServiceRequest(BaseModel):
    service: str = Field(
        ...,
        description="ollama | siglip | nima | embedding | all",
    )


class StopServiceRequest(BaseModel):
    service: str = Field(
        ...,
        description="ollama | siglip | nima | embedding | all",
    )


class RunTaskRequest(BaseModel):
    taskName: str = Field(..., description="Windows scheduled task name")


class PowerRequest(BaseModel):
    delaySec: int = Field(default=60, ge=0, le=600, description="종료·재부팅까지 대기(초)")
    force: bool = Field(default=False, description="실행 중인 앱 강제 종료 (shutdown 전용)")


def _assert_control_auth(authorization: str | None) -> None:
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


def _pids_listening_on_port(port: int) -> list[int]:
    pids: set[int] = set()
    try:
        for conn in psutil.net_connections(kind="inet"):
            laddr = conn.laddr
            if not laddr or laddr.port != port:
                continue
            if conn.status != psutil.CONN_LISTEN:
                continue
            if conn.pid:
                pids.add(conn.pid)
    except (psutil.Error, PermissionError):
        return []
    return sorted(pids)


def _process_signature(pid: int) -> str:
    try:
        proc = psutil.Process(pid)
        parts = [proc.name(), *proc.cmdline()]
        return " ".join(parts).lower()
    except (psutil.Error, OSError):
        return ""


def _pids_for_service(key: str, port: int) -> list[int]:
    """서비스별 프로세스만 선택 (공유 포트·다른 에이전트 제외)."""
    listeners = _pids_listening_on_port(port)
    if not listeners:
        return []

    match_patterns = _SERVICE_STOP_MATCH.get(key)
    protected_patterns = _PORT_PROTECTED_MATCH.get(port, ())
    selected: list[int] = []

    for pid in listeners:
        signature = _process_signature(pid)
        if not signature:
            continue
        if protected_patterns and any(token in signature for token in protected_patterns):
            continue
        if match_patterns:
            if any(token in signature for token in match_patterns):
                selected.append(pid)
            continue
        selected.append(pid)

    return selected


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


def _stop_one_service(key: str) -> dict:
    config = _SERVICE_CONFIG.get(key)
    if not config:
        return {"service": key, "ok": False, "error": "알 수 없는 서비스입니다."}

    label = str(config["label"])
    port = int(config["port"])
    if not _port_open(port):
        return {
            "service": key,
            "label": label,
            "ok": True,
            "alreadyStopped": True,
            "port": port,
        }

    pids = _pids_for_service(key, port)
    if not pids:
        return {
            "service": key,
            "label": label,
            "ok": True,
            "alreadyStopped": True,
            "port": port,
            "note": "포트는 사용 중이지만 해당 서비스 프로세스는 없습니다.",
        }

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
        }

    if not _pids_for_service(key, port):
        return {
            "service": key,
            "label": label,
            "ok": True,
            "stopped": True,
            "port": port,
            "killedPids": killed,
            "note": f"{label} 프로세스는 종료했습니다. 포트 {port}는 다른 서비스가 사용 중일 수 있습니다.",
        }

    return {
        "service": key,
        "label": label,
        "ok": False,
        "stopped": True,
        "port": port,
        "killedPids": killed,
        "error": f"{label} 프로세스는 종료했지만 {int(_STOP_WAIT_SEC)}초 내 포트 {port}가 닫히지 않았습니다.",
    }


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


def _stop_services(service: str) -> dict:
    keys = _resolve_service_keys(service)
    if service.strip().lower() == "all":
        keys = list(reversed(keys))
    results = [_stop_one_service(name) for name in keys]
    ok = all(item.get("ok") for item in results)
    return {"ok": ok, "results": results}


def _read_py_from_agent_config() -> str | None:
    if not _AGENT_CONFIG_CMD.is_file():
        return None
    for line in _AGENT_CONFIG_CMD.read_text(encoding="utf-8", errors="ignore").splitlines():
        match = re.match(r'^\s*set\s+"?PY=(.+?)"?\s*$', line, flags=re.IGNORECASE)
        if match:
            return match.group(1).strip().strip('"')
    return None


def _resolve_gpu_python() -> str | None:
    py = _read_py_from_agent_config()
    if py and Path(py).is_file():
        return py
    for candidate in _GPU_PYTHON_CANDIDATES:
        if Path(candidate).is_file():
            return candidate
    return None


def _ensure_gpu_service_config(key: str) -> bool:
    spec = _GPU_CONFIG_DEFAULTS.get(key)
    if not spec:
        return True

    cfg_path = _REPO_ROOT / "scripts" / spec["dir"] / "config.cmd"
    if cfg_path.is_file():
        return True

    py = _resolve_gpu_python()
    if not py:
        return False

    lines = ["@echo off", f'set "PY={py}"']
    for name, value in spec["vars"].items():
        lines.append(f"set {name}={value}")
    cfg_path.parent.mkdir(parents=True, exist_ok=True)
    cfg_path.write_text("\r\n".join(lines) + "\r\n", encoding="ascii")
    return True


def _bootstrap_gpu_services() -> dict:
    results: list[dict] = []
    ok = True
    for key in ("siglip", "nima"):
        label = str(_SERVICE_CONFIG[key]["label"])
        if _ensure_gpu_service_config(key):
            results.append({"service": key, "label": label, "ok": True, "configured": True})
        else:
            ok = False
            results.append({
                "service": key,
                "label": label,
                "ok": False,
                "error": "GPU Python/config.cmd 를 찾지 못했습니다. bootstrap_gpu_config.ps1 를 실행하세요.",
            })

    tasks_script = _SERVICES_DIR / "install_service_tasks.ps1"
    if sys.platform == "win32" and tasks_script.is_file():
        try:
            proc = subprocess.run(
                [
                    "powershell",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(tasks_script),
                ],
                capture_output=True,
                text=True,
                timeout=120,
                check=False,
                cwd=str(_SERVICES_DIR),
            )
            tasks_ok = proc.returncode == 0
            ok = ok and tasks_ok
            results.append({
                "service": "tasks",
                "label": "작업 스케줄러",
                "ok": tasks_ok,
                "error": None if tasks_ok else (proc.stderr or proc.stdout or "install_service_tasks.ps1 실패")[:500],
            })
        except (OSError, subprocess.SubprocessError) as exc:
            ok = False
            results.append({"service": "tasks", "label": "작업 스케줄러", "ok": False, "error": str(exc)})

    return {"ok": ok, "results": results}


def _start_via_task(task_name: str) -> bool:
    if not task_name or sys.platform != "win32":
        return False
    try:
        proc = subprocess.run(
            ["schtasks", "/Run", "/TN", task_name],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        return proc.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def _start_via_cmd(command: str) -> bool:
    if not command:
        return False
    try:
        creationflags = 0
        if sys.platform == "win32":
            creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
        subprocess.Popen(
            command,
            shell=True,
            cwd=str(_REPO_ROOT),
            creationflags=creationflags,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except OSError:
        return False


def _start_one_service(key: str) -> dict:
    config = _SERVICE_CONFIG.get(key)
    if not config:
        return {"service": key, "ok": False, "error": "알 수 없는 서비스입니다."}

    label = str(config["label"])
    port = int(config["port"])
    if key in _GPU_CONFIG_DEFAULTS and not _ensure_gpu_service_config(key):
        return {
            "service": key,
            "label": label,
            "ok": False,
            "error": "GPU Python/config.cmd 를 찾지 못했습니다. bootstrap_gpu_config.ps1 를 실행하세요.",
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
    task_name = str(config.get("task") or "")
    cmd = str(config.get("cmd") or "")

    if task_name and _start_via_task(task_name):
        started = True
        method = f"task:{task_name}"
    elif cmd and _start_via_cmd(cmd):
        started = True
        method = "cmd"

    if not started:
        return {
            "service": key,
            "label": label,
            "ok": False,
            "error": "기동 명령을 실행하지 못했습니다. 작업 스케줄러·PATH를 확인하세요.",
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
        "error": f"{label} 기동을 시도했지만 {int(_service_start_wait_sec(key))}초 내 포트 {port} 응답이 없습니다. services\\logs\\kure_embed.log 를 확인하세요."
        if key == "embedding"
        else f"{label} 기동을 시도했지만 {int(_service_start_wait_sec(key))}초 내 포트 {port} 응답이 없습니다.",
    }


def _service_start_wait_sec(key: str) -> float:
    waits = {
        "embedding": _EMBED_START_WAIT_SEC,
        "ollama": _OLLAMA_START_WAIT_SEC,
        "siglip": float(os.getenv("WINDOWS_SIGLIP_START_WAIT_SEC", "120")),
        "nima": float(os.getenv("WINDOWS_NIMA_START_WAIT_SEC", "120")),
    }
    return waits.get(key, _START_WAIT_SEC)


def _start_services(service: str) -> dict:
    keys = _resolve_service_keys(service)
    results = [_start_one_service(name) for name in keys]
    ok = all(item.get("ok") for item in results)
    return {"ok": ok, "results": results}


def _round(value: float | None, digits: int = 1) -> float | None:
    if value is None:
        return None
    return round(float(value), digits)


def _disks() -> list[dict]:
    rows: list[dict] = []
    for part in psutil.disk_partitions(all=False):
        if not part.mountpoint:
            continue
        try:
            usage = psutil.disk_usage(part.mountpoint)
        except (PermissionError, OSError):
            continue
        rows.append(
            {
                "mount": part.mountpoint,
                "device": part.device,
                "totalGb": _round(usage.total / (1024**3), 2),
                "usedGb": _round(usage.used / (1024**3), 2),
                "freeGb": _round(usage.free / (1024**3), 2),
                "usedPercent": _round(usage.percent),
            }
        )
    rows.sort(key=lambda row: row.get("usedPercent") or 0, reverse=True)
    return rows[:6]


def _gpus() -> list[dict]:
    """nvidia-smi 로 GPU 사용률·VRAM·온도·전력을 수집. 없으면 빈 리스트."""
    exe = shutil.which("nvidia-smi")
    if not exe:
        return []
    query = "name,utilization.gpu,memory.total,memory.used,temperature.gpu,power.draw"
    try:
        out = subprocess.run(
            [exe, f"--query-gpu={query}", "--format=csv,noheader,nounits"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if out.returncode != 0:
        return []

    rows: list[dict] = []
    for line in out.stdout.strip().splitlines():
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 6:
            continue
        name, util, mem_total, mem_used, temp, power = parts

        def _num(value: str) -> float | None:
            try:
                return float(value)
            except ValueError:
                return None

        total_mib = _num(mem_total)
        used_mib = _num(mem_used)
        total_gb = _round(total_mib / 1024, 2) if total_mib is not None else None
        used_gb = _round(used_mib / 1024, 2) if used_mib is not None else None
        used_percent = (
            _round((used_mib / total_mib) * 100)
            if total_mib and used_mib is not None
            else None
        )
        rows.append(
            {
                "name": name,
                "utilizationPercent": _round(_num(util)),
                "memoryTotalGb": total_gb,
                "memoryUsedGb": used_gb,
                "memoryUsedPercent": used_percent,
                "temperatureC": _round(_num(temp), 0),
                "powerWatt": _round(_num(power), 0),
            }
        )
    return rows


def _services() -> list[dict]:
    rows: list[dict] = []
    for label, port in SERVICE_PORTS:
        started = time.perf_counter()
        reachable = False
        latency_ms: int | None = None
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1.5):
                reachable = True
                latency_ms = int((time.perf_counter() - started) * 1000)
        except OSError:
            reachable = False
        rows.append(
            {
                "label": label,
                "port": port,
                "reachable": reachable,
                "latencyMs": latency_ms,
            }
        )
    return rows


@app.get("/metrics")
def metrics() -> dict:
    cpu_percent = psutil.cpu_percent(interval=0.35)
    memory = psutil.virtual_memory()
    swap = psutil.swap_memory()
    uptime_sec = max(0, int(time.time() - psutil.boot_time()))

    return {
        "platform": platform.platform(),
        "cpuPercent": _round(cpu_percent),
        "cpuCount": psutil.cpu_count(logical=True),
        "memoryTotalGb": _round(memory.total / (1024**3), 2),
        "memoryUsedGb": _round(memory.used / (1024**3), 2),
        "memoryAvailableGb": _round(memory.available / (1024**3), 2),
        "memoryUsedPercent": _round(memory.percent),
        "swapTotalGb": _round(swap.total / (1024**3), 2),
        "swapUsedGb": _round(swap.used / (1024**3), 2),
        "swapUsedPercent": _round(swap.percent) if swap.total else 0.0,
        "uptimeSec": uptime_sec,
        "disks": _disks(),
        "gpus": _gpus(),
        "services": _services(),
    }


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


def _schedule_power(action: str, *, delay_sec: int, force: bool) -> dict:
    if sys.platform != "win32":
        raise HTTPException(status_code=501, detail="전원 제어는 윈도우에서만 지원합니다.")

    flag = "/s" if action == "shutdown" else "/r"
    args = ["shutdown", flag, "/t", str(delay_sec), "/c", "설비실 원격 전원 제어"]
    if force and action == "shutdown":
        args.append("/f")

    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=20, check=False)
    except (OSError, subprocess.SubprocessError) as exc:
        raise HTTPException(status_code=500, detail=f"전원 명령 실행 실패: {exc}") from exc

    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "shutdown 명령이 거부되었습니다.").strip()
        raise HTTPException(status_code=500, detail=detail)

    label = "종료" if action == "shutdown" else "재부팅"
    return {
        "ok": True,
        "action": action,
        "delaySec": delay_sec,
        "force": force if action == "shutdown" else False,
        "message": f"{label} 예약됨 ({delay_sec}초 후)",
    }


@app.post("/services/bootstrap-gpu")
def bootstrap_gpu_services(
    authorization: str | None = Header(default=None),
) -> dict:
    _assert_control_auth(authorization)
    return _bootstrap_gpu_services()


@app.post("/services/run-task")
def run_scheduled_task(
    body: RunTaskRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    _assert_control_auth(authorization)
    task_name = body.taskName.strip()
    if not task_name:
        raise HTTPException(status_code=400, detail="taskName 이 필요합니다.")
    if sys.platform != "win32":
        raise HTTPException(status_code=501, detail="작업 스케줄러는 윈도우에서만 지원합니다.")
    try:
        proc = subprocess.run(
            ["schtasks", "/Run", "/TN", task_name],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise HTTPException(status_code=500, detail=f"작업 실행 실패: {exc}") from exc
    ok = proc.returncode == 0
    return {
        "ok": ok,
        "taskName": task_name,
        "error": None if ok else (proc.stderr or proc.stdout or "schtasks /Run 실패").strip(),
    }


@app.post("/services/start")
def start_services(
    body: StartServiceRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    _assert_control_auth(authorization)
    return _start_services(body.service)


@app.post("/services/stop")
def stop_services(
    body: StopServiceRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    _assert_control_auth(authorization)
    return _stop_services(body.service)


@app.post("/power/shutdown")
def power_shutdown(
    body: PowerRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    _assert_control_auth(authorization)
    return _schedule_power("shutdown", delay_sec=body.delaySec, force=body.force)


@app.post("/power/reboot")
def power_reboot(
    body: PowerRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    _assert_control_auth(authorization)
    return _schedule_power("reboot", delay_sec=body.delaySec, force=False)


if __name__ == "__main__":
    port = int(os.getenv("METRICS_AGENT_PORT", "8425"))
    uvicorn.run(app, host="0.0.0.0", port=port)
