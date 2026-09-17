# Build Log

## 2026-09-11
- **Time spent:** ~1 hr
- **Tokens used:** ~3,000 (plan.md drafting via Claude in plan mode)
- **Shipped:** Capstone idea locked in, repo created, `project-setup` branch, plan.md committed with descriptive message

## 2026-09-17
- **Time spent:** ~3 hrs total (most of it went into figuring out API key formatting, MCP server setup, and .gitignore; the actual agent build (once things were connected) took Claude Code about 7 minutes)
- **Tokens used:** ~40k
- **Shipped:** Finalized and committed the filename-nomenclature Skill (filename-nomenclature.md) with the help of Claude. Set up .env for the Gemini API key and added .gitignore to keep it out of the repo. Connected a filesystem MCP server. Had Claude Code build the full agent (perceive → reason → act → observe) using the Skill for naming. First run failed: invalid API key turned out to be a stray space after the `=` in .env, plus the key needed header auth instead of a URL param, and the model name was deprecated so it got repointed to a current one. After fixing those, successfully ran the agent end-to-end on a real downloaded file- read it, classified it via Gemini, renamed it per the Skill's rules, and moved it into the correct Archive subfolder via the MCP server. Then worked on renaming a newly downloaded file.