import re

import fitz  # PyMuPDF


def extract_text(pdf_bytes: bytes) -> str:
    """PDF 바이트에서 전체 텍스트를 페이지 순서대로 추출."""
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    try:
        parts = [page.get_text() for page in doc]
    finally:
        doc.close()
    return "\n\n".join(parts)


def detect_doc_type(text_sample: str) -> str:
    """간단한 휴리스틱으로 문서 타입 추정 (청킹 전략 선택용)."""
    words = max(len(text_sample.split()), 1)
    code_hits = len(re.findall(r"```|def |class |function\s*\(|import |=>|;\s*$", text_sample))
    if code_hits / words > 0.02:
        return "official_doc"
    if re.search(r"아키텍처|컨벤션|가이드라인|architecture|convention", text_sample, re.IGNORECASE):
        return "internal_doc"
    return "theory_book"
