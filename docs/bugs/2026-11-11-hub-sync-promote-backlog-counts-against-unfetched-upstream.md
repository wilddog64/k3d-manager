# hub-sync promote backlog counts against an upstream ref the hub never fetches

**Status:** OPEN — found by the independent verifier for `v1.43.15-checkout-auto-sync` (2026-11-11)
**Priority:** P2
**Waiting on:** dispatch — since 2026-11-11
**Introduced by:** `f310b4d4` (v1.43.15 checkout-auto-sync)
**Should have been caught by:** offline test
**Prior art:** none above threshold — exact-slug glob empty; `find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing), not run
**Approval:** operator, 2026-11-11 ("approved"): fix in v1.43.15
**Intent approved:** operator, 2026-11-11

## Symptom

`make hub-sync` prints `promote backlog: 0` while the release branch has commits `deploy/hub` lacks. Independent
verifier fixture (2026-11-11, `scratchpad/plan-verify/checkout-auto-sync/tests/verify.bats`, M8 backlog test):
`deploy/hub` equal to HEAD, `origin/main` one commit ahead in the bare origin, summary reads `promote backlog: 0`,
expected 1. The other 29 tests from the Acceptance block passed on head.

## Root cause

On the hub's own k3d-manager checkout the sync fetches only `deploy/hub`
(`bin/k3dm-repo-sync:134-137`, refspec `+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub`). The backlog is
`git rev-list --count origin/deploy/hub..<@{upstream}>` (`bin/k3dm-repo-sync:321-323`), and this script never
refreshes `<@{upstream}>` on that path. The count is as fresh as whatever last fetched the branch, which on the hub
may be nothing. Not yet shown live: whether another hub process fetches the upstream (E6 of the plan would show it).

## Impact

The one number meant to say "a promote is waiting" can read 0 when one is. The operator reads `hub-sync` before
deciding whether to promote; a wrong 0 delays live checks (the v1.43.15 delay this week was mostly promote waits).
Workaround: `make hub-promote-status`, or `git fetch origin && git rev-list --count origin/deploy/hub..origin/<branch>`
on the hub. `promote_backlog` is display only (`bin/k3dm-repo-sync:211`); no metric or alert reads it.

## Fix direction

On the hub ROOT path, fetch the upstream ref too (second refspec in the same `git fetch`), still fast-forwarding the
checkout only to `deploy/hub`. If the upstream fetch fails, print `promote backlog: unknown`, never a number.

## Contract readers

`promote_backlog` in the state written by `bin/k3dm-repo-sync`: reader `bin/k3dm-repo-sync:211` (summary line,
changes only in freshness). No other reader (`grep -rn promote_backlog bin scripts docs/howto docs/guides`,
2026-11-11).

## Acceptance

```yaml
must:
  - M1: on the hub role, after one sync run, the promote backlog equals the number of commits on the origin's upstream branch that origin's deploy/hub lacks, even when the local upstream ref was stale before the run
  - M2: the checkout still advances only to origin's deploy/hub, never to the upstream branch
must_not:
  - N1: print a numeric backlog when the upstream fetch failed (prints unknown)
evidence:
  - E1: {proves: [M1], offline: true, intent: "hub-sync says how many commits are waiting to promote, and the number is right even if nothing else fetched"}
  - E2: {proves: [M2], offline: true, intent: "fetching the release branch does not move the hub's checkout past deploy/hub"}
  - E3: {proves: [N1], offline: true, intent: "if GitHub can't be reached, the backlog says unknown instead of a wrong number"}
  - E4: {proves: [M1], live: true, intent: "on the M5, hub-sync's backlog matches make hub-promote-status"}
interface:
  - bin/k3dm-repo-sync (hub role, ROOT checkout)
  - make hub-sync
```

## Worker definition of done

- Edit only `bin/k3dm-repo-sync` and a new or existing test under `scripts/tests/bin/` for it.
- Tests use a local bare origin in a scratch dir and a scratch `HOME`; Pushgateway URL `http://127.0.0.1:9`; no
  `launchctl`, `gh` or network. Assert the fixture first (scratch HOME, bare origin path, not the real tree).
- E1 and E3 tests shown red against the pre-fix `bin/k3dm-repo-sync` (paste the red output in your final message).
- One mutation (drop the new refspec) shown red.
- `shellcheck bin/k3dm-repo-sync` clean; the existing repo-sync bats suite still green.
- Do not commit; leave the changes in the worktree.
