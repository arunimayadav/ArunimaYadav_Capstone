"""Step 2: Reason — ask Gemini who a file belongs to, its category, and its doc type."""

import json

import requests

GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

PROMPT_TEMPLATE = """You are the classification step of a personal file-archiving agent.
Given a document's filename and an excerpt of its text, decide:

1. ownership: "own" if this is the archive owner's own work (an essay, assignment
   submission, personal notes, resume, etc. written or produced BY {person_name}),
   or "other" if it's course/reference material the owner received (lecture slides,
   readings, handouts, someone else's document).
2. category: the course, club, internship, or personal-life category this document
   belongs to. Infer a short, clean label from the content (e.g. "Consumer Behaviour",
   "Internship", "Personal").{course_hint}
3. doc_type: a short plain document type (Essay, Notes, Slides, Reading, Assignment,
   Resume, Syllabus, etc.) — pick the closest fit.
4. title: a short, clean 2-5 word title describing the document's actual subject,
   derived from the filename and/or content — NOT the raw filename.
5. confidence: your confidence in this classification, 0.0-1.0.
6. reasoning: one sentence explaining the call.

Filename: {filename}

Text excerpt:
---
{excerpt}
---

Respond with ONLY a JSON object with exactly these keys:
ownership, category, doc_type, title, confidence, reasoning.
"""


def _course_hint(course_list: list) -> str:
    if not course_list:
        return ""
    listed = ", ".join(c.get("code", c.get("name", "")) for c in course_list)
    return f" Known courses to prefer when they match: {listed}."


def classify(perceived: dict, api_key: str, person_name: str, course_list: list, model: str) -> dict:
    prompt = PROMPT_TEMPLATE.format(
        person_name=person_name,
        course_hint=_course_hint(course_list),
        filename=perceived["filename"],
        excerpt=perceived["text_excerpt"] or "(no extractable text)",
    )

    resp = requests.post(
        GEMINI_URL.format(model=model),
        headers={"x-goog-api-key": api_key},
        json={
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json"},
        },
        timeout=60,
    )
    if not resp.ok:
        raise RuntimeError(f"Gemini API error {resp.status_code}: {resp.text[:500]}")
    data = resp.json()
    text = data["candidates"][0]["content"]["parts"][0]["text"]
    classification = json.loads(text)

    required = {"ownership", "category", "doc_type", "title", "confidence", "reasoning"}
    missing = required - classification.keys()
    if missing:
        raise ValueError(f"Gemini response missing keys: {missing}")

    return classification
