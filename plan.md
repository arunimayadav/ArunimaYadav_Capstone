# Archivist — a menu bar file memory for macOS

> **Revision note:** This plan was originally scoped as a coursework-only CLI tool (Python + watchdog + local Ollama, filing against a fixed course list). It has been revised to a general-purpose macOS menu bar app after deciding the more useful MVP is: watch Downloads, understand *any* file with AI, make it instantly searchable via a content graph, and let natural-language commands reorganize files — while still supporting a fully local/private AI path alongside optional cloud providers. Sections below describe the current, revised design. The original coursework-specific framing (fixed course list, `filed`/`flat` modes as the only action, CLI-only UI) has been superseded but the underlying judgment-call/agent argument, graph-memory idea, and safety posture (confidence gating, undo log) carry over directly.

## 1. Problem Statement

Files accumulate in Downloads faster than any manual filing habit survives — invoices, receipts, contracts, slides, installers, and one-off PDFs all land with generic, uninformative filenames (`Untitled.pdf`, `download (3).docx`, `Statement_Final.pdf`). Each file *could* be filed and labeled correctly the moment it arrives, but doing that requires interrupting whatever you're doing to open it, figure out what it's about, rename it, tag it, and maybe move it — a small tax that's easy to defer and, once deferred, never comes back to. Nothing downstream (Spotlight, folder browsing, your own memory of "that PDF from three weeks ago") works well when the upstream understanding never happened. The gap isn't that filing is hard — it's that it's manual and silent, so it doesn't happen consistently, and search has nothing but a filename to go on.

## 2. Goal / Scope

**In scope (MVP):**
- A native macOS **menu bar app** (SwiftUI/AppKit, `NSStatusItem`) — no Dock icon, always available from the top toolbar. This is the primary interface; there is no separate CLI in this revision.
- **Watches Downloads** (Desktop as a secondary source) via FSEvents. New files are read, understood, and indexed automatically, without the user invoking anything.
- Handles **.pdf, .docx, .pptx, .txt/.md**, with an OCR/vision fallback path flagged as a stretch goal for scanned/image-based PDFs.
- **AI understanding is provider-agnostic and dual-mode:** every AI call (classification, summarization, tagging, embeddings, natural-language command parsing) goes through a single `AIProvider` protocol. The user configures, from the app's **Settings menu**, either or both:
  - **Local**: Ollama running on-device (default/fallback — no key required, no data leaves the machine).
  - **Cloud**: an API key for **Groq, OpenAI, Anthropic, or Gemini**, entered once in Settings and stored in the macOS Keychain (never written to disk in plaintext).
  - If a cloud key is configured it's preferred for quality; if not (or if the call fails), the app falls back to local Ollama. This is a per-user setting, not hardcoded.
- **Graph-based memory, not flat search.** Every indexed file becomes a node (path, summary, category, tags, embedding). Shared tags, shared category, and content similarity become edges. Search returns the best match **and** what it's connected to.
- **Search from the menu bar.** A global search field (menu bar dropdown or a hotkey-summoned panel) queries the graph and returns ranked results with summaries, not just filenames.
- **Natural-language file commands.** The user can type something like *"create a folder for anything related to my bank and put those files in it"* — the app resolves this against the graph (which files match "bank" by tag/summary/category), proposes the action, and on confirmation creates the folder and moves the matching files, logging every move for undo.
- **macOS-native tagging.** In addition to the app's own graph tags, the app writes the same categorical tags onto files using **macOS's built-in Finder tags** (`URLResourceValues.tagNames`), so files stay tagged and colored in Finder/Spotlight even outside the app.
- **Confidence-gated automatic action.** High-confidence file understanding is indexed (and tagged) immediately; low-confidence results land in a review list inside the app rather than being silently guessed at.
- One user, one Mac. No sync, no collaboration, no multi-device story.

