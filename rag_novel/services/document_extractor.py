from dataclasses import dataclass
from pathlib import Path

import fitz  # PyMuPDF


@dataclass
class NovelChunk:
    content: str
    section_label: str = ""
    work_title: str = ""
    doc_kind: str = "prose"


def normalize_text(text: str) -> str:
    """PDF 줄바꿈·공백 정리. Postgres UTF8에 넣지 못하는 NUL 바이트도 제거."""
    text = text.replace("\x00", "")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    # 하이픈으로 끊긴 단어 이어붙이기 (영문 PDF)
    text = __import__("re").sub(r"(\w)-\n(\w)", r"\1\2", text)
    text = __import__("re").sub(r"[ \t]+\n", "\n", text)
    text = __import__("re").sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def extract_from_bytes(data: bytes, suffix: str) -> str:
    suffix = suffix.lower()
    if suffix == ".pdf":
        doc = fitz.open(stream=data, filetype="pdf")
        try:
            parts = [page.get_text() for page in doc]
        finally:
            doc.close()
        return normalize_text("\n\n".join(parts))
    if suffix in (".txt", ".text", ".md"):
        for enc in ("utf-8", "utf-8-sig", "cp949", "euc-kr"):
            try:
                return normalize_text(data.decode(enc))
            except UnicodeDecodeError:
                continue
        return normalize_text(data.decode("utf-8", errors="replace"))
    raise ValueError(f"지원하지 않는 형식: {suffix}")


def extract_file(path: Path) -> str:
    return extract_from_bytes(path.read_bytes(), path.suffix)


def infer_work_title(path: Path, base: Path) -> str:
    rel = path.relative_to(base)
    if len(rel.parts) > 1:
        return rel.parts[0]
    return path.stem
