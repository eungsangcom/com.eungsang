"""ArtiMuse(InternVL3-8B) 사진 미학 심사 HTTP 서버 — 윈도우 GPU 상주용.

맥미니 backend가 `POST /score`로 이미지를 보내면 0~100 점수와
8차원 전문 분석을 반환한다. GPU(CUDA)가 필요하며, 16GB VRAM에 맞추기 위해
기본적으로 8-bit 양자화(bitsandbytes)로 로드한다.

필수 준비:
  1) git clone https://github.com/thunderbolt215/ArtiMuse.git
  2) 체크포인트를 <repo>/checkpoints/ArtiMuse 에 배치 (HuggingFace: Thunderbolt215215/ArtiMuse)
  3) 환경변수 ARTIMUSE_REPO, ARTIMUSE_MODEL_PATH 설정 후 이 스크립트 실행

환경변수:
  ARTIMUSE_REPO           클론한 ArtiMuse 저장소 경로 (필수)
  ARTIMUSE_MODEL_PATH     체크포인트 폴더 (기본: <repo>/checkpoints/ArtiMuse)
  ARTIMUSE_DEVICE         추론 디바이스 (기본: cuda:0)
  ARTIMUSE_LOAD_8BIT      8-bit 양자화 (기본: 1 — 16GB VRAM 권장)
  ARTIMUSE_USE_FLASH_ATTN flash-attn 사용 (기본: 0 — 윈도우 빌드 난해)
  ARTIMUSE_INCLUDE_ANALYSIS 기본 분석 포함 여부 (기본: 1)
  ARTIMUSE_MAX_NEW_TOKENS 분석 토큰 상한 (기본: 512)
  ARTIMUSE_PORT           서버 포트 (기본: 8426)
  ARTIMUSE_LAZY_LOAD      기동 시 모델 미로드, /score 시 로드 (기본: 1)
  ARTIMUSE_IDLE_UNLOAD_SEC 마지막 심사 후 VRAM 해제까지 초 (기본: 300, 0=비활성)
"""

from __future__ import annotations

import io
import logging
import os
import sys
import threading
from contextlib import asynccontextmanager

import torch
import torchvision.transforms as T
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from PIL import Image
from torchvision.transforms.functional import InterpolationMode
from transformers import AutoTokenizer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("artimuse_server")

AESTHETIC_ATTRIBUTES = [
    "Composition & Design",
    "Visual Elements & Structure",
    "Technical Execution",
    "Originality & Creativity",
    "Theme & Communication",
    "Emotion & Viewer Response",
    "Overall Gestalt",
    "Comprehensive Evaluation",
]

IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


def _bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


REPO = os.getenv("ARTIMUSE_REPO", "").strip()
MODEL_PATH = os.getenv("ARTIMUSE_MODEL_PATH", "").strip()
DEVICE = os.getenv("ARTIMUSE_DEVICE", "cuda:0").strip() or "cuda:0"
LOAD_8BIT = _bool_env("ARTIMUSE_LOAD_8BIT", True)
USE_FLASH_ATTN = _bool_env("ARTIMUSE_USE_FLASH_ATTN", False)
INCLUDE_ANALYSIS_DEFAULT = _bool_env("ARTIMUSE_INCLUDE_ANALYSIS", True)
MAX_NEW_TOKENS = int(os.getenv("ARTIMUSE_MAX_NEW_TOKENS", "512"))
PORT = int(os.getenv("ARTIMUSE_PORT", "8426"))
LAZY_LOAD = _bool_env("ARTIMUSE_LAZY_LOAD", True)
IDLE_UNLOAD_SEC = int(os.getenv("ARTIMUSE_IDLE_UNLOAD_SEC", "300"))


def _build_transform(input_size: int = 448):
    return T.Compose(
        [
            T.Lambda(lambda img: img.convert("RGB") if img.mode != "RGB" else img),
            T.Resize((input_size, input_size), interpolation=InterpolationMode.BICUBIC),
            T.ToTensor(),
            T.Normalize(mean=IMAGENET_MEAN, std=IMAGENET_STD),
        ]
    )


