#!/usr/bin/env python3
"""Reject newly LIVE-VERIFIED bug docs that omit live-proof evidence."""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from hermes.prior_art import doc_live_evidence, doc_verification  # noqa: E402


def _head_text(path):
    result = subprocess.run(
        ["git", "show", f"HEAD:{path}"], capture_output=True, text=True, check=False
    )
    return result.stdout if result.returncode == 0 else None


def main(paths):
    failures = []
    for raw_path in paths:
        path = Path(raw_path)
        relative = path.as_posix()
        if not (relative.startswith("docs/bugs/") and path.suffix == ".md"):
            continue
        try:
            current = path.read_text(encoding="utf-8")
        except OSError:
            continue
        if doc_verification(current) != "live":
            continue
        head = _head_text(relative)
        if head is not None and doc_verification(head) == "live":
            continue
        if not doc_live_evidence(current):
            failures.append(relative)
    for path in failures:
        print(f"{path}: LIVE-VERIFIED requires a well-formed **Live evidence:** line", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
