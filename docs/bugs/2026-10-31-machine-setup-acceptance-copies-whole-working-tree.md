# Bug: machine_setup_acceptance.bats copies the whole working tree, so it takes 7 minutes in the main checkout

**Status:** OPEN
**Priority:** P3
**Approval:** pending (filed by Claude 2026-10-31; operator to approve)
**Filed:** 2026-10-31
**Detected by:** Claude, on the first push through the v1.43.13 fast-gate pre-push hook (`18d7d95d`)
**Affected:** `scripts/tests/bin/machine_setup_acceptance.bats` (`ensure_copy`)
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-31-ci-reds-reproducible-locally-no-fast-gate.md` (the gate that now runs this suite on push)

## Observed failure

The first push of `k3d-manager-v1.43.13` through the new pre-push fast gate took 529 s. One suite took 509 s
of that: `SLOWEST scripts/tests/bin/machine_setup_acceptance.bats 509s`. Run alone in the main checkout on the
M4 it took 7 min 24 s (19.6 s user, 366.9 s system, 45 tests, ~18 s per setup test). In a fresh detached
worktree at `bd68d6ff` the same suite took 39 s.

## Root cause

`ensure_copy` runs `cp -R "$TREE"/. "$T/tree"/` and only then removes `.venv`. In the main checkout `$TREE` is
545 MB with 132,352 files outside `.git`, mostly ignored or untracked content (for example
`scripts/lib/foundation/scripts/lib/acg/node_modules/`, `scratch/`, `scratchpad/`, `__pycache__/`), plus `.git`
itself. A fresh worktree has none of it. The high system time is the file copy.

The suite has always done this; the fast gate makes it visible, because the hook selects the suite whenever a
push touches a file it names (`bin/k3dm-machine-setup`, `Makefile`, the machine lists).

## Fix

Copy only what git tracks: build `$T/tree` from `git -C "$TREE" ls-files -z` (or `git archive HEAD` plus the
working-tree changes to tracked files), so uncommitted edits to tracked files are still tested. Do not copy
`.git`; if a test needs a repo, `git init` the copy. Keep the `.venv` assertion at line ~549.

## Files

- `scripts/tests/bin/machine_setup_acceptance.bats`

## What NOT to do

- Do not exclude untracked files the setup script reads; check every `$TREE/...` path the script uses is tracked.
- Do not drop tests or loosen assertions to save time.

## Acceptance

```yaml
must:
  M1: the suite run in the main checkout on the M4 finishes within 2x its time in a fresh worktree
  M2: an uncommitted edit to a tracked file under bin/ or scripts/etc/machine/ is what the suite tests (not the committed version)
must_not:
  N1: no ignored or untracked file and no .git content appears in the fixture copy
evidence:
  E1:
    proves: [M2, N1]
    kind: offline
    intent: >-
      You will see a fixture tree with an ignored 1 MB file, an untracked file and an uncommitted edit to a
      tracked file; after ensure_copy the copy has the edit and neither of the other two, and no .git. It
      failed if it passes against today's suite.
    what: bats scripts/tests/bin/machine_setup_acceptance.bats
  E2:
    proves: [M1]
    kind: live
    intent: >-
      You will see `time bats scripts/tests/bin/machine_setup_acceptance.bats` in the main checkout and in a
      fresh worktree, the first within 2x of the second. It failed if the main checkout is still minutes slower.
    what: Claude runs both on the M4 and records the times
interface:
  - bats scripts/tests/bin/machine_setup_acceptance.bats
  - TREE (the tree the suite copies)
```
