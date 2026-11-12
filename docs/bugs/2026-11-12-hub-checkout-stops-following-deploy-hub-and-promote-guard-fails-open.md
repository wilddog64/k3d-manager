# Hub checkout stops following deploy/hub after a rollback or carried promoter commit; promote containment guard fails open

**Status:** OPEN — captured 2026-11-12 from the Fable pre-merge review of v1.43.15
**Priority:** P2
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (degraded, nothing broken live today, manual reset and promote-tag recovery work around both); Claude proposed P2. Agreed.
**Waiting on:** operator decision — since 2026-11-12
**Introduced by:** v1.43.15 (checkout auto-sync and deploy/hub promote plans)
**Should have been caught by:** offline test
**Prior art:** docs/bugs/2026-11-10-repo-sync-reports-zero-behind-for-diverged-checkout.md (not scored) — read, different root cause (that one is the behind metric for non-hub repos); find-similar-docs not run
**Approval:** none yet (capture only)

Two related defects in the deploy/hub path, found in one review. Both reproduced in scratch repos.

## 1. The hub checkout stops following deploy/hub

`bin/k3dm-repo-sync:200-204` fast-forwards the hub checkout only when `HEAD` is an ancestor of
`origin/deploy/hub`; otherwise it records `skipped:not-ff-to-deploy-hub` and stops.

- **After `make hub-rollback`:** deploy/hub moves back from E to D. E is not an ancestor of D, so every
  run skips. The checkout keeps running the rolled-back code: the webhook, Hermes, launchd agents, `bin/`.
- **After a promote that carries a CVE-promoter commit:** the promoter commits C on deploy/hub and the
  hub fast-forwards to C. The operator carries C to the release branch by `git cherry-pick -x`, as
  `docs/howto/hub-promote.md` says, which gives it a new SHA C'. The promote to D passes, since
  `git cherry` matches C' by patch-id, but hub HEAD (C) is not an ancestor of D, so the checkout is
  stuck again.

ArgoCD and `make platform-ops` still follow deploy/hub; only the code the checkout runs diverges. No code
path recovers. The workaround is `git reset --hard origin/deploy/hub` on the hub. `behind_after` reads 0
meanwhile, and `K3dmRepoSyncStale` fires only after about 70 minutes.

**Evidence (re-run by Claude 2026-11-12, M4, scratch HOME, local bare repo, stubbed launchctl and curl;
script written by the reviewer):**
- carried promoter commit: `hub: rel skipped:not-ff-to-deploy-hub (2 behind before, 0 after)`,
  `hub HEAD=C fix(cve): pin  deploy/hub=D`, on repeated runs
- control, pure fast-forward: `hub: rel updated`, `hub HEAD=E deploy/hub=E`
- rollback E→D: `hub: rel skipped:not-ff-to-deploy-hub (0 behind before, 0 after)`, `hub HEAD=E deploy/hub=D`

Live today: deploy/hub `9f5f0d89` is an ancestor of the release branch, with no promoter commits, so
nothing is stuck yet. The first rollback or the first CVE pin triggers it.

## 2. The promote containment guard fails open

`bin/k3dm-hub-promote:26`: `git_cmd cherry "$target" "$old" 2>/dev/null | awk ... || true`. If `old` (read
by `ls-remote` at `:252`, after the fetch at `:250`) names a commit the local clone does not have, for
example because the promoter pushed between those two calls, `git cherry` fails with a bad object. The
error is discarded, and the empty output reads as "nothing uncontained". The confirmation prints "no
commits between refs", the lease is built from the fresh `old`, and the force-push drops the promoter
commit without `BREAK_GLASS`. This is the case `aa97c491` was written to refuse. The window is about a
second. The same fail-open applies to any clone whose fetch refspec omits deploy/hub. Rollback is not
affected: `:215-218` fails closed through `merge-base`. The promote tag records the true `old`, so a
dropped commit can be recovered.

**Evidence:** the reviewer's scratch reproduction (a git wrapper that lands a promoter push before the
first `ls-remote`) gave `no commits between refs` then `+ b96a09f...888efa2 -> deploy/hub (forced update)`,
rc=0. Claude confirmed the swallowed error by reading `:20-27`; not re-run.

## Also noted (suspected, P3, read only)

- `bin/k3dm-hub-promote:123-133`: if the branch push succeeds and the tag push fails, the next rollback
  computes `live_sha` from the older tag and refuses, or with `BREAK_GLASS=1` goes back one promote too far.
- `bin/k3dm-repo-sync:201` hardcodes `origin/deploy/hub` while fetch and merge use the configured remote.
