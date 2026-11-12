# hub-sync stops following deploy/hub once the hub checkout's upstream branch is deleted on origin

**Status:** OPEN — found 2026-11-11 by the Fable pre-PR review of v1.43.15; reproduced by Claude in a scratch repo
**Priority:** P2
**Waiting on:** dispatch — since 2026-11-11
**Introduced by:** `d06c0340` (v1.43.15, hub-sync promote backlog fix)
**Should have been caught by:** spec (the backlog fix spec said "second refspec in the same `git fetch`")
**Prior art:** none above threshold — exact-slug glob empty; `find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing); `grep "couldn't find remote ref" docs/bugs` no match
**Approval:** operator, 2026-11-11 ("approve two P2s")
**Intent approved:** operator, 2026-11-11

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

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (comment out the check, invert the condition), run its
   test, show it red, then restore the guard and show it green. List any `must_not` whose test stayed green with the
   guard broken.
3. Where the spec allows a read-only run against real data (a real file, a real ledger, a real container image), run
   the changed code once that way and paste what it printed. Otherwise say "no read-only real-data run possible" and
   why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).
```

### 2. Cross-vendor diff review before Claude's review

When the worker exits successfully, a reviewer from the other vendor reviews the diff against the spec: Flash
reviews Luna's work, and Luna reviews Flash's. It is linked to the task:

`bin/k3dm-codex-dispatch start --spec <review brief> --slug <slug>-review --parent <slug> --role review --agent <other>`

- The brief gives the reviewer the spec and the worker's diff, and asks for findings only, with file:line, the input
  that breaks it, and the spec line it violates. The reviewer changes no files.
- Findings are advisory. Claude checks each one, sends the real ones back to the worker by `resume`, and records the
  rest as noise.
- Claude still reviews last, before `codex-land`.
- The diff goes inline in the brief, `docs/reviews/<slug>-review.md`, committed before `start` (settled on first use,
  2026-11-08). Untracked new files are included with `git add -N` before `git diff`, then unstaged again.
- `start` runs the intent gate for review children too. The operator approves each brief, and the brief carries
  `**Intent approved:**` (operator, 2026-11-08, choosing this over exempting `--role review` from the gate).
- `start` also needs a `## Files` section with a backticked path: list the files under review, marked read-only.

### 3. Spec review by a second agent before intent approval

Before Claude shows the operator the intents of a trial spec, an agent that did not write it runs `/spec-review`
against it. The agent also answers: what does the spec leave undecided that a worker would have to guess (paths,
modes, platforms, defaults)? Claude fixes the spec, and then asks for intent approval.
