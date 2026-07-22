import httpx

from core.config import settings


async def embed_texts(texts: list[str]) -> list[list[float]]:
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(
            settings.embed_url,
            json={"texts": texts, "model": settings.embed_model},
        )
        res.raise_for_status()
        embeddings = res.json()["embeddings"]
    if not isinstance(embeddings, list) or not embeddings:
        raise ValueError("임베딩 응답에 embeddings 배열이 없습니다.")
    return embeddings


async def embed_one(text: str) -> list[float]:
    return (await embed_texts([text]))[0]