class ArtiMuseEngine:
    def __init__(self) -> None:
        self.model = None
        self.tokenizer = None
        self.transform = _build_transform()
        self.gen_config: dict = {}
        self._lock = threading.Lock()  # GPU 추론·로드·언로드 직렬화
        self._idle_timer: threading.Timer | None = None

    def is_loaded(self) -> bool:
        return self.model is not None

    def _cancel_idle_timer(self) -> None:
        if self._idle_timer is not None:
            self._idle_timer.cancel()
            self._idle_timer = None

    def _schedule_idle_unload(self) -> None:
        self._cancel_idle_timer()
        if IDLE_UNLOAD_SEC <= 0:
            return
        self._idle_timer = threading.Timer(IDLE_UNLOAD_SEC, self._idle_unload_callback)
        self._idle_timer.daemon = True
        self._idle_timer.start()

    def _idle_unload_callback(self) -> None:
        try:
            self.unload()
        except Exception:  # noqa: BLE001
            logger.exception("[artimuse] idle unload failed")

    def unload(self) -> None:
        with self._lock:
            self._cancel_idle_timer()
            if self.model is None:
                return
            logger.info("[artimuse] unloading model (VRAM release)")
            del self.model
            del self.tokenizer
            self.model = None
            self.tokenizer = None
            self.gen_config = {}
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
            logger.info("[artimuse] model unloaded")

    def ensure_loaded(self) -> None:
        if self.model is not None:
            return
        self.load()

    def load(self) -> None:
        if not REPO:
            raise RuntimeError("ARTIMUSE_REPO 환경변수가 필요합니다 (클론한 저장소 경로).")
        for sub in (REPO, os.path.join(REPO, "src"), os.path.join(REPO, "src", "artimuse")):
            if sub not in sys.path:
                sys.path.append(sub)

        from artimuse.internvl.model.internvl_chat.modeling_artimuse import (  # noqa: E501
            InternVLChatModel,
        )

        model_path = MODEL_PATH or os.path.join(REPO, "checkpoints", "ArtiMuse")
        logger.info("[artimuse] 모델 로딩: %s (8bit=%s, flash=%s)", model_path, LOAD_8BIT, USE_FLASH_ATTN)

        common = dict(
            torch_dtype=torch.bfloat16,
            low_cpu_mem_usage=True,
            use_flash_attn=USE_FLASH_ATTN,
        )
        if LOAD_8BIT:
            model = InternVLChatModel.from_pretrained(
                model_path,
                load_in_8bit=True,
                device_map={"": DEVICE},
                **common,
            ).eval()
        else:
            model = InternVLChatModel.from_pretrained(model_path, **common).eval().to(DEVICE)

        tokenizer = AutoTokenizer.from_pretrained(
            model_path, trust_remote_code=True, use_fast=False
        )
        self.model = model
        self.tokenizer = tokenizer
        self.gen_config = dict(
            max_new_tokens=MAX_NEW_TOKENS,
            do_sample=False,
            pad_token_id=tokenizer.eos_token_id,
        )
        logger.info("[artimuse] 모델 로딩 완료")

    def _pixel_values(self, image: Image.Image):
        tensor = self.transform(image).unsqueeze(0)
        return tensor.to(torch.bfloat16).to(DEVICE)

    def score_image(self, image: Image.Image, include_analysis: bool) -> dict:
        self._cancel_idle_timer()
        with self._lock:
            self.ensure_loaded()
            pixel_values = self._pixel_values(image)
            overall = float(
                self.model.score(DEVICE, self.tokenizer, pixel_values, dict(self.gen_config))
            )
            attributes: dict[str, str] = {}
            if include_analysis:
                for aspect in AESTHETIC_ATTRIBUTES:
                    prompt = (
                        f"Please evaluate the aesthetic quality of this image "
                        f"from the aspect of {aspect}."
                    )
                    response = self.model.chat(
                        DEVICE, self.tokenizer, pixel_values, prompt, dict(self.gen_config)
                    )
                    attributes[aspect] = (response or "").strip()
        self._schedule_idle_unload()
        return {"overall": round(overall, 2), "attributes": attributes}


engine = ArtiMuseEngine()


@asynccontextmanager
async def lifespan(app: FastAPI):
    if not LAZY_LOAD:
        engine.load()
    else:
        logger.info(
            "[artimuse] lazy load enabled — model loads on first /score, "
            "unloads after %ss idle",
            IDLE_UNLOAD_SEC,
        )
    yield
    engine.unload()


app = FastAPI(title="ArtiMuse Scoring Server", lifespan=lifespan)


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "device": DEVICE,
        "model_loaded": engine.is_loaded(),
        "lazy_load": LAZY_LOAD,
        "idle_unload_sec": IDLE_UNLOAD_SEC,
    }


@app.post("/unload")
def unload_model() -> dict:
    """수동 VRAM 해제 (선택)."""
    engine.unload()
    return {"status": "ok", "model_loaded": False}


@app.post("/score")
async def score(
    file: UploadFile = File(...),
    include_analysis: bool | None = Form(None),
) -> dict:
    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="empty image")
    try:
        image = Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"invalid image: {exc}") from exc

    want_analysis = INCLUDE_ANALYSIS_DEFAULT if include_analysis is None else include_analysis
    import anyio

    return await anyio.to_thread.run_sync(engine.score_image, image, want_analysis)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
