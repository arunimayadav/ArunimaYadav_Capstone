Name: tagging
Description: Assigns a tag to a file from its extracted content. Reuses an existing tag whenever one reasonably fits, and only mints a new tag when nothing in the existing vocabulary matches. Keeps the tag vocabulary small, short, and non-overlapping over time, this is the sole guard against tag sprawl in the graph's emergent tags table.

Tagging Skill

Input
content_excerpt: extracted text/content from the file, to judge subject matter from
existing_tags: the full list of tag names already in the graph's tags table
category: category from Classification, if available, useful context but not a substitute for a tag
title_source: extracted text excerpt and/or original filename, for extra context when content_excerpt is thin

Step 1: Try to reuse an existing tag
Read existing_tags first, before considering any new tag.
Ask: does the file's actual subject matter reasonably fit one of these already?
"Reasonably fits" means the tag would still make sense applied to other files on the same general subject, not only this one file.
If a tag fits, use it. Prefer reuse over precision, a slightly-broader existing tag beats a slightly-more-accurate new one.
If more than one existing tag could fit, choose the one that's already the closest semantic match rather than adding a second, overlapping tag.

Step 2: Only create a new tag if nothing existing matches
A new tag is justified only when the file's subject is genuinely not covered by anything in existing_tags, not merely under-specified by it.
New tag names follow the same shape as good existing tags: short (1-3 words), broad enough to apply to a class of files, not to one file (Finance, not Q3-Bank-Statement; Lecture Notes, not DesignThinking-Week2-Notes).
Do not create a new tag that's just a narrower version of one that already exists (e.g. don't add "Bank Statements" if "Finance" exists and would fit).
Category names and tag names are allowed to overlap in spirit but serve different jobs, category is structural (where a file belongs), tag is topical (what it's about), don't default to copying category as the tag.

Rules
Tags are short, plain, and reusable, title case, no punctuation beyond spaces (Finance, Lecture Notes, Receipts, Club).
Never emit a tag that's a one-off, hyper-specific label built from this file's own title or date.
When in doubt between reusing a close-but-imperfect existing tag and minting a precise new one, reuse. Vocabulary size is the thing being protected here.
A file can reasonably take more than one tag if it genuinely spans two subjects (e.g. an invoice from a club could be both Finance and Club), but don't stack tags just to hedge, if one tag captures it, use one.
