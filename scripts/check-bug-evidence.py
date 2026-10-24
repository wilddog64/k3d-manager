#!/usr/bin/env python3
"""Reject newly LIVE-VERIFIED bug docs that omit live-proof evidence."""

import subprocess
import sys
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from hermes.prior_art import doc_fix_commit, doc_live_evidence, doc_verification  # noqa: E402

_INVESTIGATION_TYPE = re.compile(r"^\*\*Verification type:\*\*\s*investigation\s*$", re.MULTILINE | re.IGNORECASE)
_INVESTIGATION_EVIDENCE = re.compile(
    r"^\*\*Live investigation evidence:\*\*\s*(\d{4}-\d{2}-\d{2})"
    r"\s+·\s+source\s+(\S+)\s+·\s+reference\s+(\S+)"
    r"\s+·\s+env\s+(\S+)\s+·\s+scenario\s+(\S+)"
    r"\s+·\s+proves\s+([a-z0-9][a-z0-9,-]*)\s*$",
    re.MULTILINE | re.IGNORECASE,
)


def _head_text(path):
    result = subprocess.run(
        ["git", "show", f"HEAD:{path}"], capture_output=True, text=True, check=False
    )
    return result.stdout if result.returncode == 0 else None


def _evidence_contains_fix(fix_commit, evidence_commit):
    try:
        result = subprocess.run(
            ["git", "merge-base", "--is-ancestor", fix_commit, evidence_commit],
            capture_output=True, text=True, check=False,
        )
    except OSError:
        return None
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    return None


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
        live_evidence = doc_live_evidence(current)
        if not live_evidence:
            investigation_evidence = _INVESTIGATION_EVIDENCE.search(current)
            if investigation_evidence:
                if not _INVESTIGATION_TYPE.search(current):
                    failures.append(
                        f"{relative}: live investigation evidence requires **Verification type:** investigation"
                    )
                elif doc_fix_commit(current):
                    failures.append(
                        f"{relative}: investigation evidence is only for bugs without a **Fix commit:**"
                    )
                continue
            failures.append(
                f"{relative}: LIVE-VERIFIED requires a well-formed **Live evidence:** line or "
                "a typed **Live investigation evidence:** line"
            )
            continue
        fix_commit = doc_fix_commit(current)
        if fix_commit is None:
            failures.append(
                f"{relative}: LIVE-VERIFIED needs a **Fix commit:** <sha> line naming the commit that fixed it"
            )
            continue
        evidence_contains_fix = False
        all_evidence_resolves = True
        for item in live_evidence:
            contains_fix = _evidence_contains_fix(fix_commit, item["commit"])
            if contains_fix is True:
                evidence_contains_fix = True
                break
            if contains_fix is None:
                all_evidence_resolves = False
        if not evidence_contains_fix and all_evidence_resolves:
            failures.append(
                f"{relative}: no **Live evidence:** commit contains the fix commit {fix_commit}"
            )
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
