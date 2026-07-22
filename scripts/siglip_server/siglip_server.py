"""SigLIP(google/siglip-so400m-patch14-384) 이미지·텍스트 임베딩 HTTP 서버.

윈도우 GPU 상주용. 맥미니 backend가 포토배틀 채점·갤러리 검색에 호출한다.

엔드포인트:
  GET  /health
  POST /embed   — texts 및/또는 images → L2 정규화 임베딩
  POST /score   — 미학 프롬프트 유사도 → 0~100
  POST /rank    — 이미지 vs 후보 텍스트 zero-shot 순위

환경변수:
  SIGLIP_MODEL_ID   기본 google/siglip-so400m-patch14-384
  SIGLIP_DEVICE     기본 cuda:0 (없으면 cpu)
  SIGLIP_PORT       기본 8437
  SIGLIP_LAZY_LOAD  기본 1
  SIGLIP_DTYPE      float16 | bfloat16 | float32 (기본: cuda면 float16)
  HF_HOME           기본 G:\\hf_cache (윈도우) / ~/.cache/eungsang-hf (macOS·Linux)
"""

from __future__ import annotations

import asyncio
import io
import logging
import os
import platform
import threading
from contextlib import asynccontextmanager
from typing import Any, Optional

# sentencepiece는 비ASCII 경로(한글 사용자명)에서 실패할 수 있음 → HF_HOME 을 ASCII 경로로.
def _resolve_hf_home() -> str:
    raw = (os.getenv("HF_HOME") or "").strip()
    if raw:
        return raw
    if platform.system() == "Windows":
        return r"G:\hf_cache"
    return os.path.join(os.path.expanduser("~"), ".cache", "eungsang-hf")


_DEFAULT_HF_HOME = _resolve_hf_home()
os.environ.setdefault("HF_HOME", _DEFAULT_HF_HOME)
os.environ.setdefault("HUGGINGFACE_HUB_CACHE", os.path.join(_DEFAULT_HF_HOME, "hub"))
os.environ.setdefault("TRANSFORMERS_CACHE", os.path.join(_DEFAULT_HF_HOME, "transformers"))
os.environ.setdefault("HF_HUB_CACHE", os.path.join(_DEFAULT_HF_HOME, "hub"))
os.environ.pop("XDG_CACHE_HOME", None)
os.makedirs(_DEFAULT_HF_HOME, exist_ok=True)
# huggingface_hub cache_dir = hub 루트 (models--* 가 바로 아래에 있어야 함)
_CACHE_DIR = os.environ["HUGGINGFACE_HUB_CACHE"]
_LOCAL_SNAPSHOT = os.path.join(
    _CACHE_DIR,
    "models--google--siglip-so400m-patch14-384",
    "snapshots",
    "9fdffc58afc957d1a03a25b10dba0329ab15c2a3",
)

import torch
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from PIL import Image
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("siglip_server")

MODEL_ID = os.getenv("SIGLIP_MODEL_ID", "google/siglip-so400m-patch14-384").strip()
_DEVICE_RAW = os.getenv("SIGLIP_DEVICE", "").strip()
if _DEVICE_RAW:
    DEVICE = _DEVICE_RAW
elif torch.cuda.is_available():
    DEVICE = "cuda:0"
elif getattr(torch.backends, "mps", None) is not None and torch.backends.mps.is_available():
    DEVICE = "mps"
else:
    DEVICE = "cpu"
# cuda 지정인데 빌드가 CPU-only면 폴백
if DEVICE.startswith("cuda") and not torch.cuda.is_available():
    logger.warning("[siglip] CUDA requested but unavailable; falling back to cpu")
    DEVICE = "cpu"
PORT = int(os.getenv("SIGLIP_PORT", "8437"))
LAZY_LOAD = os.getenv("SIGLIP_LAZY_LOAD", "1").strip().lower() in {"1", "true", "yes", "on"}
DTYPE_RAW = os.getenv("SIGLIP_DTYPE", "").strip().lower()

# 포토배틀 미학 채점용 품질 사다리 (프롬프트 → 점수)
QUALITY_LADDER: list[tuple[str, float]] = [
    ("This is a photo of a terrible blurry low quality snapshot.", 12.0),
    ("This is a photo of a weak amateur snapshot.", 28.0),
    ("This is a photo of an average casual photograph.", 48.0),
    ("This is a photo of a good well-composed photograph.", 68.0),
    ("This is a photo of an excellent professional photograph.", 85.0),
    ("This is a photo of an outstanding masterpiece photograph.", 96.0),
]