**Explicitly cut (not this iteration):**
- No mobile ingestion, no email attachment monitoring.
- No web dashboard — this is the menu bar app only (no CLI, superseding the original plan's CLI-only decision).
- No dedicated graph database — same rationale as the original plan: `nodes`/`edges`/`tags` tables inside one local SQLite file, no separate storage engine.
- No automatic bulk reorganization of pre-existing Downloads backlog on first launch — an explicit "index my existing Downloads" action exists, but (as in the original plan) it indexes without moving files until the user asks for a move.
- No packaging/notarization/App Store distribution polish in the MVP — runs as a locally-built app for the author's own Mac.

## 3. AI-Involvement Level

Same as originally stated: Claude-driven implementation, human-directed. I write the problem statement and review/approve the plan before execution; Claude does the implementation inside the plan → execute loop. This revision changes *what* is being built, not that process.

## 4. Why This Needs an Agent

"What is this file about, and what should it be called/tagged?" is a judgment call, not a lookup — a filename alone rarely says. This needs an LLM to read an excerpt and reason about content, exactly as the original plan argued. Two things are new in this revision:

- **The judgment call now spans multiple possible AI backends.** The agent doesn't just classify — it has to decide *which provider* to call (local vs. whichever cloud key is configured), handle a down/misconfigured provider gracefully, and keep behaving consistently either way.
- **The action space is now open-ended, not just "file vs. don't."** A natural-language command like "gather my bank files" requires the agent to interpret intent, query its own memory (the graph) for matches, and propose a filesystem action — a step beyond the original plan's fixed classify→file pipeline.

It still has to be an always-on watcher, not an on-demand command, for the same reason as before: a tool you have to remember to run reproduces the exact behavioral gap that causes the mess in section 1.

## 5. User Flow

**Flow A — a new file, automatically, via the watcher:**
1. **File lands** in Downloads (or Desktop). The FSEvents watcher notices, debounces until the write finishes.
2. **Dedup check** — content hash (SHA-256) against the index. A byte-identical re-download is skipped and logged.
3. **Extraction** — filename, file type, and a text excerpt (PDFKit for PDFs, unzipped-XML text pull for `.docx`/`.pptx`, plain read for text files).
4. **Understanding call** — the excerpt goes to the active `AIProvider` (cloud key if configured, else local Ollama) for classification (category), summarization (what it's about), and tag suggestion (reuse an existing tag or mint a new one).
5. **Embedding** — the same provider (or Ollama's local embedding model as fallback, since Groq/Anthropic don't expose embeddings) produces a vector for the file's content.
6. **Graph write** — a node is created/enriched (path, category, tags, summary, confidence, embedding, timestamps); Relationship Builder compares it against existing nodes and writes `same_tag` / `same_category` / `similar_content` edges.
7. **macOS tagging** — the resolved category/tags are also written as native Finder tags on the file via `URLResourceValues`.
8. **Branch on confidence:** high confidence → indexed and tagged silently; low confidence → added to an in-app review list, file untouched otherwise.
9. **Later, retrieval.** The user opens the menu bar search, types something like "the bank statement from spring," and gets the best-matching node plus files connected to it in the graph (e.g. the statement plus a related receipt tagged the same way).
10. **Later, a command.** The user types "put all my bank stuff in one folder." The app resolves matching nodes from the graph, shows a confirmation with the file list and destination folder name, and on approval creates the folder, moves the files, updates each node's path, and appends to the move log.
11. **Undo.** Any move (auto-tag doesn't count, only actual file moves) can be reversed from the move log.

**No backfill.** An explicit product decision, not an oversight: only files downloaded *after* the watcher starts get indexed, renamed, and tagged. Files already sitting in Downloads before the app was ever run are deliberately left alone and stay unsearchable unless re-downloaded. A "Flow B" bulk backfill was prototyped (index-only, never rename, matching the original plan's caution around bulk hard-to-reverse actions) but was explicitly rejected — indexing a large pre-existing Downloads folder against local Ollama would take hours, and more importantly the owner wants search scoped to what the watcher has actually seen, not their entire download history. If this changes later, re-introduce it as a separate, explicitly-triggered action rather than folding it into the always-on pipeline.

## 6. System Architecture

```
                    ┌─────────────────────────┐
                    │   Menu Bar App (Swift)   │  NSStatusItem — always running
                    │  Search · Settings · Review · Commands
                    └────────────┬─────────────┘
                                  │
            ┌─────────────────────┼─────────────────────┐
            ▼                     ▼                       ▼
   ┌────────────────┐   ┌──────────────────┐   ┌─────────────────────┐
   │  FileWatcher    │   │ CommandInterpreter│   │   SettingsStore      │
   │  (FSEvents on   │   │ (NL → graph query │   │ (Keychain: provider   │
   │  Downloads/     │   │  → proposed move) │   │  + API keys per       │
   │  Desktop)       │   │                    │   │  provider)            │
   └───────┬─────────┘   └─────────┬──────────┘   └──────────┬───────────┘
           ▼                        │                          │
   ┌────────────────┐               │                          │
   │  Dedup gate     │              │                          │
   │  (content hash) │              │                          │
   └───────┬─────────┘              │                          │
           ▼                        │                          │
   ┌────────────────┐               │                          │
   │  Extractor      │              │                          │
   │ (PDFKit / XML   │              │                          │
   │  unzip / text)  │              │                          │
   └───────┬─────────┘              │                          │
           ▼                        ▼                          ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │                        AIProvider (protocol)                     │
   │   classify() · summarize() · tag() · embed() · interpretCommand() │
   │   ┌───────────┐  ┌───────────┐  ┌────────────┐  ┌──────────────┐  │
   │   │  Ollama   │  │  OpenAI   │  │ Anthropic  │  │ Groq / Gemini │  │
   │   │ (local,   │  │ (cloud,   │  │ (cloud,    │  │ (cloud,       │  │
   │   │ default)  │  │  keyed)   │  │  keyed)    │  │  keyed)       │  │
   │   └───────────┘  └───────────┘  └────────────┘  └──────────────┘  │
   └───────────────────────────────┬───────────────────────────────────┘
                                    ▼
                          ┌───────────────────┐
                          │ Relationship       │  same_tag / same_category /
                          │ Builder             │  similar_content edges
                          └─────────┬───────────┘
                                    ▼
                          ┌───────────────────┐
                          │ GraphStore (SQLite) │  nodes · tags · node_tags ·
                          │                      │  edges · moves
                          └─────────┬───────────┘
                                    ▼
                    ┌───────────────────────────────┐
                    │ Finder Tag Writer               │  URLResourceValues.tagNames
                    └───────────────────────────────┘

confidence ≥ threshold?  → indexed + tagged silently
confidence < threshold?  → in-app review list (untouched on disk)
```

- **Menu Bar App** — the shell: status item, dropdown menu, a Search panel, a Settings window, a Review list, and the natural-language command box. Built in SwiftUI hosted from an `NSStatusItem`/`NSPopover`, no Dock icon (`.accessory` activation policy).
- **FileWatcher** — FSEvents-based (`FSEventStreamCreate` or `DispatchSource` polling as a simpler first cut), debounced, ignores its own move destinations to avoid loops.
- **Dedup gate** — SHA-256 content hash checked before any AI call.
- **Extractor** — per-filetype text pull: PDFKit for `.pdf`; unzip + strip XML for `.docx`/`.pptx` (Office files are zips of XML — no external library needed); plain read for text formats. OCR/vision fallback for scanned PDFs is a flagged stretch goal, not MVP.
- **AIProvider** — a single Swift protocol (`classify`, `summarize`, `tag`, `embed`, `interpretCommand`) with one concrete implementation per backend (Ollama over local HTTP; OpenAI, Anthropic, Groq, Gemini over their REST APIs). A `ProviderRouter` picks cloud-if-configured-else-Ollama and handles fallback on error. This is the direct successor to the original plan's single hardcoded "Ollama-only" Classifier/Summarizer/Tagger — same responsibilities, now backend-agnostic.
- **Relationship Builder** — unchanged in spirit from the original plan: turns shared tags/category/embedding similarity into graph edges.
- **GraphStore** — SQLite (via the system `libsqlite3`, no external dependency), same `nodes`/`edges`/`tags` design as the original plan, with `node_tags` join and an added `moves` log — see Data Model.
- **Finder Tag Writer** — new in this revision: mirrors the app's own category/tags onto the file as native macOS Finder tags, so the organization is visible and useful outside the app (Finder sidebar, Spotlight, tag-colored icons).
- **CommandInterpreter** — new in this revision: takes a free-text instruction, asks the AIProvider to extract intent (destination folder name + a graph query describing what belongs in it), executes the graph query against GraphStore, and returns a proposed action for the user to confirm before anything moves.

## 7. Data Model (SQLite, one local file)

**`nodes`** — one row per indexed file:
| field | notes |
|---|---|
| `id` | primary key |
| `path` | current location on disk |
| `filename` | original name, kept even if Finder tags/summary change |
| `category` | AI-assigned category/bucket |
| `summary` | plain-language description of what the file is about |
| `tags` | via `node_tags` join to `tags` |
| `confidence` | 0–1 score from the classification call |
| `status` | `indexed`, `pending_review`, `duplicate_skipped` |
| `provider_used` | which `AIProvider` backend produced this record (for debugging/eval) |
| `extracted_text` | truncated excerpt used for all AI calls |
| `embedding` | BLOB vector |
| `content_hash` | SHA-256, the dedup key |
| `created_at` / `updated_at` | timestamps |

**`tags`** — emergent vocabulary, `id`, `name`, `created_at` (unchanged from the original plan).

**`node_tags`** — many-to-many join (unchanged).

**`edges`** — `id`, `source_node_id`, `target_node_id`, `edge_type` (`same_tag`/`same_category`/`similar_content`), `weight`, `created_at`; unique on `(source_node_id, target_node_id, edge_type)` (unchanged from the original plan).

**`moves`** — append-only log, one row per action actually taken: `id`, `node_id`, `src_path`, `dst_path`, `ts`, `triggered_by` (`command` replaces the old `auto`/`reviewed` values, since all moves in this revision originate from either the review list or a natural-language command), `reversed`.

**Edge cases carried over from the original plan, still relevant:** duplicate filename at destination (suffix, never overwrite); undo must restore both file location and node status; a file modified after indexing is a known detection gap; a rejected review item shouldn't resurface every relaunch.

**New edge case this revision introduces:** a natural-language command's graph query may under- or over-match (e.g. "bank" matching an unrelated file that happens to mention a river bank) — the proposed-action confirmation step exists specifically to catch this before any move happens, not after.

## 8. Key Design Decisions & Trade-offs

- **Native Swift/SwiftUI menu bar app instead of a CLI.** The original plan's CLI-only decision assumed the primary "customer" was a terminal-comfortable student running commands. This revision's use case (background understanding + natural-language commands + always-visible search) is better served by something that lives in the toolbar and is one click away — the trade-off is a much larger, platform-specific build (Swift, AppKit/SwiftUI, Keychain, FSEvents) versus a portable Python script.
- **Dual AI backend (local Ollama + optional cloud key) instead of local-only.** The original plan chose local-only for privacy and zero API cost, at the price of weaker reasoning from a 7–8B model. This revision keeps local as the private, no-setup default but lets the user opt into a stronger hosted model with their own key when they want better classification/summarization quality — same privacy option, now a choice instead of the only path. The cost is a provider-abstraction layer and per-provider quirks (e.g. Groq/Anthropic have no embeddings endpoint, so embedding calls fall back to Ollama even when a cloud key is set for text generation).
- **API keys in Keychain, entered once in Settings.** Never written to disk in plaintext, never logged. This is a hard requirement, not a nice-to-have, given the app is asking for third-party credentials.
- **Confidence-gated indexing, not confidence-gated moving.** The original plan gated *filing* (moving files) on confidence. This revision mostly doesn't move files automatically at all — indexing and tagging happen at any confidence level that clears a low bar, but only get flagged for review if genuinely uncertain, because the riskiest action (moving/renaming) now only ever happens through an explicit reviewed or commanded action, never silently. This is a stricter safety posture than the original plan, not a looser one.
- **Natural-language commands always propose before they act.** Given the action space is now open-ended (any command, not just "file into course X"), a wrong graph match moving the wrong files is a bigger risk than a wrong auto-file was in the original design. Requiring an explicit confirmation step trades a little convenience for keeping the same "fail safe" posture the original plan established with confidence-gating.
- **Finder tags as a second, native tagging layer.** The graph's own `tags` table remains the source of truth for search/relationships (it's structured and queryable); Finder tags are a projection of that onto the OS so the work is visible outside the app too. Keeping the graph as ground truth avoids the alternative (Finder tags as ground truth) which would mean parsing tag state back out of the filesystem on every launch.
- **Graph memory instead of flat RAG — unchanged from the original plan** and for the same reason: edges let retrieval return a relevant cluster, not just a single closest match.
- **No dedicated graph database — unchanged from the original plan.** Still small enough that SQLite `nodes`/`edges` tables suffice.

## 9. Tech Stack

| Component | Tool |
|---|---|
| App shell | Swift, SwiftUI + AppKit (`NSStatusItem`), Swift Package Manager (no Xcode project file required to build/run) |
| File watching | FSEvents (`FSEventStreamCreate`) |
| Extraction | `PDFKit` (PDF), zip+XML text pull for `.docx`/`.pptx` (Office Open XML is a zip archive — no external library), `String(contentsOf:)` for text/markdown |
| AI backends | Local: **Ollama** REST API (`http://localhost:11434`). Cloud (user-keyed): **Groq**, **OpenAI**, **Anthropic**, **Gemini** REST APIs via `URLSession` |
| Embeddings | Ollama local embedding model by default; OpenAI/Gemini embeddings endpoint if that provider is configured and Ollama isn't running (Groq and Anthropic don't expose embeddings, so they're never used for this step) |
| Credential storage | macOS Keychain Services (`Security` framework) |
| Storage / graph | SQLite via the system `libsqlite3` (linked directly, no third-party dependency) — `nodes`/`edges`/`tags`/`node_tags`/`moves` |
| Native tagging | `URLResourceValues.tagNames` (Finder tags) |
| UI | SwiftUI for Settings/Search/Review windows, `NSStatusItem`/`NSPopover` for the menu bar surface |

This keeps the dependency footprint minimal (system frameworks + SQLite, no third-party Swift packages required) — deliberately, so the MVP builds and runs without dependency-resolution/network access being a prerequisite.

## 10. Milestones

| Milestone | Deliverable |
|---|---|
| M1 — App shell | Menu bar item, Settings window (provider picker + Keychain-backed key entry), app runs with `.accessory` activation policy (no Dock icon) |
| M2 — GraphStore | SQLite schema (`nodes`/`tags`/`node_tags`/`edges`/`moves`), CRUD, basic keyword search |
| M3 — AIProvider | Protocol + Ollama implementation working end-to-end (classify/summarize/tag/embed against a sample file); one cloud provider added next |
| M4 — Extraction + Watcher | PDFKit/docx/pptx extraction; FSEvents watcher on Downloads with debounce + dedup gate, wired to M2/M3 |
| M5 — Relationship Builder + Search UI | Edges created on new nodes; Search panel returns best match + connected files |
| M6 — Finder tags + Review list | Category/tags mirrored as native Finder tags; low-confidence items surfaced in an in-app review list |
| M7 — Natural-language commands | CommandInterpreter: free-text → graph query → proposed folder/move action → confirm → execute → move log |
| M8 — Remaining cloud providers + eval | OpenAI/Anthropic/Groq/Gemini providers; run the evaluation plan below (no backfill — explicitly descoped, see section 5) |

## 11. Evaluation

- **Classification/summarization quality.** Hand-check a sample of indexed files against their AI-generated category/summary/tags for both a local (Ollama) and a cloud provider run of the same files — does the cloud path noticeably outperform local, and is local good enough to be the sane default?
- **Tag convergence.** Confirm the tag vocabulary reuses tags across similar files instead of sprawling into near-duplicates.
- **Retrieval quality.** Natural-language search queries in the style you'd actually use ("that bank statement from a few weeks back") — is the right file the top match, and are the connected files it returns actually related?
- **Command correctness.** For a natural-language reorganization command, confirm the proposed file list matches user intent *before* confirming, and that the executed move only touches what was shown and confirmed.
- **Provider fallback behavior.** Turn off Ollama / use an invalid cloud key and confirm the app degrades to review-queue behavior rather than crashing or silently mis-filing.

## 12. Risks / Open Questions

- **Provider inconsistency.** Different providers (and local vs. cloud) may disagree on category/tags for the same file — worth tracking whether this causes confusing tag sprawl when a user switches providers mid-use.
- **No packaging/notarization in MVP.** The app isn't signed/notarized or distributed as a `.app` bundle beyond a local build — acceptable for a capstone prototype running on the author's own Mac, called out explicitly rather than silently assumed away.
- **Natural-language command safety.** Free-text-driven file moves are the highest-risk feature in this revision precisely because the action space is open-ended; the propose-then-confirm step is the main mitigation and its effectiveness should be evaluated directly (section 11), not assumed.
- **OCR/scanned PDFs.** Flagged as a stretch goal, not built in the MVP — scanned files will extract poorly or not at all until this is added.
- **Keychain/API key handling.** Storing third-party API keys, even locally in Keychain, is a real trust surface — worth a one-line note (as the original plan did for local-only privacy) on what's guaranteed (Keychain-only, never logged, never leaves the machine except in the outbound API call itself) versus what isn't.
- **FSEvents vs. polling.** FSEvents is the right long-term approach but has more setup complexity than a polling loop; if M4 runs long, a debounced polling fallback is an acceptable interim de-risk, matching the original plan's preference for a working simple version over a stalled complex one.
