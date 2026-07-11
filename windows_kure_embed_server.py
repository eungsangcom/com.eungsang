"""Windows GPU KURE-v1 임베딩 서버 — RAG·star_craft 공용.

수동:
    pip install fastapi uvicorn sentence-transformers torch
    python windows_kure_embed_server.py

작업 스케줄러:
    scripts/windows_services/install_tasks.ps1
"""

from __future__ import annotations

import os

import uvicorn
from fastapi import FastAPI
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer

app = FastAPI(title="kure-embed")
_MODEL_ID = os.getenv("KURE_MODEL_ID", "nlpai-lab/KURE-v1").strip() or "nlpai-lab/KURE-v1"
_model: SentenceTransformer | None = None


def _get_model() -> SentenceTransformer:
    global _model
    if _model is None:
        _model = SentenceTransformer(_MODEL_ID)
    return _model


class EmbedRequest(BaseModel):
    texts: list[str]
    model: str = "kure"


@app.post("/embed")
def embed(req: EmbedRequest) -> dict:
    vectors = _get_model().encode(req.texts, normalize_embeddings=True)
    return {"embeddings": vectors.tolist(), "model": req.model, "dim": len(vectors[0]) if len(vectors) else 1024}


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "model": _MODEL_ID}


if __name__ == "__main__":
    port = int(os.getenv("KURE_EMBED_PORT", "8420"))
    uvicorn.run(app, host="0.0.0.0", port=port)
