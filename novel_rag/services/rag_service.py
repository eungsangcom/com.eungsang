import httpx

from core.config import settings
from core.database import ensure_schema
from services.document_extractor import NovelChunk
from services.embedding_client import embed_one, embed_texts

_TABLE = "novel_docs_embeddings"

_SYSTEM_PROMPT = (
    "너는 소설 창작·로어 질의에 답하는 전문 어시스턴트다. "
    "아래 '참고 자료'의 설정·문장·장르 관습을 근거로 한국어로 답한다. "
    "창작 요청이면 구체적인 장면·대사·묘사를 제안한다. "
    "자료에 없는 설정은 추측하지 말고 '자료에 없음'이라고 밝힌다. "
    "개인 연구·습작 목적임을 전제로 한다."
)

_BATCH = 32


async def ingest_chunks(pool, source_file: str, chunks: list[NovelChunk]) -> int:
    if not chunks:
        return 0

    inserted = 0
    schema_ready = False
    async with pool.acquire() as conn:
        for start in range(0, len(chunks), _BATCH):
            batch = chunks[start : start + _BATCH]
            vectors = await embed_texts([c.content for c in batch])
            if not schema_ready:
                await ensure_schema(pool, len(vectors[0]))
                schema_ready = True
            for offset, (chunk, vector) in enumerate(zip(batch, vectors)):
                await conn.execute(
                    f"""
                    INSERT INTO {_TABLE}
                        (source_file, work_title, doc_kind, section_label, chunk_index, content, embedding)
                    VALUES ($1, $2, $3, $4, $5, $6, $7::vector)
                    """,
                    source_file,
                    chunk.work_title,
                    chunk.doc_kind,
                    chunk.section_label,
                    start + offset,
                    chunk.content,
                    str(vector),
                )
                inserted += 1
    return inserted


async def search(
    pool,
    query: str,
    top_k: int | None = None,
    *,
    work_title: str | None = None,
    doc_kind: str | None = None,
) -> list[dict]:
    top_k = top_k or settings.top_k
    vector = str(await embed_one(query))
    clauses = ["1=1"]
    params: list = [vector]
    idx = 2
    if work_title:
        clauses.append(f"work_title = ${idx}")
        params.append(work_title)
        idx += 1
    if doc_kind:
        clauses.append(f"doc_kind = ${idx}")
        params.append(doc_kind)
        idx += 1
    params.append(top_k)
    where = " AND ".join(clauses)
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            f"""
            SELECT source_file, work_title, doc_kind, section_label, chunk_index, content,
                   1 - (embedding <=> $1::vector) AS similarity
            FROM {_TABLE}
            WHERE {where}
            ORDER BY embedding <=> $1::vector
            LIMIT ${idx}
            """,
            *params,
        )
    return [dict(r) for r in rows]


def _format_hit(h: dict) -> str:
    parts = [h.get("work_title") or "", h.get("section_label") or "", h["source_file"]]
    label = " · ".join(p for p in parts if p)
    return f"[{label} #{h['chunk_index']}]\n{h['content']}"


async def generate_answer(query: str, hits: list[dict]) -> str:
    context = "\n\n---\n\n".join(_format_hit(h) for h in hits)
    prompt = (
        f"{_SYSTEM_PROMPT}\n\n"
        f"# 참고 자료\n{context or '(관련 자료 없음)'}\n\n"
        f"# 요청\n{query}\n\n# 답변\n"
    )
    async with httpx.AsyncClient(timeout=180.0) as client:
        res = await client.post(
            f"{settings.ollama_host.rstrip('/')}/api/generate",
            json={"model": settings.novel_model, "prompt": prompt, "stream": False},
        )
        res.raise_for_status()
        return res.json().get("response", "").strip()


async def answer(
    pool,
    query: str,
    top_k: int | None = None,
    *,
    work_title: str | None = None,
    doc_kind: str | None = None,
) -> dict:
    hits = await search(pool, query, top_k, work_title=work_title, doc_kind=doc_kind)
    text = await generate_answer(query, hits)
    return {
        "answer": text,
        "sources": [
            {
                "source_file": h["source_file"],
                "work_title": h.get("work_title"),
                "doc_kind": h.get("doc_kind"),
                "section_label": h.get("section_label"),
                "chunk_index": h["chunk_index"],
                "similarity": round(float(h["similarity"]), 4),
            }
            for h in hits
        ],
    }
