# Bug: the pre-push fast gate, run from a linked worktree, lets test fixtures write into the real repository

**Status:** FIXED — `9942c413` (Codex; Claude review, independent verifier PASS); live check pending
**Priority:** P1
**Approval:** operator, 2026-10-31 ("approve P1 and P3 bugs then you can dispatch them")
**Filed:** 2026-10-31
**Detected by:** Claude, pushing `k3d-manager-v1.43.13` from a scratch worktree to work around the push drop in
`docs/bugs/2026-10-31-machine-setup-acceptance-copies-whole-working-tree.md`
**Affected:** `.githooks/pre-push`, `scripts/ci/fast_gate.sh`; the suites that build git fixtures
(`scripts/tests/bin/codex_land_pending.bats`, `test_vectordb_bug_metrics.py`, `test_ask_docs.py`, and others that
`git init`, `clone`, `config` or `checkout` in a temp dir)
**Branch:** `k3d-manager-v1.43.13`

## Observed failure

On 2026-10-31 at about 14:50 Claude ran `git -C <scratchpad>/pushwt push origin k3d-manager-v1.43.13`. `pushwt` was a
linked worktree of the main checkout, detached at `3c32022e`. The hook ran the fast gate (86 s), and the push was refused
with rc 1. The gate failed on `codex_land_pending.bats` (`fatal: a branch named 'k3d-manager-v9.9.9' already exists`),
`test_ask_docs.py` (`ValueError: not enough values to unpack`) and 13 cases in `test_vectordb_bug_metrics.py`. In the main
checkout all three pass.

The failures were secondary. While the gate ran, the fixtures wrote into the real repository:

1. **`pushwt` was switched to fixture state.** It was left on a new branch `k3d-manager-v9.9.9` whose commits (`seed`,
   `base`, ...) delete almost the whole tree. `task/v9.9.9/demo` was created and registered as a worktree under a
   `/private/tmp/bats-run-*` path.
2. **A fixture branch reached the public origin.** `origin/k3d-manager-v9.9.9` = `627a8461` ("docs: record demo landed,
   review pending", author `Test <test@example.com>`), built on `3c32022e` and the four unpushed v1.43.13 commits. The
   pre-push main guard did not stop it, because the target was not `main`.
3. **The shared `.git/config` was changed.** It gained `core.bare = true`, which made `git status` in the main checkout
   fail with `fatal: this operation must be run in a work tree`. It also had a `[user]` section with
   `Test <test@example.invalid>`, the identity the Python fixtures use. Whether that section came from this run or an
   earlier one is not known.

Claude restored `core.bare = false`, removed `pushwt`, pruned the stale worktree, and deleted both local `v9.9.9`
branches. The origin branch is still there.

## Root cause

When `git push` runs from a linked worktree, git exports `GIT_DIR` (the worktree's gitdir) to the hook. A push from the
main checkout does not export it. Checked 2026-10-31 with a hook that prints `env | grep ^GIT_`: in the main checkout it
showed only `GIT_CONFIG_PARAMETERS GIT_EDITOR GIT_PREFIX GIT_EXEC_PATH`; in a linked worktree it also showed `GIT_DIR`.
The gate passes the environment on to every suite. A fixture git command that does not set its own `GIT_DIR` therefore
runs against the real repository rather than its temp repository. The worktree config is shared with the main
checkout, so a write there is a write to `.git/config`.

Claude could not reproduce the exact write with single commands in a throwaway repo (`init --bare`, `init`,
`config`, `checkout -b` under an inherited `GIT_DIR`). Which suite set `core.bare` is still open, and the fix must not
depend on finding it.

## Fix

1. `scripts/ci/fast_gate.sh`: before running any suite, unset every repository-locating git variable it inherited:
   `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`,
   `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_NAMESPACE`, `GIT_PREFIX`. The gate finds its own tree with
   `git rev-parse --show-toplevel` before unsetting them, then passes that tree to the suites explicitly.
2. A guard, run before and after the suites, that records `git config --local core.bare`, the `--local` `user.*` values,
   the list of local branches and the list of worktrees of the repository being pushed. If any of them changed, the gate
   fails and names the change.
3. Identify the suite that wrote `core.bare` (run the gate from a linked worktree with the guard on) and record it here.

## Files

- `scripts/ci/fast_gate.sh`
- `scripts/tests/lib/fast_gate.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not delete `origin/k3d-manager-v9.9.9` as part of the fix. The operator decides on it separately.
- Do not "fix" it by refusing pushes from a linked worktree. The gate must be safe wherever git runs it.
- Do not change any suite's fixtures to work around it. The gate owns its environment.

## Acceptance

```yaml
must:
  M1: the gate run from a linked worktree passes on the same commit where it passes in the main checkout
  M2: a suite run by the gate sees no inherited GIT_DIR, GIT_WORK_TREE or GIT_INDEX_FILE
must_not:
  N1: after the gate runs from a linked worktree, the repository's core.bare, local user.*, branch list and worktree list are unchanged
  N2: a fixture suite that runs `git config core.bare true` with no -C does not change the real repository (the guard fails the gate if it does)
evidence:
  E1:
    proves: [M2, N1, N2]
    kind: offline
    intent: >-
      You will see a scratch repository with a linked worktree, the gate run from the worktree via a real
      `git push` to a scratch bare origin, and a probe suite that prints its GIT_ variables and runs
      `git config core.bare true` in its temp dir. The real scratch repository's core.bare stays false. A
      paired control with the variables deliberately passed through shows the probe's write landing,
      so the test can fail. It failed if it passes against today's gate.
    what: bats scripts/tests/lib/fast_gate.bats; the fixture first asserts it points at the scratch repository, not the real tree
  E2:
    proves: [M1, N1]
    kind: live
    intent: >-
      You will see Claude push the release branch from a linked worktree, the gate pass, and
      `git -C <main checkout> config core.bare` print false afterwards with no new local branches.
    what: Claude runs it after the fix lands
interface:
  - .githooks/pre-push (run by git push)
  - scripts/ci/fast_gate.sh [BASE]
```