def _resolve_dtype() -> torch.dtype:
    if DTYPE_RAW == "float32":
        return torch.float32
    if DTYPE_RAW == "bfloat16":
        return torch.bfloat16
    if DTYPE_RAW == "float16":
        return torch.float16
    if DEVICE.startswith("cuda"):
        return torch.float16
    return torch.float32


class EmbedTextRequest(BaseModel):
    texts: list[str] = Field(default_factory=list)
    normalize: bool = True


class RankRequest(BaseModel):
    labels: list[str] = Field(..., min_length=1)
    # image는 multipart로 받거나, 이 엔드포인트는 /rank 전용 multipart 사용


class SiglipEngine:
    def __init__(self) -> None:
        self.model = None
        self.processor = None
        self.device = DEVICE
        self.dtype = _resolve_dtype()
        self.dim: int | None = None
        self._lock = threading.Lock()

    def is_loaded(self) -> bool:
        return self.model is not None

    def load(self) -> None:
        with self._lock:
            if self.model is not None:
                return
            from transformers import AutoModel, AutoProcessor

            # processor는 ASCII 로컬 스냅샷 우선 (sentencepiece 한글 경로 버그 회피)
            # model은 hub id + cache_dir로 받아 G:\hf_cache에 저장
            proc_id = _LOCAL_SNAPSHOT if os.path.isfile(
                os.path.join(_LOCAL_SNAPSHOT, "spiece.model")
            ) else MODEL_ID
            logger.info(
                "[siglip] loading %s on %s dtype=%s cache=%s proc=%s",
                MODEL_ID,
                self.device,
                self.dtype,
                _CACHE_DIR,
                proc_id,
            )
            processor = AutoProcessor.from_pretrained(
                proc_id,
                cache_dir=_CACHE_DIR,
                local_files_only=proc_id == _LOCAL_SNAPSHOT,
            )
            model = AutoModel.from_pretrained(
                MODEL_ID,
                cache_dir=_CACHE_DIR,
                torch_dtype=self.dtype if self.device.startswith("cuda") else torch.float32,
            )
            model = model.to(self.device)
            model.eval()
            self.processor = processor
            self.model = model
            # warm dim
            with torch.inference_mode():
                inputs = processor(
                    text=["warmup"],
                    padding="max_length",
                    return_tensors="pt",
                )
                inputs = self._prepare_inputs(inputs)
                feats = model.get_text_features(**inputs)
                tensor = self._as_tensor(feats)
                self.dim = int(tensor.shape[-1])
            logger.info("[siglip] ready dim=%s", self.dim)

    def ensure(self) -> None:
        if not self.is_loaded():
            self.load()

    @staticmethod
    def _as_tensor(feats: Any) -> torch.Tensor:
        if torch.is_tensor(feats):
            return feats
        pooler = getattr(feats, "pooler_output", None)
        if pooler is not None and torch.is_tensor(pooler):
            return pooler
        raise TypeError(f"Unexpected feature type: {type(feats)!r}")

    def _prepare_inputs(self, inputs: dict[str, torch.Tensor]) -> dict[str, torch.Tensor]:
        prepared: dict[str, torch.Tensor] = {}
        for key, value in inputs.items():
            tensor = value.to(self.device)
            if tensor.is_floating_point() and self.dtype != torch.float32:
                tensor = tensor.to(dtype=self.dtype)
            prepared[key] = tensor
        return prepared

    @staticmethod
    def _normalize(x: torch.Tensor) -> torch.Tensor:
        return x / x.norm(p=2, dim=-1, keepdim=True).clamp_min(1e-12)

    def embed_texts(self, texts: list[str], *, normalize: bool = True) -> list[list[float]]:
        if not texts:
            return []
        self.ensure()
        assert self.model is not None and self.processor is not None
        with self._lock, torch.inference_mode():
            inputs = self.processor(
                text=texts,
                padding="max_length",
                truncation=True,
                return_tensors="pt",
            )
            inputs = self._prepare_inputs(inputs)
            feats = self._as_tensor(self.model.get_text_features(**inputs))
            if normalize:
                feats = self._normalize(feats)
            return feats.detach().float().cpu().tolist()

    def embed_images(self, images: list[Image.Image], *, normalize: bool = True) -> list[list[float]]:
        if not images:
            return []
        self.ensure()
        assert self.model is not None and self.processor is not None
        rgb = [im.convert("RGB") if im.mode != "RGB" else im for im in images]
        with self._lock, torch.inference_mode():
            inputs = self.processor(images=rgb, return_tensors="pt")
            inputs = self._prepare_inputs(inputs)
            feats = self._as_tensor(self.model.get_image_features(**inputs))
            if normalize:
                feats = self._normalize(feats)
            return feats.detach().float().cpu().tolist()

    def score_image(self, image: Image.Image) -> dict[str, Any]:
        """품질 사다리 프롬프트 유사도 → 0~100 가중 점수."""
        self.ensure()
        assert self.model is not None and self.processor is not None
        prompts = [p for p, _ in QUALITY_LADDER]
        scores = [s for _, s in QUALITY_LADDER]
        rgb = image.convert("RGB") if image.mode != "RGB" else image
        with self._lock, torch.inference_mode():
            inputs = self.processor(
                text=prompts,
                images=rgb,
                padding="max_length",
                truncation=True,
                return_tensors="pt",
            )
            inputs = self._prepare_inputs(inputs)
            outputs = self.model(**inputs)
            logits = outputs.logits_per_image[0]  # (num_prompts,)
            probs = torch.sigmoid(logits)
            probs = probs / probs.sum().clamp_min(1e-12)
            overall = float((probs * torch.tensor(scores, device=probs.device)).sum().item())
            overall = max(0.0, min(100.0, overall))
            breakdown = {
                prompts[i]: round(float(probs[i].item()), 4) for i in range(len(prompts))
            }
        return {"overall": round(overall, 2), "breakdown": breakdown, "model": MODEL_ID}

    def rank_image(self, image: Image.Image, labels: list[str]) -> list[dict[str, Any]]:
        self.ensure()
        assert self.model is not None and self.processor is not None
        texts = [f"This is a photo of {label}." for label in labels]
        rgb = image.convert("RGB") if image.mode != "RGB" else image
        with self._lock, torch.inference_mode():
            inputs = self.processor(
                text=texts,
                images=rgb,
                padding="max_length",
                truncation=True,
                return_tensors="pt",
            )
            inputs = self._prepare_inputs(inputs)
            outputs = self.model(**inputs)
            logits = outputs.logits_per_image[0]
            probs = torch.sigmoid(logits)
            order = torch.argsort(probs, descending=True)
            return [
                {
                    "label": labels[int(i)],
                    "score": round(float(probs[int(i)].item()), 6),
                }
                for i in order.tolist()
            ]


