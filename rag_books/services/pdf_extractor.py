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
    """간단한 휴리스틱으로 도서 유형을 추정 (청킹 전략 선택용)."""
    if re.search(r"제\s*\d+\s*장|chapter|목차|contents", text_sample, re.IGNORECASE):
        return "structured_book"
    if re.search(r"참고문헌|각주|정의|이론|references|theorem", text_sample, re.IGNORECASE):
        return "reference_book"
    return "prose_book"
