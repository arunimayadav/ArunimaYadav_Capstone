"""Coursework Archivist agent — perceive / reason / act / observe loop for one file.

Usage:
    python -m agent.run_agent <path-to-file> [--existing NAME ...]

Perceive and Reason run fully in this process. Act computes the file's new
name (via the filename-nomenclature skill logic) and leaves it in its current
directory — files are renamed in place, never moved. The actual rename is
left to the caller: this script writes its plan to agent/last_plan.json and
the orchestrating Claude Code agent performs the rename through the
filesystem MCP server, then reports the final observe line itself.

This script also appends a record of the rename (new name + original text
excerpt) to the log file at config.LOG_PATH, so files can be found later by
describing their content.
"""

import argparse
import json
import os
import sys

from dotenv import load_dotenv

from agent import act, config, log, observe, perceive, reason

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(file_path: str, existing_filenames: list) -> dict:
    load_dotenv(os.path.join(PROJECT_ROOT, ".env"))
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY not set in .env")

    perceived = perceive.perceive(file_path)
    classification = reason.classify(
        perceived,
        api_key=api_key,
        person_name=config.PERSON_NAME,
        course_list=config.COURSE_LIST,
        model=config.GEMINI_MODEL,
    )
    plan = act.plan_action(
        perceived,
        classification,
        person_name=config.PERSON_NAME,
        existing_filenames=existing_filenames,
    )

    log_path = os.path.join(PROJECT_ROOT, config.LOG_PATH)
    log.append_entry(perceived, classification, plan, log_path)

    observe.report(perceived, classification, plan, log_path=log_path)

    result = {"perceived": perceived, "classification": classification, "plan": plan}
    with open(os.path.join(os.path.dirname(__file__), "last_plan.json"), "w") as f:
        json.dump(result, f, indent=2)

    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("file_path")
    parser.add_argument(
        "--existing",
        nargs="*",
        default=[],
        help="filenames already present in the file's current directory, for collision checking",
    )
    args = parser.parse_args()

    try:
        run(args.file_path, args.existing)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
