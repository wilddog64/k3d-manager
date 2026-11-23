# Instruction-file check: an unstaged edit to a tracked instruction file has no test

**Status:** OPEN — captured 2026-11-22, not triaged
**Priority:** P3
**Introduced by:** `0959fc6a` (instruction-file refusal)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Test-coverage gap where `_dispatch_instruction_files` has no BATS test for unstaged edits to tracked instruction files.)
**Waiting on:** operator decision — since 2026-11-22
**Prior art:** `docs/bugs/2026-11-22-dispatch-land-instruction-check-uses-dispatch-base-after-rebase.md` (exact-slug grep, not scored) — read, different root cause: found while verifying it. `make find-similar-docs` not run (unavailable on m4-air).
**Filed:** 2026-11-22
**Detected by:** Claude, mutation check while verifying `dispatch-land-instruction-check-rebase` (`fcf96e0d`)
**Affected:** `bin/k3dm-codex-dispatch` `_dispatch_instruction_files`; `scripts/tests/bin/codex_dispatch.bats`, `codex_dispatch_scope.bats`

## Symptom

Deleting the `git -C "$worktree" diff --name-only` line (unstaged changes) from `_dispatch_instruction_files` leaves
`codex_dispatch.bats` (6/6) and `codex_dispatch_scope.bats` (13/13) green. Committed, staged-new and untracked
protected files are covered (the untracked guard's mutant turns test 4 red); a tracked `CLAUDE.md` modified in the
worktree but not staged is not.

## Impact

None today: the guard exists and works. A future refactor could drop it and no test would notice, letting a worker's
unstaged edit to a tracked instruction file land without `--allow-instruction-files`.

## Fix direction (for triage)

One BATS case: task commits a normal file, then modifies tracked `CLAUDE.md` without staging; `land` without the flag
refuses and shows the added line. Red with the unstaged guard removed. Batch with other `codex_dispatch` P3s.
