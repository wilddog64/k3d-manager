#!/usr/bin/env python3
"""Count bug documents by release, state and priority without model inference."""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from hermes.prior_art import doc_meta, doc_release, doc_status  # noqa: E402

TAG_RE = re.compile(r"^v(\d+\.\d+\.\d+)$")
BRANCH_RE = re.compile(r"k3d-manager-v(\d+\.\d+\.\d+)")
STATUS_LINE_RE = re.compile(r"^[+-](?:\*\*Status:\*\*|Status:)\s*(.*)$")


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
        release, source = _release_of_commit(commit, branch)
        for path in commit_paths:
            result[path] = (release, source) if release else None
    return result


def _release_of_commit(commit, branch):
    """Return (release, "added_tag"|"added_branch") from tag ancestry, else (None, None)."""
    tags = [tag for tag in _git("tag", "--contains", commit, "--list", "v*").splitlines()
            if TAG_RE.match(tag)]
    if tags:
        return min(tags, key=lambda tag: tuple(int(part) for part in TAG_RE.match(tag).group(1).split("."))), "added_tag"
    match = BRANCH_RE.search(branch)
    return (f"v{match.group(1)}", "added_branch") if match else (None, None)


def _fixed_commits(ref):
    """Map each bug doc to the commit at which its Status last became fixed."""
    output = _git("log", "--reverse", "-p", "-U0", "--no-renames", "--format=commit %H",
                  "-G", "Status:", ref, "--", "docs/bugs/")
    fixed = {}
    is_fixed = {}
    commit = None
    path = None
    created = False
    for line in output.splitlines():
        if line.startswith("commit ") and re.fullmatch(r"[0-9a-f]{40}", line[7:]):
            commit = line[7:]
            path = None
        elif line.startswith("--- "):
            created = line == "--- /dev/null"
        elif line.startswith("+++ "):
            name = line[4:].removeprefix("b/")
            path = name if name.startswith("docs/bugs/") and "/" not in name[len("docs/bugs/"):] else None
        elif path and line.startswith("+") and not line.startswith("+++"):
            match = STATUS_LINE_RE.match(line)
            if not match:
                continue
            now_fixed = doc_status(f"**Status:** {match.group(1)}\n")[1] == "fixed"
            if now_fixed and not is_fixed.get(path):
                if path in is_fixed:
                    source = "status_change"
                else:
                    source = "added_fixed" if created else "status_backfill"
                fixed[path] = (commit, source)
            elif not now_fixed:
                fixed.pop(path, None)
            is_fixed[path] = now_fixed
    return fixed


def _fixed_releases(ref, branch, paths_fixed):
    releases = {}
    by_commit = {}
    for path, (commit, source) in paths_fixed.items():
        if source == "status_backfill":
            releases[path] = ("unknown", source)
            continue
        if commit not in by_commit:
            by_commit[commit] = _release_of_commit(commit, branch)[0]
        releases[path] = (by_commit[commit] or "unknown", source)
    return releases


def _release_for_added(path, added):
    return added.get(path)


def _read_blobs(ref, paths):
    request = "".join(f"{ref}:{path}\n" for path in paths).encode()
    blob = subprocess.run(["git", "-C", str(ROOT), "cat-file", "--batch"], input=request,
                          capture_output=True, check=True, timeout=60).stdout
    texts = {}
    offset = 0
    for path in paths:
        header_end = blob.index(b"\n", offset)
        header = blob[offset:header_end].split()
        if len(header) != 3 or header[1] != b"blob":
            raise RuntimeError(f"git cat-file: unexpected header for {path}: {blob[offset:header_end]!r}")
        start = header_end + 1
        size = int(header[2])
        texts[path] = blob[start:start + size].decode("utf-8")
        offset = start + size + 1
    return texts


def _scan(ref):
    listing = _git("ls-tree", "-r", "--name-only", ref, "docs/bugs")
    paths = [path for path in listing.splitlines()
             if path.startswith("docs/bugs/") and "/" not in path[len("docs/bugs/"):]]
    branch = ref.removeprefix("origin/") if ref != "HEAD" else _git("branch", "--show-current").strip()
    added_releases = _added_releases(ref, branch)
    texts = _read_blobs(ref, paths)
    result = {}
    for path in paths:
        raw = texts[path]
        priority, state = doc_meta(raw)
        added = _release_for_added(path, added_releases)
        release, source = doc_release(raw, added)
        bucket = result.setdefault(release, {"total": 0, "closed": 0, "open": 0, "unknown": 0,
                                              "by_source": {}, "by_priority": {p: {"total": 0, "closed": 0, "open": 0, "unknown": 0} for p in ("P0", "P1", "P2", "P3", "unset")},
                                              "open_paths": [], "unknown_paths": [], "closed_paths": []})
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
        elif state == "closed":
            item = {"path": path, "priority": priority}
            bucket["closed_paths"].append(item)
    fixed_commits = _fixed_commits(ref)
    fixed_releases = _fixed_releases(ref, branch, fixed_commits)
    fixed_in = {}
    for path in paths:
        if doc_status(texts[path])[1] != "fixed":
            continue
        commit_info = fixed_releases.get(path)
        fixed_in[path] = ({"release": commit_info[0], "source": commit_info[1]}
                          if commit_info else {"release": "unknown", "source": "no_transition"})
    return result, fixed_in


def tally(ref):
    return _scan(ref)[0]


def fixed_in(ref):
    return _scan(ref)[1]


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", default=os.environ.get("K3DM_INDEX_REF", "HEAD"))
    parser.add_argument("--release")
    parser.add_argument("--priority", choices=("P0", "P1", "P2", "P3"))
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        releases, fixed = _scan(args.ref)
    except (OSError, subprocess.SubprocessError, UnicodeError, ValueError):
        return 2
    if args.json:
        print(json.dumps({"ref": args.ref, "generated_at": datetime.now(timezone.utc).isoformat(),
                          "releases": releases, "fixed_in": fixed}, separators=(",", ":")))
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
        fixed_count = sum(item["release"] == release for item in fixed.values())
        if fixed_count:
            print(f"  fixed here: {fixed_count}")
        for item in data.get("open_paths", []):
            print(f"  open:    {item['path']} [{item['priority']}]")
        for item in data.get("unknown_paths", []):
            print(f"  unknown: {item['path']}")
        if args.priority:
            print(f"({releases[release]['by_priority']['unset']['total']} docs in {release} have no Priority line)")
    unknown_fixed = sum(item["release"] == "unknown" for item in fixed.values())
    if unknown_fixed:
        print(f"fixed in an unknown release: {unknown_fixed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
