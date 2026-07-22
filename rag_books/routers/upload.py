from fastapi import APIRouter, File, HTTPException, UploadFile

from core.database import get_pool
from services import rag_service
from services.chunker import chunk_by_type
from services.pdf_extractor import detect_doc_type, extract_text

router = APIRouter(prefix="/documents", tags=["documents"])


@router.post("/upload")
async def upload_pdf(file: UploadFile = File(...)):
    if not (file.filename or "").lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="PDF 파일만 업로드할 수 있습니다.")

    pdf_bytes = await file.read()
    if not pdf_bytes:
        raise HTTPException(status_code=400, detail="빈 파일입니다.")

    text = extract_text(pdf_bytes)
    if not text.strip():
        raise HTTPException(status_code=422, detail="PDF 에서 텍스트를 추출하지 못했습니다.")

    doc_type = detect_doc_type(text[:4000])
    chunks = chunk_by_type(text, doc_type)

    pool = await get_pool()
    inserted = await rag_service.ingest_chunks(pool, file.filename, doc_type, chunks)

    return {
        "source_file": file.filename,
        "doc_type": doc_type,
        "chunks_ingested": inserted,
    }
