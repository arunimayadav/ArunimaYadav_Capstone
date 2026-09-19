"""Static config for the archivist agent. Edit these by hand as needed."""

PERSON_NAME = "Arunima"

GEMINI_MODEL = "gemini-flash-latest"

# Optional: known courses to bias classification. Leave empty and the
# reasoning step will infer a category straight from the document content.
COURSE_LIST: list[dict] = []

# JSON Lines file recording every rename with its new name and original text
# excerpt, so files can be found later by content, not just by filename.
LOG_PATH = "archive_log.jsonl"
