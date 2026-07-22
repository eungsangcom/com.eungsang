"""로컬/NAS 디렉터리의 PDF를 일괄 임베딩해 pgvector 에 적재한다.

HTTP 업로드 대신 파일을 직접 읽어 처리하므로 대용량(수 GB) 문서에 적합하다.
이미 적재된 파일(source_file 기준)은 건너뛴다. --force 로 재적재.

사용:
    cd code_rag
    python3 ingest_local.py "/Volumes/프리마스/멀티미디어/E-Book/IT"
    python3 ingest_local.py <dir> --force
"""

import asyncio
import sys
import time
from pathlib import Path

from core.database import get_pool, close_pool
from services import rag_service
from services.chunker import chunk_by_type
from services.pdf_extractor import detect_doc_type, extract_text

_TABLE = "code_docs_embeddings"


async def _already_ingested(pool, source_file: str) -> bool:
    async with pool.acquire() as conn:
        try:
            row = await conn.fetchrow(
                f"SELECT 1 FROM {_TABLE} WHERE source_file = $1 LIMIT 1",
                source_file,
            )
        except Exception:
            return False  # 테이블이 아직 없으면 최초 적재
    return row is not None


async def ingest_dir(base: Path, force: bool) -> None:
    pdfs = sorted(p for p in base.rglob("*.pdf"))
    if not pdfs:
        print(f"PDF 없음: {base}")
        return

    pool = await get_pool()
    print(f"대상 {len(pdfs)}개 PDF · base={base}\n")

    grand_chunks = 0
    for idx, path in enumerate(pdfs, 1):
        source_file = str(path.relative_to(base))
        head = f"[{idx}/{len(pdfs)}] {source_file}"

        if not force and await _already_ingested(pool, source_file):
            print(f"{head} — 이미 적재됨, 건너뜀")
            continue

        t0 = time.time()
        try:
            text = extract_text(path.read_bytes())
        except Exception as e:
            print(f"{head} — 추출 실패: {e}")
            continue

        if not text.strip():
            print(f"{head} — 텍스트 없음(이미지 PDF?), 건너뜀")
            continue

        doc_type = detect_doc_type(text[:4000])
        chunks = chunk_by_type(text, doc_type)
        print(f"{head} — type={doc_type} chunks={len(chunks)} 임베딩 중…")

        try:
            inserted = await rag_service.ingest_chunks(pool, source_file, doc_type, chunks)
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
        print("사용: python3 ingest_local.py <PDF_디렉터리> [--force]")
        raise SystemExit(1)
    base = Path(args[0]).expanduser()
    if not base.is_dir():
        print(f"디렉터리가 아님: {base}")
        raise SystemExit(1)
    asyncio.run(ingest_dir(base, force))


if __name__ == "__main__":
    main()
