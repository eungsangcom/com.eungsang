from fastapi import APIRouter
from pydantic import BaseModel, Field

from core.database import get_pool
from services import rag_service

router = APIRouter(prefix="/chat", tags=["chat"])


class ChatRequest(BaseModel):
    query: str = Field(..., min_length=1)
    top_k: int | None = Field(default=None, ge=1, le=20)
    work_title: str | None = Field(default=None, description="특정 작품만 검색")
    doc_kind: str | None = Field(default=None, description="prose | lore | genre_guide")


@router.post("")
async def chat(body: ChatRequest):
    pool = await get_pool()
    return await rag_service.answer(
        pool,
        body.query,
        body.top_k,
        work_title=body.work_title,
        doc_kind=body.doc_kind,
    )


@router.post("/search")
async def search(body: ChatRequest):
    pool = await get_pool()
    hits = await rag_service.search(
        pool,
        body.query,
        body.top_k,
        work_title=body.work_title,
        doc_kind=body.doc_kind,
    )
    return {"hits": hits}
