# Bug: The Linux control-node how-to's `git checkout <release branch>` step fails on setup's single-branch clone

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-12 (capture-first triage; nothing dispatched)
**Introduced by:** `4bd764b9` (control-node-linux: the how-to's VM sequence)
**Should have been caught by:** live check (the sequence was first run end to end in this E3 rerun)
**Prior art:** exact-slug glob: none. `make find-similar-docs`: unavailable (vector store context `k3d-k3d-cluster` missing on the M4, 2026-11-11)
**Severity:** documentation only. Setup's clone is correct; the documented test step after it fails with
`error: pathspec 'k3d-manager-v1.43.15' did not match any file(s) known to git`. Workaround: `git fetch origin
<branch>:refs/remotes/origin/<branch>` then `git checkout --no-track -B <branch> origin/<branch>`.
**Approval:** Claude, 2026-11-11 (found running control-node E3 in Vagrant under the operator's go)
**Intent approved:** operator, 2026-11-11
**Intent approval words:** "go ahead for that how-to checkout P3"
**Dispatch go:** operator, 2026-11-11: "go ahead for that how-to checkout P3"
**Filed:** 2026-11-11
**Detected by:** Claude, control-node E3 rerun on the M4 Vagrant VM, 2026-11-11
**Branch:** `k3d-manager-v1.43.15`

## Evidence (Claude, M4 Vagrant VM, Ubuntu 24.04 arm64, 2026-11-11)

- `bin/k3dm-machine-setup:286`: repos are cloned with `git clone --branch "$branch" --single-branch`. In the VM,
  `~k3dm-control/src/gitrepo/personal/k3d-manager` has `remote.origin.fetch = +refs/heads/main:refs/remotes/origin/main`
  and only `main`.
- `docs/howto/machine-setup.md` "Linux control node" says to run
  `git checkout <release branch> && make test` in that clone. It fails with the pathspec error above (rc 1). After
  `git fetch origin k3d-manager-v1.43.15:refs/remotes/origin/k3d-manager-v1.43.15`, `git checkout -b ... --track`
  still fails: `fatal: cannot set up tracking information; starting point 'origin/k3d-manager-v1.43.15' is not a branch`
  (rc 128), because the refspec covers only `main`.
- `git checkout --no-track -B k3d-manager-v1.43.15 origin/k3d-manager-v1.43.15` works.

## Fix

Change the how-to's test step to fetch the release branch explicitly and check it out without tracking (the two
commands in the workaround), and say in one sentence that setup clones `main` only. The single-branch clone stays.

## Files

| File | Change |
|---|---|
| `docs/howto/machine-setup.md` | Linux control node test step |

## Contract readers

- None: a how-to read by people. `bin/k3dm-machine-setup`'s clone is unchanged.

## Acceptance

```yaml
must:
  - id: M1
    text: "Following the how-to's Linux test step verbatim in a fresh setup clone checks out the release branch and starts make test."
must_not:
  - id: N1
    text: "The fix never changes how bin/k3dm-machine-setup clones repos."
evidence:
  - {id: E1, proves: [M1], kind: live, intent: "Claude pastes the how-to's new test step into a fresh Vagrant control VM after setup and sees the release head SHA printed and make test start."}
  - {id: E2, proves: [N1], kind: offline, intent: "You will see the diff touch only docs/howto/machine-setup.md."}
interface:
  - "docs/howto/machine-setup.md, Linux control node section"
```

## Worker definition of done

- Change only `docs/howto/machine-setup.md`. Leave changes uncommitted; Claude reviews and lands.
