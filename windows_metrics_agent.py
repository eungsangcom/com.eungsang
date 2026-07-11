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

# 윈도우에서 노출 중인 서비스 (포트 → 라벨)
SERVICE_PORTS: list[tuple[str, int]] = [
    ("Ollama", int(os.getenv("METRICS_OLLAMA_PORT", "11434"))),
    ("임베딩", int(os.getenv("METRICS_EMBED_PORT", "8420"))),
]

_SERVICE_CONFIG: dict[str, dict[str, object]] = {
    "ollama": {
        "label": "Ollama",
        "port": int(os.getenv("METRICS_OLLAMA_PORT", "11434")),
        "task": os.getenv("WINDOWS_OLLAMA_TASK", "Eungsang-Ollama").strip(),
        "cmd": os.getenv("WINDOWS_OLLAMA_START_CMD", "").strip(),
    },
    "embedding": {
        "label": "임베딩",
        "port": int(os.getenv("METRICS_EMBED_PORT", "8420")),
        "task": os.getenv("WINDOWS_EMBED_TASK", "Eungsang-KureEmbed").strip(),
        "cmd": os.getenv(
            "WINDOWS_EMBED_START_CMD",
            f'"{sys.executable}" "{_REPO_ROOT / "windows_kure_embed_server.py"}"',
        ).strip(),
    },
}


class StartServiceRequest(BaseModel):
    service: str = Field(..., description="ollama | embedding | all")


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

    if _wait_port(port, timeout_sec=_START_WAIT_SEC):
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
        "error": f"{label} 기동을 시도했지만 {int(_START_WAIT_SEC)}초 내 포트 {port} 응답이 없습니다.",
    }


def _start_services(service: str) -> dict:
    key = service.strip().lower()
    if key == "all":
        results = [_start_one_service(name) for name in ("ollama", "embedding")]
        ok = all(item.get("ok") for item in results)
        return {"ok": ok, "results": results}

    if key not in _SERVICE_CONFIG:
        raise HTTPException(status_code=400, detail="service는 ollama, embedding, all 중 하나여야 합니다.")

    result = _start_one_service(key)
    return {"ok": bool(result.get("ok")), "results": [result]}


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


@app.post("/services/start")
def start_services(
    body: StartServiceRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    _assert_control_auth(authorization)
    return _start_services(body.service)


if __name__ == "__main__":
    port = int(os.getenv("METRICS_AGENT_PORT", "8425"))
    uvicorn.run(app, host="0.0.0.0", port=port)
