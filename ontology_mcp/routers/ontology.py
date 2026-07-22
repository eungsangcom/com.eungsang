from fastapi import APIRouter, HTTPException
from models.ontology import EntityCreate, RelationCreate, SearchRequest
from services import ontology as svc
from core.database import get_pool

router = APIRouter(prefix="/ontology", tags=["ontology"])

@router.post("/entities")
async def create_entity(body: EntityCreate):
    pool = await get_pool()
    return await svc.upsert_entity(
        pool, body.entity_id, body.entity_type, body.label,
        body.content, body.description, body.namespace, body.model
    )

@router.get("/entities/{entity_id}")
async def read_entity(entity_id: str):
    pool = await get_pool()
    row = await svc.get_entity(pool, entity_id)
    if not row:
        raise HTTPException(status_code=404, detail="Entity not found")
    return dict(row)

@router.delete("/entities/{entity_id}")
async def remove_entity(entity_id: str):
    pool = await get_pool()
    return await svc.delete_entity(pool, entity_id)


@router.post("/entities/delete-by-prefix")
async def remove_entities_by_prefix(body: dict):
    pool = await get_pool()
    namespace = str(body.get("namespace") or "").strip()
    prefix = str(body.get("prefix") or "").strip()
    return await svc.delete_entities_by_prefix(pool, namespace, prefix)

@router.post("/relations")
async def create_relation(body: RelationCreate):
    pool = await get_pool()
    return await svc.upsert_relation(
        pool, body.from_id, body.to_id, body.relation_type,
        body.weight, body.properties, body.relation_id
    )

@router.get("/entities/{entity_id}/relations")
async def read_relations(entity_id: str):
    pool = await get_pool()
    rows = await svc.get_relations(pool, entity_id)
    return [dict(r) for r in rows]

@router.post("/search")
async def search(body: SearchRequest):
    pool = await get_pool()
    rows = await svc.search_entities(
        pool, body.query, body.top_k,
        body.namespace, body.entity_type, body.model
    )
    return [dict(r) for r in rows]
