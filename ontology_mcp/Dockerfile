FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    fastapi \
    uvicorn \
    asyncpg \
    httpx \
    neo4j \
    pydantic-settings \
    python-dotenv

COPY . .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8421"]
