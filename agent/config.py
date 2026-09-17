"""Static config for the archivist agent. Edit these by hand as needed."""

PERSON_NAME = "Arunima"

GEMINI_MODEL = "gemini-flash-latest"

# Optional: known courses to bias classification. Leave empty and the
# reasoning step will infer a category straight from the document content.
COURSE_LIST: list[dict] = []

ARCHIVE_ROOT = "Archive"
