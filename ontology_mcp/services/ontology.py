import asyncpg
from services.embedding import get_embeddings
from services import neo4j_service as neo

async def upsert_entity(pool, entity_id, entity_type, label,
                         content, description=None, namespace="default", model="kure"):
    emb = await get_embeddings([content], model)
    async with pool.acquire() as conn:
        await conn.execute("""
            INSERT INTO ontology_embeddings
                (entity_id, entity_type, label, content, description, embedding, model_name, namespace, updated_at)
            VALUES ($1,$2,$3,$4,$5,$6::vector,$7,$8,now())
            ON CONFLICT (entity_id) DO UPDATE
            SET label=$3, content=$4, description=$5,
                embedding=$6::vector, model_name=$7, updated_at=now()
        """, entity_id, entity_type, label, content, description, str(emb[0]), model, namespace)

    # Neo4j 동기화
    await neo.upsert_node(entity_id, entity_type, label, content, namespace)

    return {"entity_id": entity_id, "status": "upserted"}

async def get_entity(pool, entity_id: str):
    async with pool.acquire() as conn:
        return await conn.fetchrow(
            "SELECT entity_id,entity_type,label,content,description,model_name,namespace,created_at,updated_at FROM ontology_embeddings WHERE entity_id=$1",
            entity_id
        )

async def delete_entity(pool, entity_id: str):
    async with pool.acquire() as conn:
        await conn.execute("DELETE FROM ontology_relations WHERE from_id=$1 OR to_id=$1", entity_id)
        await conn.execute("DELETE FROM ontology_embeddings WHERE entity_id=$1", entity_id)
    return {"entity_id": entity_id, "status": "deleted"}

async def upsert_relation(pool, from_id, to_id, relation_type,
                           weight=1.0, properties={}, relation_id=None):
    rid = relation_id or f"{from_id}__{relation_type}__{to_id}"
    import json
    async with pool.acquire() as conn:
        await conn.execute("""
            INSERT INTO ontology_relations (relation_id,from_id,to_id,relation_type,weight,properties)
            VALUES ($1,$2,$3,$4,$5,$6)
            ON CONFLICT (relation_id) DO UPDATE SET weight=$5, properties=$6
        """, rid, from_id, to_id, relation_type, weight, json.dumps(properties))
    return {"relation_id": rid, "status": "upserted"}

async def search_entities(pool, query, top_k=5, namespace="default", entity_type=None, model="kure"):
    emb = await get_embeddings([query], model)
    vector = str(emb[0])
    async with pool.acquire() as conn:
        if entity_type:
            rows = await conn.fetch("""
                SELECT entity_id, entity_type, label, content,
                       1-(embedding<=>$1::vector) AS similarity
                FROM ontology_embeddings
                WHERE namespace=$2 AND entity_type=$3
                ORDER BY embedding<=>$1::vector LIMIT $4
            """, vector, namespace, entity_type, top_k)
        else:
            rows = await conn.fetch("""
                SELECT entity_id, entity_type, label, content,
                       1-(embedding<=>$1::vector) AS similarity
                FROM ontology_embeddings
                WHERE namespace=$2
                ORDER BY embedding<=>$1::vector LIMIT $3
            """, vector, namespace, top_k)
    return rows

async def get_relations(pool, entity_id: str):
    async with pool.acquire() as conn:
        return await conn.fetch("""
            SELECT r.*, e1.label as from_label, e2.label as to_label
            FROM ontology_relations r
            JOIN ontology_embeddings e1 ON r.from_id=e1.entity_id
            JOIN ontology_embeddings e2 ON r.to_id=e2.entity_id
            WHERE r.from_id=$1 OR r.to_id=$1
        """, entity_id)
