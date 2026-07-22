"""novel_rag — 소설 로어·장르·본문 RAG 에이전트.

PDF/txt → 챕터·장면 청킹 → KURE 임베딩 → pgvector,
질의 → 검색 → qwen2.5(추후 파인튜닝 모델) 답변.
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI

from core.config import settings
from core.database import close_pool, get_pool
from routers.chat import router as chat_router
from routers.upload import router as upload_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await get_pool()
    yield
    await close_pool()


app = FastAPI(
    title="Novel RAG Agent",
    description="소설 로어·본문·장르 참고 RAG (개인 연구·습작용)",
    version="0.1.0",
    lifespan=lifespan,
)

app.include_router(upload_router)
app.include_router(chat_router)


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "novel-rag",
        "novel_model": settings.novel_model,
        "embed_model": settings.embed_model,
    }
