#!/usr/bin/env python3
"""Reject bug Status values that the dashboard would misread as open."""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from hermes.prior_art import (  # noqa: E402
    _CLOSED_RE,
    _DEFERRED_RE,
    _status_value,
)

_OPEN_RE = re.compile(r"^(?:OPEN|REOPENED)\b", re.IGNORECASE)
_OPEN_LANDED_RE = re.compile(r"^OPEN\b.*\bfix landed\b", re.IGNORECASE)


def _head_text(path):
    result = subprocess.run(
        ["git", "show", f"HEAD:{path}"], capture_output=True, text=True, check=False
    )
    return result.stdout if result.returncode == 0 else None


def _refusal(value):
    if not (
        _CLOSED_RE.search(value)
        or _DEFERRED_RE.search(value)
        or _OPEN_RE.search(value)
    ):
        return True
    return bool(_OPEN_LANDED_RE.search(value))


def main(paths):
    failures = []
    for raw_path in paths:
        path = Path(raw_path)
        relative = path.as_posix()
        if not (path.parent.as_posix() == "docs/bugs" and path.suffix == ".md"):
            continue
        try:
            current = path.read_text(encoding="utf-8")
        except OSError:
            continue
        value = _status_value(current)
        if value is None:
            continue
        head = _head_text(relative)
        if head is not None and _status_value(head) == value:
            continue
        if _refusal(value):
            failures.append(
                f'{relative}: invalid Status "{value[:60]}"; a landed fix starts LANDED, '
                "and VERIFIED once independently verified; anything still open starts OPEN"
            )
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
