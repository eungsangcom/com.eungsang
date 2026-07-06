from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from services import neo4j_service as neo
from services import ontology as pgv
from core.database import get_pool

router = APIRouter(prefix="/graph", tags=["graph"])

class RelationBody(BaseModel):
    from_id: str
    to_id: str
    relation_type: str
    weight: float = 1.0

class HybridSearchRequest(BaseModel):
    query: str
    top_k: int = 5
    namespace: str = "default"
    expand_neighbors: bool = True
    neighbor_depth: int = 1

@router.post("/relations")
async def create_graph_relation(body: RelationBody):
    return await neo.upsert_relationship(
        body.from_id, body.to_id, body.relation_type, body.weight
    )

@router.get("/neighbors/{entity_id}")
async def get_neighbors(entity_id: str, depth: int = 2):
    result = await neo.get_neighbors(entity_id, depth)
    if not result:
        raise HTTPException(status_code=404, detail="No neighbors found")
    return result

@router.get("/path")
async def get_path(from_id: str, to_id: str):
    result = await neo.get_path(from_id, to_id)
    if not result:
        raise HTTPException(status_code=404, detail="No path found")
    return result

@router.post("/hybrid-search")
async def hybrid_search(body: HybridSearchRequest):
    pool = await get_pool()
    vector_results = await pgv.search_entities(
        pool, body.query, body.top_k, body.namespace
    )
    if not body.expand_neighbors:
        return {"vector_results": [dict(r) for r in vector_results], "graph_expanded": []}
    seen_ids = {r["entity_id"] for r in vector_results}
    graph_expanded = []
    for row in vector_results[:3]:
        neighbors = await neo.get_neighbors(row["entity_id"], body.neighbor_depth)
        for n in neighbors:
            if n["entity_id"] not in seen_ids:
                seen_ids.add(n["entity_id"])
                graph_expanded.append(n)
    return {
        "vector_results": [dict(r) for r in vector_results],
        "graph_expanded": graph_expanded
    }
