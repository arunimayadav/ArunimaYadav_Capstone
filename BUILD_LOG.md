# Build Log

**Running total (Assessments 1–3):** ~13 hrs · ~243k tokens

## 2026-09-11
- **Time spent:** ~1 hr
- **Tokens used:** ~3,000 (plan.md drafting via Claude in plan mode)
- **Shipped:** Capstone idea locked in, repo created, `project-setup` branch, plan.md committed with descriptive message

## 2026-09-17
- **Time spent:** ~3 hrs total (most of it went into figuring out API key formatting, MCP server setup, and .gitignore; the actual agent build (once things were connected) took Claude Code about 7 minutes)
- **Tokens used:** ~40k
- **Shipped:** Finalized and committed the filename-nomenclature Skill (filename-nomenclature.md) with the help of Claude. Set up .env for the Gemini API key and added .gitignore to keep it out of the repo. Connected a filesystem MCP server. Had Claude Code build the full agent (perceive → reason → act → observe) using the Skill for naming. First run failed: invalid API key turned out to be a stray space after the `=` in .env, plus the key needed header auth instead of a URL param, and the model name was deprecated so it got repointed to a current one. After fixing those, successfully ran the agent end-to-end on a real downloaded file- read it, classified it via Gemini, renamed it per the Skill's rules, and moved it into the correct Archive subfolder via the MCP server. Then worked on renaming a newly downloaded file.

## 2026-09-18
- **Time spent:** ~4 hrs (plan revisions, scaffolding the new Swift app, then losing time to a self-inflicted git incident)
- **Tokens used:** ~90k
- **Shipped:** Pivoted the plan away from the Python/CLI agent toward a native macOS Swift menu bar app, and rewrote plan.md around graph memory, an always-on FSEvents watcher, and a backfill scan for files that predate the app. Had Claude Code scaffold the initial macapp Swift package with Search, Organize, Review, and Settings tabs. Mid-session, a commit meant to capture the redesign (`Redesign for graph memory, automatic watcher, and backfill scan`) accidentally swept in a `.venv` and a `.env` file containing a live API key. Caught it, added a proper `.gitignore` to stop it recurring, and had to delete and recover a branch to get the key out of tracked history — lost a chunk of the session to cleanup rather than feature work, and some of the just-built macapp scaffolding had to be reconstructed afterward since it hadn't been safely committed yet.

## 2026-09-19
- **Time spent:** ~5 hrs (steady stream of small fixes from early afternoon into the evening)
- **Tokens used:** ~110k
- **Shipped:** Fixed a startup crash in FileWatcher.swift — the FSEvents callback was treating `eventPaths` as a raw C array of pointers when `kFSEventStreamCreateFlagUseCFTypes` actually hands back a CFArray, so indexing into it read garbage memory and crashed almost immediately; switched to `CFArrayGetValueAtIndex`. Also fixed the watcher picking up every pre-existing file in Downloads on launch instead of only genuinely new files after start. Added the tagging Skill (skills/tagging.md) and wired it into the processing pipeline alongside filename-nomenclature, then spent several commits (`Fixing rename and tagging not executing after file detection`, `naming fix`, `renaming issue fixing`, `Fixing tagging execution`) chasing renames and tags not firing after file detection, incorrect filenames, and inconsistent tags being applied across similar files — root-caused to gaps in GraphStore, Pipeline, TagWriter, and OllamaProvider not passing existing tags/context through consistently. Wired Search to check filename, content, category, and tags together instead of filename-only matching. Set up Ollama locally as the default free/local AI provider (with cloud providers as opt-in overrides in Settings). Wrote the project README covering setup, requirements, and how the AI provider fallback works. Opened and merged the assessment-2 branch into main via PR #2.