engine = SiglipEngine()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    if not LAZY_LOAD:
        try:
            engine.load()
        except Exception:  # noqa: BLE001
            logger.exception("[siglip] eager load failed — will retry on request")
    yield


app = FastAPI(title="SigLIP Embedding Server", lifespan=lifespan)


def _read_image(data: bytes) -> Image.Image:
    try:
        return Image.open(io.BytesIO(data))
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"Invalid image: {exc}") from exc


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "model": MODEL_ID,
        "device": DEVICE,
        "loaded": engine.is_loaded(),
        "dim": engine.dim,
    }


@app.post("/embed")
async def embed(
    body: Optional[EmbedTextRequest] = None,
    files: Optional[list[UploadFile]] = File(None),
    normalize: bool = Form(True),
) -> JSONResponse:
    """텍스트 JSON 및/또는 multipart 이미지 임베딩.

    - JSON only: ``{"texts": ["..."], "normalize": true}``
    - multipart: ``files`` (+ optional ``normalize`` form) and/or combine with query texts via JSON body when using clients that support it
    """
    texts = list(body.texts) if body else []
    do_norm = body.normalize if body is not None else normalize

    images: list[Image.Image] = []
    if files:
        for f in files:
            data = await f.read()
            if data:
                images.append(_read_image(data))

    if not texts and not images:
        raise HTTPException(status_code=400, detail="texts 또는 image files가 필요합니다.")

    try:
        text_vecs = engine.embed_texts(texts, normalize=do_norm) if texts else []
        image_vecs = engine.embed_images(images, normalize=do_norm) if images else []
    except Exception as exc:  # noqa: BLE001
        logger.exception("[siglip] embed failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    dim = engine.dim or (len(text_vecs[0]) if text_vecs else len(image_vecs[0]))
    return JSONResponse(
        {
            "model": MODEL_ID,
            "dim": dim,
            "embeddings": text_vecs if text_vecs and not image_vecs else image_vecs if image_vecs and not text_vecs else None,
            "text_embeddings": text_vecs,
            "image_embeddings": image_vecs,
        }
    )


@app.post("/embed/texts")
def embed_texts(body: EmbedTextRequest) -> dict[str, Any]:
    if not body.texts:
        raise HTTPException(status_code=400, detail="texts가 비어 있습니다.")
    try:
        vectors = engine.embed_texts(body.texts, normalize=body.normalize)
    except Exception as exc:  # noqa: BLE001
        logger.exception("[siglip] embed texts failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    return {
        "embeddings": vectors,
        "model": MODEL_ID,
        "dim": engine.dim or (len(vectors[0]) if vectors else 0),
    }


@app.post("/embed/image")
async def embed_image(file: UploadFile = File(...), normalize: bool = Form(True)) -> dict[str, Any]:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image")
    try:
        vectors = engine.embed_images([_read_image(data)], normalize=normalize)
    except Exception as exc:  # noqa: BLE001
        logger.exception("[siglip] embed image failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    return {
        "embeddings": vectors,
        "model": MODEL_ID,
        "dim": engine.dim or (len(vectors[0]) if vectors else 0),
    }


@app.post("/score")
async def score(file: UploadFile = File(...)) -> dict[str, Any]:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image")
    try:
        return engine.score_image(_read_image(data))
    except Exception as exc:  # noqa: BLE001
        logger.exception("[siglip] score failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.post("/nima/score")
async def nima_score_proxy(file: UploadFile = File(...)) -> dict[str, Any]:
    """Tailscale ACL이 8428을 막을 수 있어, 열린 8437에서 로컬 NIMA(8428)로 프록시한다."""
    import json
    import urllib.error
    import urllib.request
    from concurrent.futures import ThreadPoolExecutor

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image")
    nima_url = (os.getenv("NIMA_LOCAL_URL") or "http://127.0.0.1:8428").rstrip("/")
    mime = file.content_type or "image/jpeg"
    filename = file.filename or "photo.jpg"
    boundary = "----NimaProxyBoundary7MA4YWxkTrZu0gW"

    def _post() -> dict[str, Any]:
        body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
            f"Content-Type: {mime}\r\n\r\n"
        ).encode() + data + f"\r\n--{boundary}--\r\n".encode()
        req = urllib.request.Request(
            f"{nima_url}/score",
            data=body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=180) as resp:
            return json.loads(resp.read().decode("utf-8"))

    try:
        loop = asyncio.get_running_loop()
        with ThreadPoolExecutor(max_workers=1) as pool:
            return await loop.run_in_executor(pool, _post)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        logger.exception("[siglip] nima proxy http error")
        raise HTTPException(status_code=502, detail=f"NIMA proxy HTTP {exc.code}: {detail}") from exc
    except Exception as exc:  # noqa: BLE001
        logger.exception("[siglip] nima proxy failed")
        raise HTTPException(status_code=502, detail=f"NIMA proxy failed: {exc}") from exc


@app.post("/rank")
async def rank(
    file: UploadFile = File(...),
    labels: str = Form(..., description="JSON array or comma-separated labels"),
) -> dict[str, Any]:
    import json

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image")
    try:
        parsed = json.loads(labels)
        if not isinstance(parsed, list) or not all(isinstance(x, str) for x in parsed):
            raise ValueError("labels must be a JSON string array")
        label_list = [x.strip() for x in parsed if x.strip()]
    except Exception:
        label_list = [x.strip() for x in labels.split(",") if x.strip()]
    if not label_list:
        raise HTTPException(status_code=400, detail="labels가 비어 있습니다.")
    try:
        ranked = engine.rank_image(_read_image(data), label_list)
    except Exception as exc:  # noqa: BLE001
        logger.exception("[siglip] rank failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    return {"results": ranked, "model": MODEL_ID}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")
