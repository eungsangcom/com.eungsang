"""books_rag — PDF 임베딩 기반 도서 지식 RAG 에이전트.

PDF 업로드 -> 텍스트 추출/청킹 -> KURE 임베딩 -> pgvector 저장,
질의 -> 유사도 검색 -> qwen2.5 답변 생성.
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
    title="Books RAG Agent",
    description="PDF 임베딩(KURE) + pgvector + qwen2.5 기반 도서 지식 어시스턴트",
    version="0.1.0",
    lifespan=lifespan,
)

app.include_router(upload_router)
app.include_router(chat_router)


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "books-rag",
        "books_model": settings.books_model,
        "embed_model": settings.embed_model,
    }
