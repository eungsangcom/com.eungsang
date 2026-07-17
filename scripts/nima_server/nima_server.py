"""NIMA (Neural Image Assessment) 사진 미학 심사 HTTP 서버 — 윈도우 GPU 상주용.

맥미니 backend가 `POST /score`로 이미지를 보내면 0~100 점수를 반환한다.
PyIQA의 AVA 학습 NIMA(`nima`)를 사용한다.

환경변수:
  NIMA_DEVICE           추론 디바이스 (기본: cuda:0, CPU면 cpu)
  NIMA_METRIC           pyiqa metric 이름 (기본: nima)
  NIMA_PORT             서버 포트 (기본: 8428)
  NIMA_LAZY_LOAD        기동 시 모델 미로드, /score 시 로드 (기본: 1)
  NIMA_IDLE_UNLOAD_SEC  마지막 심사 후 VRAM 해제까지 초 (기본: 300, 0=비활성)
"""

from __future__ import annotations

import io
import logging
import os
import threading
from contextlib import asynccontextmanager
from typing import Any

import torch
import uvicorn
from fastapi import FastAPI, File, HTTPException, UploadFile
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("nima_server")


def _bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


DEVICE = os.getenv("NIMA_DEVICE", "cuda:0").strip() or "cuda:0"
METRIC_NAME = os.getenv("NIMA_METRIC", "nima").strip() or "nima"
PORT = int(os.getenv("NIMA_PORT", "8428"))
LAZY_LOAD = _bool_env("NIMA_LAZY_LOAD", True)
IDLE_UNLOAD_SEC = int(os.getenv("NIMA_IDLE_UNLOAD_SEC", "300"))


def _resolve_device() -> str:
    if DEVICE.startswith("cuda") and not torch.cuda.is_available():
        logger.warning("[nima] CUDA unavailable — falling back to cpu")
        return "cpu"
    return DEVICE


class NimaEngine:
    def __init__(self) -> None:
        self.metric = None
        self.device = _resolve_device()
        self._lock = threading.Lock()
        self._idle_timer: threading.Timer | None = None

    def is_loaded(self) -> bool:
        return self.metric is not None

    def _cancel_idle_timer(self) -> None:
        if self._idle_timer is not None:
            self._idle_timer.cancel()
            self._idle_timer = None

    def _schedule_idle_unload(self) -> None:
        self._cancel_idle_timer()
        if IDLE_UNLOAD_SEC <= 0:
            return

        def _unload() -> None:
            try:
                with self._lock:
                    self.unload()
            except Exception:
                logger.exception("[nima] idle unload failed")

        self._idle_timer = threading.Timer(IDLE_UNLOAD_SEC, _unload)
        self._idle_timer.daemon = True
        self._idle_timer.start()

    def unload(self) -> None:
        if self.metric is None:
            return
        logger.info("[nima] unloading model (VRAM release)")
        self.metric = None
        if self.device.startswith("cuda") and torch.cuda.is_available():
            torch.cuda.empty_cache()
        logger.info("[nima] model unloaded")

    def load(self) -> None:
        if self.metric is not None:
            return
        import pyiqa

        self.device = _resolve_device()
        logger.info("[nima] loading metric=%s device=%s", METRIC_NAME, self.device)
        self.metric = pyiqa.create_metric(METRIC_NAME, device=self.device)
        self.metric.eval()
        logger.info(
            "[nima] model ready score_range=%s",
            getattr(self.metric, "score_range", None),
        )

    def ensure_loaded(self) -> None:
        with self._lock:
            self.load()

    @torch.inference_mode()
    def score_image(self, image: Image.Image) -> dict[str, Any]:
        with self._lock:
            self.load()
            assert self.metric is not None
            rgb = image.convert("RGB")
            # pyiqa accepts PIL / path / tensor; pass PIL for simplicity
            raw = self.metric(rgb)
            if isinstance(raw, torch.Tensor):
                raw_f = float(raw.detach().float().reshape(-1)[0].cpu())
            else:
                raw_f = float(raw)

            # PyIQA retrained NIMA is typically [0, 1]; classic AVA MOS is ~[1, 10].
            score_range = getattr(self.metric, "score_range", None)
            low, high = 0.0, 1.0
            if (
                isinstance(score_range, (tuple, list))
                and len(score_range) >= 2
                and score_range[0] is not None
                and score_range[1] is not None
            ):
                low, high = float(score_range[0]), float(score_range[1])
            elif raw_f > 1.5:
                # heuristic: AVA-style MOS
                low, high = 1.0, 10.0

            span = max(1e-6, high - low)
            overall = (raw_f - low) / span * 100.0
            overall = max(0.0, min(100.0, overall))

            result = {
                "overall": round(overall, 2),
                "model": f"nima/{METRIC_NAME}",
                "breakdown": {
                    "nima_raw": f"{raw_f:.4f}",
                    "nima_scale": f"{low:g}~{high:g}",
                    "nima_overall_0_100": f"{overall:.2f}",
                },
            }
            self._schedule_idle_unload()
            return result


engine = NimaEngine()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    if not LAZY_LOAD:
        engine.ensure_loaded()
    else:
        logger.info("[nima] lazy load enabled — model loads on first /score")
    yield
    with engine._lock:
        engine.unload()


app = FastAPI(title="NIMA Aesthetic Scoring", lifespan=lifespan)


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "model": f"nima/{METRIC_NAME}",
        "device": engine.device,
        "loaded": engine.is_loaded(),
        "lazy_load": LAZY_LOAD,
    }


@app.post("/score")
async def score(file: UploadFile = File(...)) -> dict[str, Any]:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image")
    try:
        image = Image.open(io.BytesIO(data))
        image.load()
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"Invalid image: {exc}") from exc
    try:
        return engine.score_image(image)
    except Exception as exc:  # noqa: BLE001
        logger.exception("[nima] score failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")
