"""Step 3: Act — apply the filename-nomenclature skill, then plan the archive move.

Naming logic mirrors skills/filename-nomenclature.md exactly. The actual move is
NOT performed here: this function only decides source/destination. The move itself
is executed by the orchestrating agent via the filesystem MCP server, so every
file-system mutation stays behind one auditable tool call.
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


def plan_action(perceived: dict, classification: dict, person_name: str, archive_root: str, existing_filenames: list) -> dict:
    raw_name = build_filename(perceived, classification, person_name)
    final_name = resolve_collision(raw_name, existing_filenames)

    if classification["ownership"] == "own":
        dest_dir = os.path.join(archive_root, "Own")
    else:
        dest_dir = os.path.join(archive_root, _clean(classification["category"]))

    return {
        "source_path": perceived["path"],
        "dest_dir": dest_dir,
        "dest_filename": final_name,
        "dest_path": os.path.join(dest_dir, final_name),
    }
