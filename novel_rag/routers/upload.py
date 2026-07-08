from fastapi import APIRouter, File, HTTPException, UploadFile

from core.database import get_pool
from services import rag_service
from services.chunker import chunk_novel
from services.document_extractor import extract_from_bytes, infer_work_title

router = APIRouter(prefix="/documents", tags=["documents"])

_ALLOWED = (".pdf", ".txt", ".text", ".md")


@router.post("/upload")
async def upload_document(file: UploadFile = File(...)):
    name = (file.filename or "").lower()
    if not any(name.endswith(ext) for ext in _ALLOWED):
        raise HTTPException(status_code=400, detail="PDF·TXT·MD 파일만 업로드할 수 있습니다.")

    suffix = "." + name.rsplit(".", 1)[-1]
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="빈 파일입니다.")

    try:
        text = extract_from_bytes(data, suffix)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    if not text.strip():
        raise HTTPException(status_code=422, detail="텍스트를 추출하지 못했습니다.")

    work_title = file.filename.rsplit(".", 1)[0] if file.filename else "unknown"
    chunks = chunk_novel(text, work_title=work_title)

    pool = await get_pool()
    inserted = await rag_service.ingest_chunks(pool, file.filename or "upload", chunks)

    kinds = {c.doc_kind for c in chunks}
    return {
        "source_file": file.filename,
        "work_title": work_title,
        "doc_kinds": sorted(kinds),
        "chunks_ingested": inserted,
    }
