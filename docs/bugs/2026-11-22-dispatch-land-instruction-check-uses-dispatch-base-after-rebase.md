# `land` refuses a rebased task for instruction-file changes that came from the release branch

**Status:** LANDED — `ffc6f3ed` (2026-11-22); E1 verified offline by Claude; E2 live owed (C r2 land)
**Priority:** P2
**Introduced by:** `0959fc6a` (instruction-file refusal, `docs/bugs/2026-11-08-dispatch-land-allow-out-of-scope-lands-instruction-file-changes.md`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-22
**Approval:** operator, 2026-11-22 ("P2 should dispatch now")
**Intent approved:** operator, 2026-11-22
**Intent note:** E1 and E2 approved in session ("Approve, dispatch to Luna")
**Branch:** `k3d-manager-v1.45.0`
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

## Fix

In `_dispatch_land`, compute the start of the instruction-file range the same way `_dispatch_scope_verdict` does:
start from the recorded base, and if `git merge-base <target> HEAD` succeeds and the recorded base is an ancestor of
that merge-base, use the merge-base instead. Use that start both in `_dispatch_instruction_files` and in the refusal's
`git diff <start> HEAD -- <path>` display. The uncommitted, staged and untracked checks stay as they are.

## Contract readers

| Reader | Changes? |
|---|---|
| `bin/k3dm-codex-dispatch:897-911` `_dispatch_instruction_files` | yes: called with the computed start, not the raw base (or takes the target and computes it) |
| `bin/k3dm-codex-dispatch:1393-1408` refusal and diff display | yes: same start |
| `bin/k3dm-codex-dispatch:1539-1544` `land` ledger event `instruction_files` | yes, by effect: no longer lists release-branch files after a rebase; field name and shape unchanged |
| `bin/k3dm-codex-dispatch:862-864` `_dispatch_scope_verdict` | no: the model for the fix; reuse it through a shared helper if that stays minimal |
| `bin/k3dm-dispatch-metrics`, `bin/k3dm-dispatch-logs` (`land_refused`) | no: reason and detail unchanged |

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | range start for the instruction-file check and its diff display |
| `scripts/tests/bin/codex_dispatch.bats` | tests for the Acceptance block |

## Do not

- Do not change the protected path set, the flag names, or `--allow-out-of-scope` behaviour.
- Do not change `_dispatch_scope_verdict` behaviour.
- Do not edit any real instruction file (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.claude/*`, ...) in this task: the
  tests create them only inside the BATS scratch repo.
- Do not run tests against the real repo, real worktrees or the real ledger; assert the fixture points at its scratch
  repo before acting. Never run real `sudo` or `launchctl`.

## Acceptance

```yaml
must:
  - id: M1
    text: A task rebased onto a target that gained a CLAUDE.md change after the dispatch base, with no protected path in the task's own commits, lands without --allow-instruction-files.
  - id: M2
    text: The landed ledger event's instruction_files for the M1 task is empty.
  - id: M3
    text: A task with no rebase (target unchanged since dispatch) behaves exactly as before - a task commit editing CLAUDE.md is refused without the flag and lands with it.
must_not:
  - id: N1
    text: After a rebase, a task commit that itself edits CLAUDE.md (or .claude/settings.json) is still refused without --allow-instruction-files, and the refusal shows the task's own added line (positive control for M1).
  - id: N2
    text: After a rebase, an uncommitted or untracked protected file in the task worktree is still refused.
  - id: N3
    text: The refusal diff after a rebase does not show the target's own instruction-file change (only the task's).
  - id: N4
    text: A recorded base that is not an ancestor of the merge-base (history rewritten) does not widen or narrow the range silently - the check falls back to the recorded base, as the scope check does.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3, N4]
    kind: offline
    how: BATS in scripts/tests/bin/codex_dispatch.bats with the existing scratch-repo fixture (target branch gains a CLAUDE.md commit after dispatch; task rebased). M1 and N3 red on pre-fix code; each must_not shown red with its guard broken.
    intent: "Proves, in a scratch repo, that a task rebased past someone else's CLAUDE.md change can land without the override, while a task that edits CLAUDE.md itself is still stopped."
  - id: E2
    proves: [M1, M2]
    kind: live
    how: Claude lands web-console-c-totp-gate-r2 (task d85926d4, rebased over 1ab308ef) on the real dispatcher without --allow-instruction-files; it is not refused for instruction files and the land event's instruction_files is empty.
    intent: "Shows on the real dispatcher that the web-console C land that was wrongly refused today now goes through with no instruction-file override."
interface:
  - bin/k3dm-codex-dispatch land --slug SLUG (--test CMD|--no-test) [--allow-out-of-scope] [--allow-instruction-files]
  - ledger event land field instruction_files
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run `bats scripts/tests/bin/codex_dispatch.bats` in full, not only the new tests: command, exit code, every error line. If the sandbox blocks a test, name it.
2. For each `must_not`: break its guard, show its test red, restore, show green. List any that stayed green.
3. Show M1 and N3 red against the pre-fix `bin/k3dm-codex-dispatch`.
4. No read-only real-data run: E2 is Claude's. Say so.
5. List every choice the spec did not decide.

## Fix direction (original capture)

Compute the range the same way as the scope check (merge-base with the target when the recorded base is its
ancestor). Tests: a task rebased over a target commit that edits `CLAUDE.md` lands without the flag (red today), and
a task commit that edits `CLAUDE.md` is still refused after a rebase (positive control).
