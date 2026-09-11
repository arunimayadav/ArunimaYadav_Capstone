Coursework Archivist
1. Problem Statement
Coursework accumulates in Downloads and Desktop faster than any manual filing habit survives — lecture slides, readings, assignment briefs, and submitted work all land with generic, uninformative filenames (Untitled.pdf, download (3).docx, Final_v2_FINAL.pptx). Each file could be filed correctly in the moment it arrives, but that requires interrupting whatever you're doing to open it, figure out which course and category it belongs to, rename it, and move it — a small tax that's easy to defer and, once deferred, never comes back to. Over a semester this compounds: the backlog grows, filenames stop meaning anything, and by finals the search cost of finding "that one slide deck with the midterm review" exceeds the cost of just re-downloading or re-requesting it. The gap isn't that filing is hard — it's that it's manual, so it doesn't happen consistently, and nothing downstream (search) works well when the upstream organization never happened.

2. Goal / Scope
In scope (prototype):

Monitors Downloads and Desktop only, not the whole filesystem.
Handles .pdf, .docx, .pptx (plus scanned/image-based PDFs via OCR fallback). No video, audio, spreadsheets, or archive files (.zip) in v1.
Classifies against a fixed, user-maintained course list (hardcoded config, not inferred from an academic calendar/API).
Files into a single local archive folder on the same machine — no cloud sync, no multi-device story.
One user, one machine. No collaboration or sharing features.
Confidence-gated auto-filing with a manual CLI review queue for anything ambiguous.
Retrieval via a local CLI command (archivist find "..."), not a GUI search app.
Explicitly cut (not this semester):

