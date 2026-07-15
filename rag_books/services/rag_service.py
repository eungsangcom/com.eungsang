import httpx

from core.config import settings
from core.database import ensure_schema
from services.embedding_client import embed_one, embed_texts

_TABLE = "books_docs_embeddings"

_SYSTEM_PROMPT = (
    "너는 도서 지식 전문 AI 어시스턴트다. 아래 '참고 문서'를 근거로 정확하고 충실한 답을 한국어로 준다. "
    "가능하면 어떤 책·구절에서 나온 내용인지 밝힌다. 참고 문서에 없는 내용은 추측하지 말고 일반 지식임을 밝힌다."
)

_BATCH = 32


async def ingest_chunks(pool, source_file: str, doc_type: str, chunks: list[str]) -> int:
    """청크들을 임베딩해 pgvector 에 저장. 저장한 청크 수를 반환."""
    if not chunks:
        return 0

    inserted = 0
    schema_ready = False
    async with pool.acquire() as conn:
        for start in range(0, len(chunks), _BATCH):
            batch = chunks[start : start + _BATCH]
            vectors = await embed_texts(batch)
            if not schema_ready:
                await ensure_schema(pool, len(vectors[0]))
                schema_ready = True
            for offset, (content, vector) in enumerate(zip(batch, vectors)):
                await conn.execute(
                    f"""
                    INSERT INTO {_TABLE} (source_file, doc_type, chunk_index, content, embedding)
                    VALUES ($1, $2, $3, $4, $5::vector)
                    """,
                    source_file,
                    doc_type,
                    start + offset,
                    content,
                    str(vector),
                )
                inserted += 1
    return inserted


async def search(pool, query: str, top_k: int | None = None) -> list[dict]:
    top_k = top_k or settings.top_k
    vector = str(await embed_one(query))
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            f"""
            SELECT source_file, chunk_index, content,
                   1 - (embedding <=> $1::vector) AS similarity
            FROM {_TABLE}
            ORDER BY embedding <=> $1::vector
            LIMIT $2
            """,
            vector,
            top_k,
        )
    return [dict(r) for r in rows]


async def generate_answer(query: str, hits: list[dict]) -> str:
    context = "\n\n---\n\n".join(
        f"[{h['source_file']} #{h['chunk_index']}]\n{h['content']}" for h in hits
    )
    prompt = (
        f"{_SYSTEM_PROMPT}\n\n"
        f"# 참고 문서\n{context or '(관련 문서 없음)'}\n\n"
        f"# 질문\n{query}\n\n# 답변\n"
    )
    async with httpx.AsyncClient(timeout=180.0) as client:
        res = await client.post(
            f"{settings.ollama_host.rstrip('/')}/api/generate",
            json={"model": settings.books_model, "prompt": prompt, "stream": False},
        )
        res.raise_for_status()
        return res.json().get("response", "").strip()


async def answer(pool, query: str, top_k: int | None = None) -> dict:
    hits = await search(pool, query, top_k)
    text = await generate_answer(query, hits)
    return {
        "answer": text,
        "sources": [
            {
                "source_file": h["source_file"],
                "chunk_index": h["chunk_index"],
                "similarity": round(float(h["similarity"]), 4),
            }
            for h in hits
        ],
    }
