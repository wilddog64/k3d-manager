# Bug: `k3dm-codex-dispatch land` cannot land a task branch that contains a subtree pull

**Status:** OPEN — capture
**Priority:** P3
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable on m4 (no k3d-k3d-cluster context) — not run
**Filed:** 2026-11-27, Claude, from the v1.46.0 W4 k3d-manager landing (`v1460-acgssh-k3dm-luna`)

## Evidence

- `land` always rebases the task branch onto the release branch. The branch held a `git subtree pull --squash` of
  lib-foundation v0.5.12 (squash commit plus merge). Rebase failed twice: `Could not apply de36e418... # Squashed
  'scripts/lib/foundation/' changes` and again on the rebuilt `76a47a47`.
- Workaround used: rebuild the branch on the release tip (subtree pull, cherry-pick worker commits), run
  `scripts/ci/fast_gate.sh` by hand, fast-forward and push (`9557ede6`). `land` then refused with `task branch has
  no commits ahead`, and `verify --result pass` refused with `no landed task`, so dispatch metrics show no landing.

## Notes for triage

Options: a `land --subtree-pull <prefix> <remote> <ref>` mode that redoes the pull on the target tip and cherry-picks
the rest; or detect a subtree merge, fast-forward when the branch already contains the target tip, and record the
landing. Memory note: `reference_pull_rebase_flattens_unpushed_subtree_merge`.
