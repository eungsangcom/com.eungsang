from fastapi import FastAPI
from contextlib import asynccontextmanager
from core.database import get_pool, close_pool
from services.neo4j_service import get_driver, close_driver
from routers.ontology import router as ontology_router
from routers.graph import router as graph_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    await get_pool()
    print("DB 연결 풀 초기화 완료")
    await get_driver()
    print("Neo4j 드라이버 초기화 완료")
    yield
    await close_pool()
    await close_driver()
    print("모든 연결 종료")

app = FastAPI(
    title="Ontology MCP Server",
    description="온톨로지 기반 MCP 서버 - pgvector + Neo4j + KURE-v1",
    version="2.0.0",
    lifespan=lifespan
)

app.include_router(ontology_router)
app.include_router(graph_router)

@app.get("/health")
async def health():
    return {"status": "ok", "service": "ontology-mcp", "version": "2.0.0"}
