"""로컬/NAS 디렉터리의 PDF·TXT를 일괄 임베딩해 pgvector 에 적재한다.

사용:
    cd novel_rag
    python3.13 ingest_local.py "/path/to/novels"
    python3.13 ingest_local.py <dir> --force
"""

import asyncio
import sys
import time
from pathlib import Path

from core.database import close_pool, get_pool
from services import rag_service
from services.chunker import chunk_novel
from services.document_extractor import extract_file, infer_work_title

_TABLE = "novel_docs_embeddings"
_EXTENSIONS = {".pdf", ".txt", ".text", ".md"}


async def _already_ingested(pool, source_file: str) -> bool:
    async with pool.acquire() as conn:
        try:
            row = await conn.fetchrow(
                f"SELECT 1 FROM {_TABLE} WHERE source_file = $1 LIMIT 1",
                source_file,
            )
        except Exception:
            return False
    return row is not None


async def ingest_dir(base: Path, force: bool) -> None:
    files = sorted(
        p for p in base.rglob("*") if p.is_file() and p.suffix.lower() in _EXTENSIONS
    )
    if not files:
        print(f"PDF/TXT 없음: {base}")
        return

    pool = await get_pool()
    print(f"대상 {len(files)}개 파일 · base={base}\n")

    grand_chunks = 0
    for idx, path in enumerate(files, 1):
        source_file = str(path.relative_to(base))
        head = f"[{idx}/{len(files)}] {source_file}"

        if not force and await _already_ingested(pool, source_file):
            print(f"{head} — 이미 적재됨, 건너뜀")
            continue

        t0 = time.time()
        try:
            text = extract_file(path)
        except Exception as e:
            print(f"{head} — 추출 실패: {e}")
            continue

        if not text.strip():
            print(f"{head} — 텍스트 없음, 건너뜀")
            continue

        work_title = infer_work_title(path, base)
        chunks = chunk_novel(text, work_title=work_title)
        kinds = {c.doc_kind for c in chunks}
        print(f"{head} — work={work_title} kinds={sorted(kinds)} chunks={len(chunks)} 임베딩 중…")

        try:
            inserted = await rag_service.ingest_chunks(pool, source_file, chunks)
        except Exception as e:
            print(f"{head} — 적재 실패: {e}")
            continue

        grand_chunks += inserted
        print(f"{head} — 완료 {inserted} chunks ({time.time() - t0:.1f}s)\n")

    print(f"\n=== 전체 완료: {grand_chunks} chunks 적재 ===")
    await close_pool()


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv[1:]
    if not args:
        print("사용: python3.13 ingest_local.py <디렉터리> [--force]")
        raise SystemExit(1)
    base = Path(args[0]).expanduser()
    if not base.is_dir():
        print(f"디렉터리가 아님: {base}")
        raise SystemExit(1)
    asyncio.run(ingest_dir(base, force))


if __name__ == "__main__":
    main()
