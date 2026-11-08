#!/usr/bin/env python3
"""Validate operator intent approval for recently filed dispatch specs."""

from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
import sys
from pathlib import Path

# The intent rule was cut on 2026-11-07; 2026-11-08 is its first day in force.
INTENT_RULE_DATE = dt.date(2026, 11, 8)


def _first_commit_date(path: Path) -> dt.date | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(path.parent), "log", "--follow", "--format=%cs", "--", path.name],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    dates = result.stdout.splitlines()
    try:
        return dt.date.fromisoformat(dates[-1]) if dates else None
    except ValueError:
        return None


def check(path: str | Path, *, first_commit_date: dt.date | None = None) -> list[str]:
    """Return missing approval gaps, or an empty list when dispatch is allowed."""
    spec_path = Path(path)
    text = spec_path.read_text(encoding="utf-8")
    filed = re.search(r"(?m)^\*\*Filed:\*\*\s*(\d{4}-\d{2}-\d{2})", text)
    filed_date = dt.date.fromisoformat(filed.group(1)) if filed else None
    date = filed_date or first_commit_date or _first_commit_date(spec_path)
    if date is None or date < INTENT_RULE_DATE:
        return []
    gaps: list[str] = []
    acceptance = re.search(r"(?ms)^## Acceptance\s*\n```ya?ml\s*\n(.*?)^```", text)
    body = acceptance.group(1) if acceptance else ""
    evidence = re.search(
        r"(?ms)^evidence:\s*\n(.*?)(?=^[A-Za-z_][A-Za-z0-9_]*:|\Z)", body
    )
    if evidence:
        items = re.split(r"(?m)^\s*-\s+id\s*:\s*", evidence.group(1))
        for index, item in enumerate(items[1:], 1):
            item_id = item.splitlines()[0].strip() or str(index)
            intent = re.search(r"(?m)^([ \t]+)intent[ \t]*:[ \t]*(.*)$", item)
            has_intent = False
            if intent:
                indent = len(intent.group(1).expandtabs(8))
                value = intent.group(2).strip()
                if value in {">", ">-", ">+", "|", "|-", "|+"}:
                    for line in item[intent.end() :].splitlines():
                        if not line.strip():
                            continue
                        line_indent = len(line) - len(line.lstrip(" \t"))
                        if line_indent <= indent and re.match(r"\s*[A-Za-z_][A-Za-z0-9_]*\s*:", line):
                            break
                        if line_indent > indent:
                            has_intent = True
                            break
                else:
                    has_intent = value not in {"", "''", '""'}
            if not has_intent:
                gaps.append(f"evidence item {item_id} is missing intent")
    if not re.search(
        r"(?m)^\*\*Intent approved:\*\*\s*[^,\n]+,\s*\d{4}-\d{2}-\d{2}\s*$", text
    ):
        gaps.append("missing **Intent approved:** header")
    return gaps


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("spec")
    args = parser.parse_args()
    try:
        gaps = check(args.spec)
    except (OSError, ValueError) as exc:
        print(f"spec-intent: cannot read spec: {exc}", file=sys.stderr)
        return 2
    if gaps:
        for gap in gaps:
            print(f"spec-intent: {args.spec}: {gap}", file=sys.stderr)
        return 1
    print(f"spec-intent: OK: {args.spec}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
