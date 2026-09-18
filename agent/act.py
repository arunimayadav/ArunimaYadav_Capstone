"""Step 3: Act — apply the filename-nomenclature skill, then plan the rename.

Naming logic mirrors skills/filename-nomenclature.md exactly. The file stays in
its current directory — this only renames it, it does not move it anywhere.
The actual rename is NOT performed here: this function only decides the new
name/path. The rename itself is executed by the orchestrating agent via the
filesystem MCP server, so every file-system mutation stays behind one
auditable tool call.
"""

import os
import re

INVALID_CHARS = r'[\\/:*?"<>|]'


def _clean(text: str) -> str:
    text = re.sub(INVALID_CHARS, "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def build_filename(perceived: dict, classification: dict, person_name: str) -> str:
    ext = perceived["extension"]
    ownership = classification["ownership"]

    if ownership == "own":
        what_it_is = _clean(classification["doc_type"]).replace(" ", "")
        date = perceived["mtime_date"]
        name = f"{person_name}_{what_it_is}_{date}"
    else:
        category = _clean(classification["category"]).replace(" ", "")
        title = _clean(classification["title"]).replace(" ", "")
        doc_type = _clean(classification["doc_type"]).replace(" ", "")
        name = f"{category}_{title}_{doc_type}"

    return f"{name}{ext}"


def resolve_collision(filename: str, existing_filenames: list) -> str:
    if filename not in existing_filenames:
        return filename

    stem, ext = os.path.splitext(filename)
    n = 2
    while f"{stem}-{n}{ext}" in existing_filenames:
        n += 1
    return f"{stem}-{n}{ext}"


def plan_action(perceived: dict, classification: dict, person_name: str, existing_filenames: list) -> dict:
    raw_name = build_filename(perceived, classification, person_name)
    source_dir = os.path.dirname(perceived["path"])

    # the file's own current name isn't a collision with itself
    others = [f for f in existing_filenames if f != perceived["filename"]]
    final_name = resolve_collision(raw_name, others)

    return {
        "source_path": perceived["path"],
        "dest_dir": source_dir,
        "dest_filename": final_name,
        "dest_path": os.path.join(source_dir, final_name),
    }
