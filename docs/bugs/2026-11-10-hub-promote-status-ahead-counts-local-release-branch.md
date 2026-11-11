# Bug: `make hub-promote-status` counts "ahead of deploy/hub" from the local release branch, not origin

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-11 (post-merge `/release-groom` triage: patch `v1.43.16` or carry into `v1.44.0`; dispatch after the decision)
**Introduced by:** v1.44.0 hub-deploy-ref work (`bin/k3dm-hub-promote` `status()`), landed in v1.43.15
**Should have been caught by:** offline test (status is tested only in a fixture where local and origin agree)
**Prior art:** `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` absent on the M4, 2026-11-10); exact-slug glob: none
**Severity:** misleading status line on the operator's promote host. Before a promote, the operator reads `ahead: 0` and may conclude there is nothing to promote when origin has new commits. No wrong ref is moved: `hub-promote` itself resolves `REF` against origin.
**Approval:** Claude, 2026-11-10 (filed from two live sightings; dispatch needs the operator's intent approval)
**Intent approved:** operator, 2026-11-11
**Filed:** 2026-11-10
**Detected by:** Claude, from the operator's M5 output: 2026-11-10 plan sweep (first sighting) and the `make hub-promote REF=906aa12e` screen the same day (second)
**Branch:** `k3d-manager-v1.43.15`
**Release:** v1.43.15 or the next patch

## Symptom

On the M5, 2026-11-10, `make hub-promote-status` printed `deploy/hub: 74cd3ca1…` and
`k3d-manager-v1.43.15 ahead of deploy/hub: 0`, while `origin/k3d-manager-v1.43.15` was at `906aa12e`, many commits past
`74cd3ca1` (`git rev-list --count 74cd3ca1..origin/k3d-manager-v1.43.15` on the M4, same day, is non-zero). The M5's
checkout had not been pulled since the last promote.

## Root cause

`bin/k3dm-hub-promote:108-113`: `release` is a bare branch name (`git branch --show-current` or `RELEASE_BRANCH`), and
`git rev-list --count "$sha..$release"` resolves it to the **local** `refs/heads/$release`. On a host whose local branch
is stale, the count reflects that clone, not origin. `deploy/hub`'s SHA comes from `ls-remote` (origin), so the two sides
of the range come from different sources. With no fetch, the local object store may also lack `$sha`, giving `?`.

## Fix

In `status()`: `git fetch --quiet "$REMOTE" "$release" deploy/hub` (read-only for the working tree), count against
`refs/remotes/$REMOTE/$release`, and when the local branch differs from origin, print one more line:
`[hub-promote] local <branch> is N behind / M ahead of origin` so a stale clone is visible.

## Files

| File | Change |
|---|---|
| `bin/k3dm-hub-promote` | `status()` only |
| the existing hub-promote bats suite | a case with a stale local branch |

## Contract readers

`make hub-promote-status` output is read by people only (`git grep -n "ahead of deploy/hub"`, 2026-11-10: the script,
this doc and the 2026-11-07 hub-promote bug's live-check note). No writer changes: `status()` moves no ref.

## Acceptance

```yaml
must:
  - id: M1
    text: "hub-promote-status reports the count of commits on origin's release branch that deploy/hub lacks, whatever the local branch's position."
  - id: M2
    text: "When the local release branch differs from origin, status says so with behind/ahead counts."
must_not:
  - id: N1
    text: "status never reports a count taken from a local branch that differs from origin."
  - id: N2
    text: "status never moves a ref, checks out, or changes the working tree."
evidence:
  - {id: E1, proves: [M1, M2, N1, N2], kind: offline, intent: "You will see a bats case with a scratch origin where the local branch is 3 commits behind origin and 5 past deploy/hub on origin: status prints ahead 5 (not 2) and the local-behind line, and HEAD, the index and every local ref are unchanged; it fails on today's script."}
  - {id: E2, proves: [M1], kind: live, intent: "You run make hub-promote-status on the M5 without pulling first, and the ahead count matches git rev-list against origin that Claude runs on the M4."}
interface:
  - "bin/k3dm-hub-promote status (env RELEASE_BRANCH, REMOTE)"
  - "make hub-promote-status"
```

## Recurrence 2026-11-11 (Claude, M5 over ssh, after promote 64e98c62)

`make hub-promote-status` printed `k3d-manager-v1.43.15 ahead of deploy/hub: 0` while `origin/k3d-manager-v1.43.15` (`5c268d3b`) was 2 commits ahead of `origin/deploy/hub` (`64e98c62`): `git rev-list --count origin/deploy/hub..origin/k3d-manager-v1.43.15` = 2. The local branch sits at `64e98c62` because the hub checkout follows `deploy/hub`, so on the hub this line reads 0 after every promote. The hub-sync backlog (state.json `promote_backlog: 2`) was right. CLAUDE.md tells Claude to confirm promotion with this command, so the 0 is the number most likely to be misread.
