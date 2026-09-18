Name: filename-nomenclature
Description: Generates a consistent filename for a downloaded file from its classification (ownership, category, document type), and resolves filename collisions against what's already in the destination folder. Does not detect true duplicates, that's a File Action responsibility, run earlier via a content hash.

Filename Nomenclature Skill

Input
ownership: "own" or "other" (from Classification)
category: course code or other category (from Classification)
doc_type: short document type (from Classification)
title_source: extracted text excerpt and/or original filename, to derive a clean title from
extension: original file extension, preserved as-is
person_name: the archive owner's name, from config — never inferred
existing_filenames: filenames already present in the destination folder, for collision checking

Step 1: Apply the matching naming pattern
If ownership == "own":

<PersonName>_<TitleInTheFile>_<YYYY-MM-DD>.<extension>
Example: Arunima_MidtermEssay_2026-03-14.docx

If ownership == "other":

<Category>_<Title>_<DocType>.<extension>
Example: DesignThinking_Lecture2_Slides.pptx

Rules
<WhatItIs> / <DocType>: short, plain description (Essay, Notes, Slides, Reading, Assignment, etc.)- pick the closest existing match from Classification's doc_type
<Title>: a short, clean version of the file's actual subject, derived from title_source
<Category> use whatever category actually fits (Personal, Club, Internship, Course etc.), as classified.
<PersonName> always comes from config, never inferred from the file itself.
Always preserve the original file extension.
Remove characters that are invalid or awkward in filenames (/ \ : * ? " < > |, leading/trailing whitespace).

Step 2: Resolve filename collisions
This is the only duplicate-related logic this skill owns. True duplicate detection (byte-identical re-download) happens earlier and elsewhere, see note below.

Generate the name from Step 1.
Check it against existing_filenames in the destination folder.
If there's no collision, return the name as-is.
If the generated name already exists (a different file, different content hash, that happens to classify to the same name), append -2, -3, etc. before the extension, incrementing until the name is unique:
Arunima_Resume.pdf
Arunima_Resume-2.pdf

