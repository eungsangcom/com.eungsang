import httpx
from core.config import settings

async def get_embeddings(texts: list[str], model: str = None) -> list[list[float]]:
    model = model or settings.default_model
    async with httpx.AsyncClient(timeout=30.0) as client:
        res = await client.post(
            settings.embed_url,
            json={"texts": texts, "model": model}
        )
        res.raise_for_status()
        return res.json()["embeddings"]
