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


def _flow_fields(text: str) -> dict[str, str] | None:
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    in_quote: str | None = None
    chunks: list[str] = []
    current: list[str] = []
    escaped = False
    closed = False

    for ch in text[start:]:
        if in_quote == '"':
            if escaped:
                current.append(ch)
                escaped = False
            elif ch == "\\":
                current.append(ch)
                escaped = True
            elif ch == '"':
                current.append(ch)
                in_quote = None
            else:
                current.append(ch)
        elif in_quote == "'":
            current.append(ch)
            if ch == "'":
                in_quote = None
        else:
            if ch == '"':
                in_quote = '"'
                current.append(ch)
            elif ch == "'":
                in_quote = "'"
                current.append(ch)
            elif ch in "{[":
                depth += 1
                if depth > 1:
                    current.append(ch)
            elif ch in "}]":
                depth -= 1
                if depth == 0:
                    closed = True
                    chunk = "".join(current).strip()
                    if chunk:
                        chunks.append(chunk)
                    break
                elif depth > 0:
                    current.append(ch)
                else:
                    return None
            elif ch == "," and depth == 1:
                chunk = "".join(current).strip()
                if chunk:
                    chunks.append(chunk)
                current = []
            else:
                current.append(ch)

    if not closed or in_quote is not None:
        return None

    fields: dict[str, str] = {}
    for chunk in chunks:
        if ":" not in chunk:
            return None
        k, v = chunk.split(":", 1)
        k = k.strip().strip("'\"")
        if not k:
            return None
        fields[k] = v.strip()
    return fields


def _block_has_intent(item: str) -> bool:
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
    return has_intent


def _evidence_items(section: str) -> list[tuple[str, str]] | None:
    lines = [line for line in section.splitlines() if line.strip()]
    dash_indents: list[int] = []
    for line in lines:
        m = re.match(r"^(\s*)-\s", line)
        if m:
            dash_indents.append(len(m.group(1).expandtabs(8)))
    if not dash_indents:
        return None
    item_indent = min(dash_indents)
    items_raw: list[list[str]] = []
    current_item: list[str] = []
    for line in lines:
        m = re.match(r"^(\s*)-\s", line)
        if m and len(m.group(1).expandtabs(8)) == item_indent:
            if current_item:
                items_raw.append(current_item)
            current_item = [line]
        elif current_item:
            current_item.append(line)
    if current_item:
        items_raw.append(current_item)
    if not items_raw:
        return None

    result: list[tuple[str, str]] = []
    for index, item_lines in enumerate(items_raw, 1):
        first_token_char = ""
        for line in item_lines:
            stripped = re.sub(r"^\s*-\s*", "", line).strip() if line == item_lines[0] else line.strip()
            if stripped:
                first_token_char = stripped[0]
                break

        stripped_first = re.sub(r"^\s*-\s*", "", item_lines[0]).strip()
        m_keyed = re.match(r"^([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*)$", stripped_first)
        is_keyed_flow = False
        if m_keyed:
            rest = m_keyed.group(2).strip()
            if rest.startswith("{"):
                is_keyed_flow = True
            elif not rest:
                for line in item_lines[1:]:
                    if line.strip():
                        if line.strip().startswith("{"):
                            is_keyed_flow = True
                        break

        if is_keyed_flow and m_keyed:
            item_id = m_keyed.group(1)
            joined = "\n".join(item_lines)
            fields = _flow_fields(joined)
            if fields is None:
                result.append((item_id, "unreadable"))
            else:
                if "intent" in fields:
                    val = fields["intent"].strip("'\"\t ")
                    if val and val not in {"null", "~"}:
                        result.append((item_id, "intent"))
                    else:
                        result.append((item_id, "missing"))
                else:
                    result.append((item_id, "missing"))
        elif first_token_char == "{":
            joined = "\n".join(item_lines)
            fields = _flow_fields(joined)
            if fields is None:
                m_id = re.search(r"[{,\s]id\s*:\s*([^,\s}]+)", joined)
                item_id = m_id.group(1).strip("'\"\t ") if m_id else str(index)
                result.append((item_id, "unreadable"))
            else:
                item_id = fields.get("id", "").strip("'\"\t ") or str(index)
                if "intent" in fields:
                    val = fields["intent"].strip("'\"\t ")
                    if val and val not in {"null", "~"}:
                        result.append((item_id, "intent"))
                    else:
                        result.append((item_id, "missing"))
                else:
                    result.append((item_id, "missing"))
        else:
            first_line = re.sub(r"^(\s*)-[ \t]?", r"\1  ", item_lines[0], count=1)
            item_text = "\n".join([first_line] + item_lines[1:])
            is_mapping = bool(re.search(r"(?m)^[ \t]*[A-Za-z_][A-Za-z0-9_]*\s*:", item_text))
            m_id = re.search(r"(?m)^[ \t]*id\s*:\s*(.*)$", item_text)
            item_id = m_id.group(1).splitlines()[0].strip().strip("'\"\t ") if m_id else str(index)
            if not is_mapping:
                result.append((item_id, "unreadable"))
            else:
                if _block_has_intent(item_text):
                    result.append((item_id, "intent"))
                else:
                    result.append((item_id, "missing"))

    return result


def _first_commit_date(path: Path) -> dt.date | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(path.parent), "log", "--format=%cs", "--", path.name],
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
        items = _evidence_items(evidence.group(1))
        if items is None:
            gaps.append("evidence section has no list items the checker can read")
        for item_id, state in items or []:
            if state == "unreadable":
                gaps.append(f"evidence item {item_id} is not a mapping the checker can read")
            elif state != "intent":
                gaps.append(f"evidence item {item_id} is missing intent")
    if re.search(
        r"(?m)^\*\*Intent approved:\*\*.*\d{4}-\d{2}-\d{2}.+$", text
    ) and not re.search(
        r"(?m)^\*\*Intent approved:\*\*\s*[^,\n]+,\s*\d{4}-\d{2}-\d{2}\s*$", text
    ):
        gaps.append(
            "**Intent approved:** line must end at the date (operator, YYYY-MM-DD); put any note on another line"
        )
    elif not re.search(
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
