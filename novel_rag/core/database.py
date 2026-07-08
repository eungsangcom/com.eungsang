import asyncpg

from core.config import settings

_pool: asyncpg.Pool | None = None
_TABLE = "novel_docs_embeddings"


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(settings.db_dsn, min_size=2, max_size=10)
    return _pool


async def close_pool() -> None:
    global _pool
    if _pool:
        await _pool.close()
        _pool = None


async def ensure_schema(pool: asyncpg.Pool, dim: int) -> None:
    async with pool.acquire() as conn:
        await conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        await conn.execute(
            f"""
            CREATE TABLE IF NOT EXISTS {_TABLE} (
                id SERIAL PRIMARY KEY,
                source_file TEXT NOT NULL,
                work_title TEXT NOT NULL DEFAULT '',
                doc_kind TEXT NOT NULL DEFAULT 'prose',
                section_label TEXT NOT NULL DEFAULT '',
                chunk_index INTEGER NOT NULL,
                content TEXT NOT NULL,
                embedding vector({dim}) NOT NULL,
                created_at TIMESTAMPTZ DEFAULT now()
            );
            """
        )
        await conn.execute(
            f"""
            CREATE INDEX IF NOT EXISTS {_TABLE}_hnsw
            ON {_TABLE} USING hnsw (embedding vector_cosine_ops);
            """
        )
        await conn.execute(
            f"""
            CREATE INDEX IF NOT EXISTS {_TABLE}_work
            ON {_TABLE} (work_title);
            """
        )
