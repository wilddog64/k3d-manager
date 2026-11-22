# `land` refuses a rebased task for instruction-file changes that came from the release branch

**Status:** OPEN — captured 2026-11-22, not triaged
**Priority:** P2
**Introduced by:** `0959fc6a` (instruction-file refusal, `docs/bugs/2026-11-08-dispatch-land-allow-out-of-scope-lands-instruction-file-changes.md`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-22
**Prior art:** `docs/bugs/2026-11-08-dispatch-land-allow-out-of-scope-lands-instruction-file-changes.md` (exact-slug grep, not scored) — read, different root cause: that change added the check; this is its diff range. `make find-similar-docs` unavailable on m4-air (vector store needs kube context `k3d-k3d-cluster`).
**Filed:** 2026-11-22
**Detected by:** Claude, landing `web-console-c-totp-gate-r2`
**Affected:** `bin/k3dm-codex-dispatch` (`_dispatch_instruction_files`, `_dispatch_land`)

## Symptom

`land --slug web-console-c-totp-gate-r2` refused with `instruction files require --allow-instruction-files`, listing
`.claude/settings.json` and `CLAUDE.md`. The task commit (`d85926d4`) touches neither: its 12 files are the TOTP gate,
tests, Makefile, howto and `not-installed.list`. Both diffs shown were the release branch's own `1ab308ef`
(autoCompactWindow trial, operator-approved).

## Cause

The task was rebased onto `k3d-manager-v1.45.0` (68 commits past the dispatch base `d17e565b`) to resolve a conflict.
`_dispatch_land` passes the recorded dispatch base to `_dispatch_instruction_files` (`bin/k3dm-codex-dispatch:1393`),
which diffs `"$base" HEAD` (`:900`). After a rebase, that range includes every release-branch commit since dispatch.
`_dispatch_scope_verdict` already handles this: it moves `from` to `merge-base "$rel" HEAD` when the recorded base is
an ancestor of it (`:862-864`). The instruction check does not.

## Impact

Any task rebased over a release-branch change to an instruction or hook file cannot land without
`--allow-instruction-files`, an override meant for real instruction edits. Routine use of that override would hide a
worker's real instruction edit, which is what `0959fc6a` exists to stop.

## Fix direction (for triage)

Compute the range the same way as the scope check (merge-base with the target when the recorded base is its
ancestor). Tests: a task rebased over a target commit that edits `CLAUDE.md` lands without the flag (red today), and
a task commit that edits `CLAUDE.md` is still refused after a rebase (positive control).
