import re

from services.document_extractor import NovelChunk

_CHAPTER_RE = re.compile(
    r"^(?:"
    r"제\s*\d+\s*[화장편권부]|"
    r"제\s*[일이삼사오육칠팔구십백천]+\s*[화장편권부]|"
    r"Chapter\s+\d+|CHAPTER\s+[IVXLC\d]+|"
    r"PART\s+[IVXLC\d]+|"
    r"\d+\s*장|"
    r"권\s*\d+|"
    r"#+\s+.+"
    r")",
    re.IGNORECASE | re.MULTILINE,
)
_SCENE_RE = re.compile(r"\n\s*[*#─—\-]{3,}\s*\n")
_LORE_HINT = re.compile(
    r"설정|세계관|등장인물|인물 소개|용어|로어|timeline|캐릭터|마법 체계|지리",
    re.IGNORECASE,
)
_GENRE_HINT = re.compile(
    r"장르|서사|구조|플롯|3막|히어로즈 저니|클리셰|문체 가이드|작법",
    re.IGNORECASE,
)

_SCENE_MAX = 1400
_SCENE_OVERLAP = 180
_SLIDE_MAX = 1200


def detect_doc_kind(text_sample: str) -> str:
    sample = text_sample[:6000]
    lore_hits = len(_LORE_HINT.findall(sample))
    genre_hits = len(_GENRE_HINT.findall(sample))
    if lore_hits >= 2 or re.search(r"^[·•\-]\s*.+[:：]", sample, re.MULTILINE):
        return "lore"
    if genre_hits >= 2:
        return "genre_guide"
    return "prose"


def _split_chapters(text: str) -> list[tuple[str, str]]:
    """(section_label, body) 목록. 챕터 헤더가 없으면 단일 블록."""
    matches = list(_CHAPTER_RE.finditer(text))
    if not matches:
        return [("", text)]

    sections: list[tuple[str, str]] = []
    for i, m in enumerate(matches):
        label = m.group(0).strip()
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[start:end].strip()
        if body:
            sections.append((label, body))
    if not sections and text.strip():
        sections.append(("", text.strip()))
    return sections


def _split_scenes(body: str) -> list[str]:
    parts = _SCENE_RE.split(body)
    scenes = [p.strip() for p in parts if p.strip()]
    return scenes or ([body.strip()] if body.strip() else [])


def _sliding(text: str, size: int = _SLIDE_MAX, overlap: int = _SCENE_OVERLAP) -> list[str]:
    chunks: list[str] = []
    step = max(size - overlap, 1)
    for i in range(0, len(text), step):
        piece = text[i : i + size].strip()
        if piece:
            chunks.append(piece)
    return chunks


def _pack_scene(scene: str, max_len: int) -> list[str]:
    if len(scene) <= max_len:
        return [scene]
    return _sliding(scene, size=max_len, overlap=_SCENE_OVERLAP)


def chunk_novel(text: str, *, work_title: str, doc_kind: str | None = None) -> list[NovelChunk]:
    kind = doc_kind or detect_doc_kind(text[:6000])
    chunks: list[NovelChunk] = []

    if kind == "lore":
        blocks = re.split(r"\n\s*\n", text)
        for block in blocks:
            block = block.strip()
            if not block:
                continue
            for piece in _pack_scene(block, _SCENE_MAX):
                chunks.append(NovelChunk(piece, section_label="", work_title=work_title, doc_kind=kind))
        return chunks

    if kind == "genre_guide":
        for piece in _sliding(text, size=_SLIDE_MAX, overlap=_SCENE_OVERLAP):
            chunks.append(NovelChunk(piece, work_title=work_title, doc_kind=kind))
        return chunks

    # prose: chapter → scene → pack
    for chapter_label, body in _split_chapters(text):
        for scene in _split_scenes(body):
            for piece in _pack_scene(scene, _SCENE_MAX):
                chunks.append(
                    NovelChunk(
                        piece,
                        section_label=chapter_label,
                        work_title=work_title,
                        doc_kind="prose",
                    )
                )
    return chunks
