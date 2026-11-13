# hub-promote containment check refuses the first promote of every release: `git cherry` cannot see squash merges

**Status:** OPEN
**Priority:** P2 (proposed: blocks every first promote of a new release; workaround BREAK_GLASS=1 after a manual check, which also skips the green-checks gate)
**Classified:** pending second-agent classification
**Introduced by:** `aa97c491` (v1.43.15, the uncontained-commits guard from `2026-11-10-hub-promote-discards-cve-promoter-commits.md`)
**Should have been caught by:** spec (the guard's spec did not consider that releases are squash-merged to `main` and the next release is cut from `main`)
**Prior art:** `docs/bugs/2026-11-10-hub-promote-discards-cve-promoter-commits.md` (grep `cherry`/`squash`, read) — this bug is a false positive of that fix
**Waiting on:** operator decision

## Symptom

2026-11-12 on the M5: `make hub-promote REF=34707659f2bddc36192d4c49e5fe65acdc9d6de5` (v1.44.0 tip, CI green) failed with
`[hub-promote] ERROR: deploy/hub contains N commit(s) not in …` and listed about 100 v1.43.15 commits ending in `9f5f0d89`.

## Cause

`uncontained_commits` (`bin/k3dm-hub-promote:21-27`) uses `git cherry <new> <old>`, which matches commits by per-commit
patch-id. v1.43.15 merged to `main` as one squash commit (`aa1196ed`, PR #160), and v1.44.0 was cut from `main`,
so none of v1.43.15's original commits match. Every one is reported as "not contained" although its content is in the target.

## Evidence (Claude, 2026-11-12)

- `git merge-base --is-ancestor 9f5f0d89 5a53e35b`: the `deploy/hub` tip is an ancestor of PR #160's head.
- `git rev-list --count 5a53e35b..origin/deploy/hub` = 0: no promoter or other commit outside the PR.
- `git diff --stat aa1196ed 5a53e35b`: 3 files and 4 lines, all newer dependabot bumps on `main`.
- `aa1196ed` is an ancestor of `34707659`.

So the promote drops nothing. It was done with `BREAK_GLASS=1`, which also skips `check_runs`. Claude had checked
both check runs green on `34707659` beforehand.

## Fix direction (for triage)

Treat an `old` commit as contained when it is an ancestor of a merged PR head whose squash commit is an ancestor of
`new` (via `gh api repos/…/commits/<sha>/pulls`). Or, simpler: before the cherry check, accept `old` when the
tree of `old` merged into `new` equals `new`'s tree (`git merge-tree --write-tree new old` with no conflicts). Keep
`check_runs` independent of BREAK_GLASS so the bypass skips only the guard that misfired.

## Outcome (2026-11-13)

The operator promoted with `BREAK_GLASS=1` at 00:34Z: `deploy/hub` moved to 34707659. The tag push then failed in the
pre-push fast gate (`scripts/ci/fast_gate.sh:129-136`): the M5 checkout's `k3d-manager-v1.44.0` still pointed at the
v1.43.15 history (9f5f0d89), whose squashed-away commits (fcc4fa4a, bb71f0cb, …, 2026-11-09) carry
`test@example.invalid`. Same root cause as this bug: individual commits outliving a squash merge. After
`git reset --hard origin/k3d-manager-v1.44.0` (backup `refs/k3dm/manual-backup/20261112`) the tag
`hub-promote/20261113T003457Z` pushed, and `make platform-ops` applied deploy/hub 34707659.
