#!/usr/bin/env python3
"""Reject newly approved plan documents that still say DRAFT."""

import re
import subprocess
import sys
from pathlib import Path

_APPROVED_RE = re.compile(
    r"(?mi)^\*\*Intent approved:\*\*\s*(?!no\b|pending\b)[^,\n]+,\s*\d{4}-\d{2}-\d{2}\b"
)


def _header(text):
    return re.split(r"(?m)^## ", text, maxsplit=1)[0]


def _pair(text):
    header = _header(text)
    match = re.search(r"(?mi)^\*\*Status:\*\*\s*(.*)$", header)
    if not match:
        return None, False
    return match.group(1).split()[0].casefold() if match.group(1).split() else "", bool(
        _APPROVED_RE.search(header)
    )


def _head_text(path):
    result = subprocess.run(
        ["git", "show", f"HEAD:{path}"], capture_output=True, text=True, check=False
    )
    return result.stdout if result.returncode == 0 else None


def main(paths):
    root = Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    )
    failures = []
    for raw_path in paths:
        path = Path(raw_path)
        absolute = path if path.is_absolute() else Path.cwd() / path
        try:
            relative = absolute.resolve().relative_to(root.resolve())
        except ValueError:
            continue
        if relative.parent.as_posix() != "docs/plans" or relative.suffix != ".md":
            continue
        try:
            current = absolute.read_text(encoding="utf-8")
        except OSError:
            continue
        status, approved = _pair(current)
        if status != "draft" or not approved:
            continue
        head = _head_text(relative.as_posix())
        if head is not None and _pair(head) == (status, approved):
            continue
        failures.append(
            f"{relative.as_posix()}: Status DRAFT but intent is approved; "
            "a reviewed, approved spec starts READY (or IN PROGRESS / LANDED)"
        )
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
