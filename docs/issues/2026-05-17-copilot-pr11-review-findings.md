# Copilot PR #11 Review Findings

**PR:** #11 — fix: AWS sandbox credential extraction and dialog handling
**Date:** 2026-05-17
**Fix commit:** `97210c4`

---

## Finding 1 — `.githooks/pre-commit`: missing subtree guard

**Flagged:** Makefile:19 — `git config core.hooksPath .githooks` replaces existing hooks path, losing the subtree guard from `scripts/hooks/pre-commit` that blocks direct commits to `scripts/lib/foundation/`.

**Fix:** Added the subtree guard block to `.githooks/pre-commit` (lines 4–21), matching `scripts/hooks/pre-commit:4-22`.

**Root cause:** `.githooks/pre-commit` was written as a new file without porting the guard from the existing hook.

**Process note:** When redirecting `core.hooksPath`, always diff the existing hook against the new one and port all guards.

---

## Finding 2 — `.githooks/pre-commit`: missing `--diff-filter=ACM`

**Flagged:** `.githooks/pre-commit:11` (and line 4) — `git diff --cached --name-only` without `--diff-filter=ACM` includes deleted/renamed paths; `node --check "$f"` and `shellcheck "$f"` fail when the file no longer exists.

**Before:**
```bash
staged_js=$(git diff --cached --name-only | grep '\.js$' || true)
staged_sh=$(git diff --cached --name-only | grep -E '^(bin/|scripts/)' | grep -v '\.js$' || true)
```

**After:**
```bash
staged_js=$(git diff --cached --name-only --diff-filter=ACM | grep '\.js$' || true)
staged_sh=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^(bin/|scripts/)' | grep -v '\.js$' || true)
```

**Root cause:** Hook template did not include `--diff-filter`. The existing `scripts/hooks/pre-commit` uses `-z` + `--diff-filter=ACM` correctly.

**Process note:** Every `git diff --cached --name-only` feeding into a file-existence check must include `--diff-filter=ACM`.

---

## Finding 3 — `memory-bank/progress.md:24`: stale dialog dismiss description

**Flagged:** Entry said "dismisses it with DOM clicks" but implementation uses `bringToFront()` + `keyboard.press('Enter')` with WARN fallback.

**Fix:** Updated to: "dismisses it with bringToFront+Enter (best-effort; WARN fallback if dialog persists — credentials populate via Extend path regardless)".

**Root cause:** Memory-bank entry was written at an earlier iteration of the fix and not updated as the implementation changed.
