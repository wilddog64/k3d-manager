# hub-sync stops following deploy/hub once the hub checkout's upstream branch is deleted on origin

**Status:** OPEN — found 2026-11-11 by the Fable pre-PR review of v1.43.15; reproduced by Claude in a scratch repo
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-11 (intent approval, then dispatch in v1.43.15 together with the launchd PATH bug, same file)
**Introduced by:** `d06c0340` (v1.43.15, hub-sync promote backlog fix)
**Should have been caught by:** spec (the backlog fix spec said "second refspec in the same `git fetch`")
**Prior art:** none above threshold — exact-slug glob empty; `find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing); `grep "couldn't find remote ref" docs/bugs` no match
**Approval:** pending

## Symptom

After a release merges and its branch is deleted on origin, every hub sync run of the k3d-manager checkout fails with
`fatal: couldn't find remote ref refs/heads/<branch>` (rc 128), records `fetch_failed`, and the checkout stops
advancing to `deploy/hub`. The only signal is `K3dmRepoSyncStale`.

Reproduction (Claude, M4, 2026-11-11, scratch bare origin): push `deploy/hub` and `rel`, delete `rel` on origin, then
`git fetch --no-tags origin '+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub' '+refs/heads/rel:refs/remotes/origin/rel'`
gives `fatal: couldn't find remote ref refs/heads/rel`, `rc=128`. Git fails the whole fetch when one refspec is missing.

## Root cause

`bin/k3dm-repo-sync:136-142` (hub ROOT path) puts the upstream branch refspec in the same `git fetch` as `deploy/hub`.
The hub checkout sits on the release branch (`k3d-manager-v1.43.15` today), and the post-merge flow deletes it.

## Impact

The hub checkout freezes on its last commit after the v1.43.15 merge: `make appsets-reapply` and anything else run from
the checkout use stale code until someone switches the branch. Workaround: switch the hub checkout to `main` (or the new
release branch) after each merge.

## Fix direction

Fetch `deploy/hub` on its own, as before `d06c0340`. Fetch the upstream ref in a second `git fetch` whose failure only
sets the backlog to unknown and never marks the record `fetch_failed` or blocks the fast-forward.

## Contract readers

`fetch_failed` result in state.json: readers `bin/k3dm-repo-sync` summary and the Pushgateway push
(`k3dm_repo_sync_*`, alert `K3dmRepoSyncStale` in `scripts/etc/prometheus/rules/repo-sync.yaml`). They change only in
that a missing upstream no longer produces it. `promote_backlog`: reader `bin/k3dm-repo-sync:211` (unchanged meaning).

## Acceptance

```yaml
must:
  - M1: on the hub role, when the checkout's upstream branch no longer exists on origin, one sync run still fast-forwards the checkout to origin's deploy/hub and records no fetch_failed
  - M2: in that case the promote backlog prints unknown
  - M3: when the upstream exists, the backlog stays the correct count (no regression of d06c0340)
must_not:
  - N1: mark the hub checkout fetch_failed because only the upstream ref is missing
evidence:
  - E1: {proves: [M1, N1], offline: true, intent: "after a release branch is deleted, the hub still follows deploy/hub"}
  - E2: {proves: [M2, M3], offline: true, intent: "the backlog says unknown when the branch is gone, and the right number when it exists"}
  - E3: {proves: [M1], live: true, intent: "on the M5 after the v1.43.15 merge, hub-sync shows the checkout current with deploy/hub"}
interface:
  - bin/k3dm-repo-sync (hub role, ROOT checkout)
  - make hub-sync
```

## Files

- `bin/k3dm-repo-sync`
- `scripts/tests/bin/repo_sync_promote_backlog.bats`
