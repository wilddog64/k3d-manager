# Copilot PR #42 Review Findings

**Date:** 2026-03-22
**PR:** [#42 — chore(v0.9.8): if-count easy wins + dry-run doc/tests](https://github.com/wilddog64/k3d-manager/pull/42)
**Fix commit:** `bf21b08`

---

## Finding 1 — Weak assertion in dry-run test

**File:** `scripts/tests/lib/dry_run.bats:21`

**Finding:**
The first test used `[[ "$output" != "hello" ]]` to prove the command wasn't executed. This is insufficient — the dry-run preview prints `[dry-run] echo hello`, which contains the word `hello`, making the assertion fragile and potentially misleading.

**Fix:**
Changed the test command from `echo hello` to `touch "$BATS_TEST_TMPDIR/ran"` and asserted the file was NOT created:
```bash
run _run_command -- touch "$BATS_TEST_TMPDIR/ran"
[ "$status" -eq 0 ]
[[ "$output" == *"[dry-run]"* ]]
[[ "$output" == *"touch"* ]]
[ ! -e "$BATS_TEST_TMPDIR/ran" ]
```

**Root cause:** Original assertion tested output content rather than actual side-effect absence. The spec comment said "checking the output isn't just hello" but Copilot correctly flagged that the dry-run output includes the command arguments.

**Process note:** Dry-run tests must assert non-execution via side effects (file not created, service not called), not via output string matching.

---

## Finding 2 — Duplicate `v0.9.8 ACTIVE` entry in progress.md

**File:** `memory-bank/progress.md:6,11`

**Finding:**
Two separate `v0.9.8 ACTIVE` lines appeared in the Overall Status section — one added by Claude with the spec/assignee detail, one added by Codex as a bare branch-cut line. This made the status summary ambiguous.

**Fix:**
Collapsed to a single entry:
```
**v0.9.8 ACTIVE** — PR #42 open 2026-03-22. if-count easy wins + dry-run doc/tests.
```

**Root cause:** Claude added the first entry when creating the spec; Codex added the second when updating memory-bank on task completion. Neither checked for an existing entry before writing.

**Process note:** When updating memory-bank Overall Status, always grep for an existing entry for the current version before adding a new line.
