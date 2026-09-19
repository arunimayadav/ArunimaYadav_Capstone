"""Step 1: Perceive — read a file off disk and pull out its text."""

import datetime
import os


def _extract_pdf(path: str) -> str:
    from pypdf import PdfReader

    reader = PdfReader(path)
    pages = [page.extract_text() or "" for page in reader.pages[:15]]
    return "\n".join(pages)


def _extract_docx(path: str) -> str:
    import docx

    doc = docx.Document(path)
    return "\n".join(p.text for p in doc.paragraphs)


def _extract_pptx(path: str) -> str:
    from pptx import Presentation

    prs = Presentation(path)
    chunks = []
    for slide in prs.slides:
        for shape in slide.shapes:
            if shape.has_text_frame:
                text = shape.text_frame.text.strip()
                if text:
                    chunks.append(text)
    return "\n".join(chunks)


def _extract_plain(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


EXTRACTORS = {
    ".pdf": _extract_pdf,
    ".docx": _extract_docx,
    ".pptx": _extract_pptx,
    ".txt": _extract_plain,
    ".md": _extract_plain,
}


def perceive(file_path: str, excerpt_chars: int = 4000) -> dict:
    """Read the file and return its raw text plus filesystem metadata."""
    filename = os.path.basename(file_path)
    _, ext = os.path.splitext(filename)
    ext = ext.lower()

    extractor = EXTRACTORS.get(ext)
    if extractor is None:
        raise ValueError(f"No extractor registered for extension '{ext}'")

    raw_text = extractor(file_path)
    stat = os.stat(file_path)
    mtime_date = datetime.date.fromtimestamp(stat.st_mtime).isoformat()

    return {
        "path": file_path,
        "filename": filename,
        "extension": ext,
        "text_excerpt": raw_text.strip()[:excerpt_chars],
        "char_count": len(raw_text),
        "mtime_date": mtime_date,
    }