No mobile ingestion (photos of handouts taken on a phone).
No email attachment monitoring.
No multi-user or shared-course support.
No web dashboard — CLI only.
No automatic course-calendar sync; the course list is typed in once and edited by hand.
3. Why This Needs an Agent
The core operation — "given this file, which course and category does it belong to?" — is a judgment call under ambiguity, not a lookup. A rule-based script can match on obvious signals (a filename containing "DESG320"), but most real files don't self-announce: a PDF named syllabus.pdf could belong to any of five courses; a slide deck's course is often only inferable from its actual content (terminology, professor's name in a footer, assignment framing). This requires reading an excerpt and reasoning about which course it most plausibly belongs to and what category it represents (assignment vs. reference vs. final) — exactly the kind of inference an LLM call handles and a fixed rule set doesn't.

Separately, it needs to be an agent rather than a script because the point is to remove the manual step entirely. A script you run on demand still requires you to remember to run it, which is the same behavioral failure that causes the mess in the first place. A background watcher that acts on files as they arrive — without being invoked — is what actually closes the loop between "file lands" and "file is organized."

4. User Flow
File is saved. Student downloads a PDF or saves a file to Desktop (e.g., a professor emails slides, or a .docx assignment is exported from a doc tool).
Agent notices. The watcher process detects the new file, waits for the write to finish (debounce), and hands it to the extractor.
Extraction. Filename, file type, and a text excerpt (native text layer, or OCR if scanned) are pulled.
Classification. The excerpt + filename + known course list go to a local LLM call, which returns a suggested course, document type, clean filename, and a confidence score with reasoning.
Branch on confidence:
High confidence → file is renamed and moved into Archive/<Course>/<Type>/ automatically. The move is logged.
Low confidence → file is left in place (or staged) and added to a pending review queue; nothing is moved yet.
Student reviews (async, periodic). Runs archivist review at their own pace — sees each pending file's suggested classification and reasoning, and accepts, edits, or rejects it. Accepted items go through the same file/rename/log path as an auto-filed item.
Later: retrieval. Weeks later, student runs archivist find "TUI midterm slides". The query is embedded and matched semantically against the index (built from extracted text at classification time), returning the right file even though the student doesn't remember its exact filename.
Trust/undo loop. If something was filed wrong (auto or reviewed), archivist undo <id> reverses it using the move log, so the system stays low-stakes to rely on.
5. System Architecture
                 ┌────────────┐
Downloads/Desktop│  Watcher   │  (watchdog, debounced)
                 └─────┬──────┘
                        ▼
                 ┌────────────┐
                 │ Extractor  │  filename, filetype, text excerpt (+ OCR fallback)
                 └─────┬──────┘
                        ▼
                 ┌────────────┐
                 │ Classifier │  local LLM (Ollama) + course list in context
                 └─────┬──────┘
                        ▼
            confidence ≥ threshold?
              │yes              │no
              ▼                 ▼
       ┌────────────┐    ┌──────────────┐
       │Action layer│    │Pending queue │──▶ archivist review (CLI)
       │rename/move │◀───┘  (accepted)
       │+ moves log │
       └─────┬──────┘
              ▼
       ┌────────────┐
       │Index (SQLite)│  extracted text + tags + local embedding
       └─────┬──────┘
              ▼
       archivist find "..."  (CLI retrieval)
Watcher — file system monitor (watchdog); the only always-running piece.
Extractor — per-filetype text/metadata pull, with OCR as a fallback path for scanned content.
Classifier — one LLM call per file; course list + naming convention are injected as context; returns structured JSON.
Action layer — owns renaming, moving, and appending to an append-only move log; also owns undo.
Index/retrieval — SQLite table of file metadata + text + embedding; retrieval is a local embed-and-cosine-similarity search, no external index service.
UI — deliberately minimal: a CLI (archivist review, archivist find, archivist undo). No GUI in v1.
6. Data Model
files table — one row per archived (or pending) file:

field	notes
id	primary key
original_name	as first seen
current_name	after rename, if filed
original_path / current_path	for undo and lookup
course	classified course code
doc_type	assignment / reference / final / lecture / other
confidence	0–1 score from classifier
status	filed, pending_review, rejected
extracted_text	truncated excerpt used for classification + indexing
embedding	BLOB, local embedding vector
reasoning	model's one-line rationale (surfaced in the review queue)
created_at	first-seen timestamp
moves table — append-only log, one row per action taken:

field	notes
id	primary key
file_id	FK into files
src_path, dst_path	for reversal
ts	when the move happened
triggered_by	auto or reviewed
reversed	boolean — set by undo
Edge cases this forces early thought on:

Duplicate filename at destination — append a disambiguating suffix (e.g., short hash or -2) rather than overwrite; never silently clobber an existing file.
Misclassification after auto-file — undo must restore both the file location and the index/status, not just move the file back.
File modified after filing — out of scope for v1 detection (the watcher only reacts to Downloads/Desktop, not the archive folder itself), but worth flagging as a known gap.
Re-processing a rejected file — a rejected status should prevent the same file from resurfacing in the review queue on every watcher restart.
7. Key Design Decisions & Trade-offs
Confirm low-confidence rather than always auto-move. Autonomous file-moving is the riskiest part of the system — a wrong move erodes trust immediately and silently. Gating on confidence trades a little automation for a system that fails safe (file stays put, gets reviewed) instead of failing loud (file goes missing into the wrong course folder). The cost is a queue to periodically clear; the alternative cost is not trusting the tool at all.
Background watcher, not an on-demand command. The entire justification for calling this "agentic" rather than a script is that it acts without being invoked. An on-demand command reintroduces the exact behavioral gap (remembering to run it) that causes the mess in section 1. The trade-off is operational complexity — something has to keep the watcher alive across reboots/logouts.
Hardcoded course list vs. inferred. A fixed, user-edited list (course code + name + known aliases) is deliberately simple: no dependency on a school API, and the classifier's job becomes "pick from a known small set" rather than "invent a course," which is both more accurate and easier to evaluate. The trade-off is manual upkeep each semester (a few minutes editing a config file).
Local LLM/embeddings vs. a cloud API. Chosen for this prototype: everything runs on-device (Ollama for classification, sentence-transformers for embeddings). This keeps coursework content — which may include personal academic work — off third-party servers, and removes per-file API cost. The trade-off is weaker reasoning quality and slower inference than a frontier hosted model, which likely means a higher rate of low-confidence flags (i.e., more manual review) than a cloud-backed version would produce.
Append-only move log with explicit undo, rather than trusting moves to be correct. Given misclassification is a real risk, reversibility is treated as a first-class feature, not an afterthought — every move (auto or reviewed) is logged before it's trusted.
8. Tech Stack
Component	Tool
Watcher	watchdog (Python)
Extraction	python-docx, python-pptx, pdfplumber/pypdf, pytesseract + pdf2image (OCR fallback)
Classifier	Local LLM via Ollama (e.g. qwen2.5:7b-instruct or llama3.1:8b), JSON-mode structured output
Embeddings	sentence-transformers (all-MiniLM-L6-v2 or bge-small-en-v1.5), local, no API
Storage	SQLite (files + moves tables; embeddings stored as BLOBs)
CLI	Typer or argparse + rich for readable review/search output
Background execution	launchd (macOS) to keep the watcher alive across sessions
Everything here is a well-documented, single-machine, no-server dependency — chosen so the prototype is buildable solo within a semester without standing up external infrastructure.

9. Milestones / Timeline
Milestone	Deliverable	Maps to
M1 — Extraction working	Extractor functions run manually against a folder of sample files; text quality verified per filetype	Weeks 1–2
M2 — Classification working	Ollama call returns structured JSON against saved extracts; manually check accuracy against a small labeled set	Weeks 3–4
M3 — Action + undo	Rename/move logic, moves log, archivist undo; tested against synthetic duplicate/misclassification cases	Weeks 5–6
M4 — Watcher integration	Wrap M1–M3 in the watchdog loop; debounce, Ollama-down handling, self-move-ignoring	Week 7
M5 — Index + retrieval	Embedding at classify time; archivist find returns correct top-k on real queries	Weeks 8–9
M6 — Review queue polish	archivist review CLI flow finalized; confidence threshold tuned from observed behavior	Week 10
M7 — Evaluation + writeup	Run the evaluation plan below against a real backlog of past files; document results	Weeks 11–12
(Adjust week numbers to your actual semester calendar — structure is what matters: extraction → classification → action → watcher → index → review polish → evaluation.)

10. Evaluation
Classification accuracy. Assemble a held-out test set from your own past Downloads/Desktop files (ideally 50–100, spanning multiple courses and doc types) with hand-labeled correct course/type. Run the classifier and report accuracy, plus a confusion breakdown (which courses get confused with which — likely signal for course-list aliasing gaps).
Confidence calibration. For the same test set, check whether low-confidence flags actually correlate with wrong classifications, and whether high-confidence predictions are reliably correct. This validates (or tunes) the threshold from section 7.
Retrieval quality. Write a set of natural-language queries in the style you'd actually use ("find my TUI midterm slides," "the service design reading on prototyping") against the indexed test set, and check whether the correct file appears in the top-3 results.
End-to-end trust test. Let the watcher run live against real new downloads for a week or two; track how many auto-filed items needed a later undo versus how many review-queue items were correctly caught.
11. Risks / Open Questions
Misclassification risk. Even with confidence gating, a high-confidence wrong classification is possible (confident and wrong is worse than the model flagging uncertainty). The undo log mitigates but doesn't prevent this — worth tracking as a metric (section 10).
Local model reasoning quality. A local 7–8B model may be noticeably weaker than a frontier hosted model at the "which course does this ambiguous file belong to" judgment call, likely pushing more files into the review queue than a cloud-backed version would. Open question: is the review-queue volume tolerable in practice, or does it need a stronger local model / bigger hardware budget?
Watcher reliability. If the watcher process isn't running (laptop closed, app quit, crash), files land unclassified and won't be picked up retroactively unless a "catch-up scan on startup" is explicitly built — currently not scoped, worth deciding.
OCR fallback quality. Scanned/handout-photo PDFs may produce noisy OCR text, which degrades both classification and retrieval for that subset of files — no fallback plan yet if OCR text is too poor to be useful signal.
Course list drift. A hardcoded list needs manual updating each semester (new courses, dropped courses); if forgotten, new files default to lower confidence and pile into review rather than being silently misfiled — which is the safer failure mode, but still a maintenance cost.
Privacy, even local. Local-only avoids sending file content to a third-party API, but extracted text and embeddings still sit unencrypted in a local SQLite file — worth a one-line note on whether that matters for this use case (probably not, but stated explicitly rather than assumed).