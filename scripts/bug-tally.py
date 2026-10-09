#!/usr/bin/env python3
"""Count bug documents by release, state and priority without model inference."""
import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from hermes.prior_art import doc_meta, doc_release  # noqa: E402

TAG_RE = re.compile(r"^v(\d+\.\d+\.\d+)$")
BRANCH_RE = re.compile(r"k3d-manager-v(\d+\.\d+\.\d+)")


def _git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True,
                          check=True).stdout


def _added_releases(ref, branch):
    output = _git("log", "--diff-filter=A", "--format=%H", "--name-only", ref, "--", "docs/bugs/")
    current = None
    paths = {}
    for line in output.splitlines():
        if re.fullmatch(r"[0-9a-f]{40}", line):
            current = line
        elif current and line.startswith("docs/bugs/") and "/" not in line[len("docs/bugs/"):]:
            paths[line] = current
    by_commit = {}
    for path, commit in paths.items():
        by_commit.setdefault(commit, []).append(path)
    result = {}
    for commit, commit_paths in by_commit.items():
        tags = [tag for tag in _git("tag", "--contains", commit, "--list", "v*").splitlines() if TAG_RE.match(tag)]
        if tags:
            release = min(tags, key=lambda tag: tuple(int(part) for part in TAG_RE.match(tag).group(1).split(".")))
            source = "added_tag"
        else:
            match = BRANCH_RE.search(branch)
            release = f"v{match.group(1)}" if match else None
            source = "added_branch"
        for path in commit_paths:
            result[path] = (release, source) if release else None
    return result


def _release_for_added(path, added):
    return added.get(path)


def tally(ref):
    listing = _git("ls-tree", "-r", "--name-only", ref, "docs/bugs")
    paths = [path for path in listing.splitlines()
             if path.startswith("docs/bugs/") and "/" not in path[len("docs/bugs/"):]]
    branch = _git("symbolic-ref", "--short", "-q", ref).strip() if ref != "HEAD" else _git("branch", "--show-current").strip()
    added_releases = _added_releases(ref, branch)
    result = {}
    for path in paths:
        raw = _git("show", f"{ref}:{path}")
        priority, state = doc_meta(raw)
        added = _release_for_added(path, added_releases)
        release, source = doc_release(raw, added)
        bucket = result.setdefault(release, {"total": 0, "closed": 0, "open": 0, "unknown": 0,
                                              "by_source": {}, "by_priority": {p: {"total": 0, "closed": 0, "open": 0, "unknown": 0} for p in ("P0", "P1", "P2", "P3", "unset")},
                                              "open_paths": [], "unknown_paths": []})
        bucket["total"] += 1
        bucket[state] += 1
        bucket["by_source"][source] = bucket["by_source"].get(source, 0) + 1
        pb = bucket["by_priority"][priority]
        pb["total"] += 1
        pb[state] += 1
        if state == "open":
            item = {"path": path, "priority": priority}
            bucket["open_paths"].append(item)
        elif state == "unknown":
            item = {"path": path, "priority": priority}
            bucket["unknown_paths"].append(item)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", default=os.environ.get("K3DM_INDEX_REF", "HEAD"))
    parser.add_argument("--release")
    parser.add_argument("--priority", choices=("P0", "P1", "P2", "P3"))
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        releases = tally(args.ref)
    except (OSError, subprocess.SubprocessError, UnicodeError, ValueError):
        return 2
    if args.json:
        print(json.dumps({"ref": args.ref, "generated_at": datetime.now(timezone.utc).isoformat(), "releases": releases}, separators=(",", ":")))
        return 0
    selected = {args.release: releases.get(args.release)} if args.release else releases
    for release in sorted((name for name, value in selected.items() if value), reverse=True):
        data = selected[release]
        if args.priority:
            data = data["by_priority"][args.priority]
        source_text = ""
        if not args.priority:
            source_text = "   (" + ", ".join(f"{key} {value}" for key, value in data["by_source"].items()) + ")"
        print(f"{release}  total {data['total']} · closed {data['closed']} · open {data['open']} · unknown {data['unknown']}{source_text}")
        for item in data.get("open_paths", []):
            print(f"  open:    {item['path']} [{item['priority']}]")
        for item in data.get("unknown_paths", []):
            print(f"  unknown: {item['path']}")
        if args.priority:
            print(f"({releases[release]['by_priority']['unset']['total']} docs in {release} have no Priority line)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
