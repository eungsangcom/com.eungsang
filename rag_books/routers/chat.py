from fastapi import APIRouter
from pydantic import BaseModel, Field

from core.database import get_pool
from services import rag_service

router = APIRouter(prefix="/chat", tags=["chat"])


class ChatRequest(BaseModel):
    query: str = Field(..., min_length=1)
    top_k: int | None = Field(default=None, ge=1, le=20)


@router.post("")
async def chat(body: ChatRequest):
    pool = await get_pool()
    return await rag_service.answer(pool, body.query, body.top_k)


@router.post("/search")
async def search(body: ChatRequest):
    """검색 결과만 반환 (LLM 추론 없이)."""
    pool = await get_pool()
    hits = await rag_service.search(pool, body.query, body.top_k)
    return {"hits": hits}
