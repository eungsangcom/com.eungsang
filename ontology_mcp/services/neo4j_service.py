from neo4j import AsyncGraphDatabase
from core.config import settings

_driver = None

async def get_driver():
    global _driver
    if _driver is None:
        _driver = AsyncGraphDatabase.driver(
            settings.neo4j_uri,
            auth=(settings.neo4j_user, settings.neo4j_password)
        )
    return _driver

async def close_driver():
    global _driver
    if _driver:
        await _driver.close()
        _driver = None

async def upsert_node(entity_id, entity_type, label, content, namespace="default"):
    driver = await get_driver()
    async with driver.session() as session:
        await session.run("""
            MERGE (n:OntologyNode {entity_id: $entity_id})
            SET n.entity_type = $entity_type,
                n.label = $label,
                n.content = $content,
                n.namespace = $namespace,
                n.updated_at = datetime()
        """, entity_id=entity_id, entity_type=entity_type,
             label=label, content=content, namespace=namespace)
    return {"entity_id": entity_id, "status": "upserted_neo4j"}


async def delete_node(entity_id: str):
    driver = await get_driver()
    async with driver.session() as session:
        await session.run(
            """
            MATCH (n:OntologyNode {entity_id: $entity_id})
            DETACH DELETE n
            """,
            entity_id=entity_id,
        )
    return {"entity_id": entity_id, "status": "deleted_neo4j"}

async def upsert_relationship(from_id, to_id, relation_type, weight=1.0):
    driver = await get_driver()
    async with driver.session() as session:
        await session.run(f"""
            MATCH (a:OntologyNode {{entity_id: $from_id}})
            MATCH (b:OntologyNode {{entity_id: $to_id}})
            MERGE (a)-[r:{relation_type}]->(b)
            SET r.weight = $weight, r.updated_at = datetime()
        """, from_id=from_id, to_id=to_id, weight=weight)
    return {"relation": f"{from_id}-[{relation_type}]->{to_id}", "status": "upserted"}

async def get_neighbors(entity_id, depth=2):
    # Neo4j는 variable-length path에 파라미터 사용 불가 → f-string으로 직접 삽입
    depth = max(1, min(int(depth), 5))  # 최대 5로 제한
    driver = await get_driver()
    async with driver.session() as session:
        result = await session.run(f"""
            MATCH path = (n:OntologyNode {{entity_id: $entity_id}})-[*1..{depth}]-(m:OntologyNode)
            RETURN DISTINCT m.entity_id AS entity_id,
                            m.label AS label,
                            m.entity_type AS entity_type,
                            m.content AS content
        """, entity_id=entity_id)
        return [dict(r) async for r in result]

async def get_path(from_id, to_id):
    driver = await get_driver()
    async with driver.session() as session:
        result = await session.run("""
            MATCH path = shortestPath(
                (a:OntologyNode {entity_id: $from_id})-[*]-(b:OntologyNode {entity_id: $to_id})
            )
            RETURN [node IN nodes(path) | node.label] AS labels,
                   [rel IN relationships(path) | type(rel)] AS relations,
                   length(path) AS path_length
        """, from_id=from_id, to_id=to_id)
        records = [dict(r) async for r in result]
        return records[0] if records else None
