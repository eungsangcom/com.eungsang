import re

_CHUNK_SIZE = 700
_OVERLAP = 100
_MAX_CHARS = 4000


def _sliding(text: str, size: int = _CHUNK_SIZE, overlap: int = _OVERLAP) -> list[str]:
    chunks: list[str] = []
    step = max(size - overlap, 1)
    for i in range(0, len(text), step):
        piece = text[i : i + size].strip()
        if piece:
            chunks.append(piece)
    return chunks


def chunk_by_type(text: str, doc_type: str) -> list[str]:
    """도서 유형별 청킹. 너무 긴 조각은 슬라이딩 윈도우로 다시 쪼갠다."""
    if doc_type == "structured_book":
        raw = re.split(r"\n(?=제\s*\d+\s*장|#{1,3}\s)", text)
    elif doc_type == "reference_book":
        raw = re.split(r"\n\s*\n", text)
    else:
        return _sliding(text)

    chunks: list[str] = []
    for block in raw:
        block = block.strip()
        if not block:
            continue
        if len(block) > _MAX_CHARS:
            chunks.extend(_sliding(block))
        else:
            chunks.append(block)
    return chunks
