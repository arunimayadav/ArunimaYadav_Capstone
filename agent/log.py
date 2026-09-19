"""Step 5: Log — append a searchable record of the rename to a JSON Lines file.

One line per renamed file, so files can be found later by describing their
content (via text_excerpt), not just by their new filename.
"""

import datetime
import json
import os


def append_entry(perceived: dict, classification: dict, plan: dict, log_path: str) -> None:
    entry = {
        "logged_at": datetime.datetime.now().isoformat(timespec="seconds"),
        "original_filename": perceived["filename"],
        "new_filename": plan["dest_filename"],
        "path": plan["dest_path"],
        "ownership": classification["ownership"],
        "category": classification["category"],
        "doc_type": classification["doc_type"],
        "title": classification["title"],
        "text_excerpt": perceived["text_excerpt"],
    }

    log_dir = os.path.dirname(log_path)
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)

    with open(log_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
