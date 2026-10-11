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
_NUMBERS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
            "nine": 9, "ten": 10}
_LAST_N_RE = re.compile(r"\b(?:last|past|previous|recent)\s+(\d+|" + "|".join(_NUMBERS) + r")\s+releases?\b",
                        re.IGNORECASE)
_CURRENT_RE = re.compile(r"\b(?:this|current|latest)\s+release\b", re.IGNORECASE)
_VERSION_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
_BRANCH_RE = re.compile(r"k3d-manager-(v\d+\.\d+\.\d+)$")
ALL_RELEASES_SHOWN = 10


class CountQuery(NamedTuple):
    release: str
    priority: str | None
    state: str | None


def match(question):
    if not _COUNT_RE.search(question or "") or not _BUG_RE.search(question or ""):
        return None
    release_match = _RELEASE_RE.search(question)
    last_match = _LAST_N_RE.search(question)
    if release_match:
        release = f"v{release_match.group(1)}"
    elif last_match:
        word = last_match.group(1).lower()
        release = f"last:{int(word) if word.isdigit() else _NUMBERS[word]}"
    elif _CURRENT_RE.search(question):
        release = "last:1"
    else:
        release = "*"
    priority_match = _PRIORITY_RE.search(question)
    state_match = _STATE_RE.search(question)
    state = None
    if state_match:
        state = "open" if state_match.group(1).lower() in ("open", "outstanding") else "closed"
    return CountQuery(release, priority_match.group(1).upper() if priority_match else None, state)


def _version(name):
    match = _VERSION_RE.match(name or "")
    return tuple(int(part) for part in match.groups()) if match else None


def _current_release(ref, root):
    if ref != "HEAD":
        branch = ref.removeprefix("origin/")
    else:
        rc, output, timed_out = proc._spawn_capture_text(["git", "branch", "--show-current"], cwd=root, timeout=10)
        branch = output.strip() if rc == 0 and not timed_out else ""
    match = _BRANCH_RE.search(branch)
    return match.group(1) if match else None


def _select(releases, release, ref, root):
    """Return (selected releases newest first, header line or None)."""
    ordered = sorted((name for name in releases if _version(name)), key=_version, reverse=True)
    ordered += sorted(name for name in releases if not _version(name))
    if release.startswith("last:"):
        count = max(1, int(release[5:]))
        current = _current_release(ref, root)
        versioned = [name for name in ordered if _version(name)]
        if current and _version(current):
            versioned = [name for name in versioned if _version(name) <= _version(current)]
            if current not in versioned:
                versioned.insert(0, current)
        chosen = versioned[:count]
        names = ", ".join(chosen) or "none"
        basis = f"current release {current} and the ones before it" if current else "newest releases in the tally"
        return [name for name in chosen if name in releases] or chosen, f"Last {count} release(s) ({basis}): {names}."
    if release == "*":
        return ordered, None
    return [release], None


def reply(query):
    ref = os.environ.get("K3DM_INDEX_REF", "HEAD")
    root = Path(__file__).resolve().parents[2].parent
    cmd = [sys.executable, str(Path(__file__).resolve().parents[2] / "bug-tally.py"), "--json", "--ref", ref]
    rc, output, timed_out = proc._spawn_capture_text(cmd, cwd=root, timeout=30)
    if timed_out:
        return "Could not count bugs — tally failed (timeout)."
    if rc != 0:
        return f"Could not count bugs — tally failed ({rc})."
    try:
        payload = json.loads(output)
    except (TypeError, ValueError, json.JSONDecodeError):
        return "Could not count bugs — tally failed (invalid output)."
    releases = payload.get("releases", {})
    names, header = _select(releases, query.release, ref, root)
    selected = {name: releases[name] for name in names if releases.get(name) is not None}
    if not selected:
        if header:
            return header + "\nNo bug docs in those releases."
        return f"No bug tally found for {query.release}."

    def counts_of(data):
        return data.get("by_priority", {}).get(query.priority, {}) if query.priority else data

    def lead_of(data):
        counts = counts_of(data)
        return counts.get(query.state, 0) if query.state else counts.get("total", 0)

    lines = [header] if header else []
    unset_total = sum(data.get("by_priority", {}).get("unset", {}).get("total", 0)
                      for data in selected.values()) if query.priority else 0
    if query.release == "*":
        noun = f" {query.priority}" if query.priority else ""
        state_lead = f" {query.state}" if query.state else ""
        total = sum(lead_of(data) for data in selected.values())
        lines.append(f"All releases: {total}{state_lead}{noun} bug docs.")
        nonzero = {name: data for name, data in selected.items() if lead_of(data)}
        omitted = len(nonzero) - ALL_RELEASES_SHOWN
        selected = dict(list(nonzero.items())[:ALL_RELEASES_SHOWN])
        if omitted > 0:
            lines.append(f"Showing the newest {ALL_RELEASES_SHOWN} releases with a match; {omitted} older ones omitted. "
                         "Name a release or ask for the last N releases.")
    for release, data in selected.items():
        counts = counts_of(data)
        lead = lead_of(data)
        noun = f" {query.priority}" if query.priority else ""
        state_lead = f" {query.state}" if query.state else ""
        lines.append(f"{release}: {lead}{state_lead}{noun} bug docs — {counts.get('closed', 0)} fixed, "
                     f"{counts.get('open', 0)} open, {counts.get('unknown', 0)} with no Status line.")
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
    if unset_total:
        lines.append(f"{unset_total} docs in these releases have no Priority line, so they are not counted here.")
    lines.append(f"_Counted from docs/bugs/ at {ref}; release = Branch: line, else the release the doc was added in._")
    return "\n".join(lines)
