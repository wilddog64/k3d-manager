# Copilot PR #11 Review Findings

**Date:** 2026-03-22
**PR:** #11 — `docs(api): fix 12 Copilot PR #8 doc accuracy findings`
**Fixed in:** `08cfbc8`

---

## Finding 1 — PR description mismatch: described as docs-only but includes .sh changes

**File:** `scripts/lib/system.sh` (line 58)
**Flagged:** PR test plan said no `.sh` files touched, but branch includes upstream lib sync commits.

**Fix:** Updated PR description to accurately reflect both doc fixes and upstream lib sync scope.

**Root cause:** PR body was drafted based on the v0.3.4 spec (docs-only), but the branch also carried upstream sync commits added in earlier sessions.

---

## Finding 2 — `_run_command_resolve_sudo` header comment inaccurate

**File:** `scripts/lib/system.sh` (line 44–46)
**Flagged:** Comment said "Caller must initialize `_RCRS_RUNNER` before calling" but the function resets it unconditionally on entry.

**Before:**
```bash
# it in the global _RCRS_RUNNER. Caller must initialize _RCRS_RUNNER before
# calling and unset it after reading.
```

**After:**
```bash
# it in the global _RCRS_RUNNER. _RCRS_RUNNER is reset unconditionally on entry;
# caller reads it after this returns and may unset it when done.
```

**Root cause:** Comment was written when the function expected an initialized global; behavior changed but comment was not updated.

---

## Finding 3 — `_agent_audit` checked both staged and unstaged diffs

**File:** `scripts/lib/agent_rigor.sh` (line 79)
**Flagged:** `changed_sh` used both `git diff --cached` and `git diff`, blocking commits due to unrelated local edits.

**Before:**
```bash
changed_sh="$(
   { git diff --cached --name-only -- '*.sh' 2>/dev/null; git diff --name-only -- '*.sh' 2>/dev/null; } \
      | sort -u || true
)"
```

**After:**
```bash
changed_sh="$(
   git diff --cached --name-only -- '*.sh' 2>/dev/null || true
)"
```

**Root cause:** Unstaged diff was added to cast a wider net, but it breaks pre-commit behavior where only staged files should be checked.

---

## Finding 4 — `SCRIPT_DIR` dependency undocumented in `_agent_audit`

**File:** `scripts/lib/agent_rigor.sh` (line 46)
**Flagged:** Allowlist default path uses `${SCRIPT_DIR}` but `agent_rigor.sh` doesn't initialize it; sourcing directly (without `system.sh`) yields a broken path.

**Fix:** Added doc comment above `_agent_audit` noting the `SCRIPT_DIR` requirement and the `AGENT_AUDIT_IF_ALLOWLIST_FILE` override.

**Root cause:** Architectural convention (source `system.sh` first) was implicit — not documented at the function level.

---

## Finding 5 — Docs said "staged diffs" but implementation checked both staged and unstaged

**File:** `docs/api/functions.md` (line 132)
**Flagged:** Doc said "Audits staged diffs" but code used both `git diff --cached` and `git diff`.

**Fix:** Resolved by Finding 3 — reverting to staged-only makes the docs accurate again. No doc change needed.

---

## Finding 6 — `memory-bank/activeContext.md` marked v0.3.4 as MERGED while PR was still in review

**File:** `memory-bank/activeContext.md` (line 27)
**Flagged:** Version table showed `**MERGED**` before the PR was merged.

**Fix:** Changed to `**in review**` with PR #11 reference.

**Root cause:** Codex updated the memory-bank optimistically after completing its task, before PR review.

---

## Finding 7 — `memory-bank/progress.md` said "docs-only, no .sh changes" inaccurately

**File:** `memory-bank/progress.md` (line 35)
**Flagged:** Entry said no `.sh` changes but branch includes upstream lib sync commits touching `.sh` files.

**Fix:** Updated entry to reflect both doc fixes and upstream lib sync scope.

**Root cause:** Same as Finding 1 — progress entry was scoped to the docs task only.

---

## Finding 8 — `line` not declared `local` in allowlist parsing loop

**File:** `scripts/lib/agent_rigor.sh` (line 56)
**Flagged:** `line` variable leaks into caller's shell environment.

**Fix:** Added `local line` declaration before the `while IFS= read -r line` loop.

**Root cause:** New allowlist-parsing loop added without following the `local` discipline used elsewhere in the file.

---

## Process Notes

- **Rule added:** Every new `while read` loop must declare loop variable with `local` before the loop.
- **Rule added:** PR description must reflect the full branch scope (all commits since branch point), not just the task spec scope.
- **Rule added:** Memory-bank status fields (`MERGED`, `in review`, etc.) must not be set until the PR is actually in that state.
