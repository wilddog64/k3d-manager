"""Deterministic routing and formatting for bug-count questions."""
import json
import os
import re
import sys
from pathlib import Path
from typing import NamedTuple

from webhook import proc

_COUNT_RE = re.compile(r"\b(?:how many|count|number of|tally)\b", re.IGNORECASE)
_BUG_RE = re.compile(r"\bbugs?\b", re.IGNORECASE)
_RELEASE_RE = re.compile(r"\bv?(\d+\.\d+\.\d+)\b", re.IGNORECASE)
_PRIORITY_RE = re.compile(r"\b(P[0-3])\b", re.IGNORECASE)
_STATE_RE = re.compile(r"\b(open|outstanding|fixed|closed|resolved|verified)\b", re.IGNORECASE)


class CountQuery(NamedTuple):
    release: str
    priority: str | None
    state: str | None


def match(question):
    if not _COUNT_RE.search(question or "") or not _BUG_RE.search(question or ""):
        return None
    release_match = _RELEASE_RE.search(question)
    release = f"v{release_match.group(1)}" if release_match else "*"
    priority_match = _PRIORITY_RE.search(question)
    state_match = _STATE_RE.search(question)
    state = None
    if state_match:
        state = "open" if state_match.group(1).lower() in ("open", "outstanding") else "closed"
    return CountQuery(release, priority_match.group(1).upper() if priority_match else None, state)


def reply(query):
    ref = os.environ.get("K3DM_INDEX_REF", "HEAD")
    cmd = [sys.executable, str(Path(__file__).resolve().parents[2] / "bug-tally.py"), "--json", "--ref", ref]
    rc, output, timed_out = proc._spawn_capture_text(cmd, cwd=Path(__file__).resolve().parents[2].parent,
                                                      timeout=30)
    if timed_out:
        return "Could not count bugs — tally failed (timeout)."
    if rc != 0:
        return f"Could not count bugs — tally failed ({rc})."
    try:
        payload = json.loads(output)
    except (TypeError, ValueError, json.JSONDecodeError):
        return "Could not count bugs — tally failed (invalid output)."
    releases = payload.get("releases", {})
    selected = releases if query.release == "*" else {query.release: releases.get(query.release)}
    selected = {name: value for name, value in selected.items() if value is not None}
    if not selected:
        return f"No bug tally found for {query.release}."
    lines = []
    for release, data in selected.items():
        counts = data
        if query.priority:
            counts = data.get("by_priority", {}).get(query.priority, {})
        lead = counts.get(query.state, 0) if query.state else counts.get("total", 0)
        noun = f" {query.priority}" if query.priority else ""
        state_lead = f" {query.state}" if query.state else ""
        lines.append(f"{release}: {lead}{state_lead}{noun} bug docs — {counts.get('closed', 0)} fixed, "
                     f"{counts.get('open', 0)} open, {counts.get('unknown', 0)} with no Status line.")
        if query.priority and data.get("by_priority", {}).get("unset", {}).get("total", 0):
            lines.append(f"{data['by_priority']['unset']['total']} docs in {release} have no Priority line, so they are not counted here.")
        open_items = data.get("open_paths", []) if query.priority else counts.get("open_paths", [])
        unknown_items = data.get("unknown_paths", []) if query.priority else counts.get("unknown_paths", [])
        if query.priority:
            open_items = [item for item in open_items if item.get("priority") == query.priority]
            unknown_items = [item for item in unknown_items if item.get("priority") == query.priority]
        for item in open_items[:10]:
            from webhook.ask_docs import _doc_link
            path = item["path"] if isinstance(item, dict) else item
            lines.append(f"Open: {_doc_link(path)}")
        for item in unknown_items[:10]:
            from webhook.ask_docs import _doc_link
            path = item["path"] if isinstance(item, dict) else item
            lines.append(f"Unknown: {_doc_link(path)}")
    lines.append(f"_Counted from docs/bugs/ at {ref}; release = Branch: line, else the release the doc was added in._")
    return "\n".join(lines)
