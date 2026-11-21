# hub_deploy.bats "checkout catches up by the short deadline" races its own background checkout for git's index.lock

**Status:** OPEN — captured 2026-11-21
**Priority:** P3 — test-only; production is serialized by the repo-sync lock
**Introduced by:** 3b541f3b (test 36 added with the checkout catch-up)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-21
**Prior art:** `docs/bugs/2026-11-19-hub-deploy-runs-stale-checkout-copy-of-itself.md` (not scored: `make find-similar-docs` vector store unavailable, cluster context missing) — read, different root cause (that bug added the catch-up this test covers)
**Filed:** 2026-11-21

## Symptom

During `bin/k3dm-codex-dispatch land --slug remote-promote-2c-root-daemon` (fast gate after rebase onto
`k3d-manager-v1.45.0`, 2026-11-21), `scripts/tests/bin/hub_deploy.bats` test 36 failed:

    `wait "$checkout_pid"' failed with status 128
    fatal: Unable to create '.../test/36/scratch-repo/.git/index.lock': File exists.

The same test passed 5 of 5 alone on the release head right after.

## Cause

The test (`scripts/tests/bin/hub_deploy.bats:703`) starts `( sleep 1; git -C "$WORK" checkout -q changed ) &` while
`k3dm-hub-deploy` polls the same repo. The poll loop (`bin/k3dm-hub-deploy:129-142`) runs `git status --porcelain`,
which refreshes the index and briefly holds `.git/index.lock`. When the two overlap, the background checkout exits 128
and the test fails on `wait`. Under full-gate load the overlap window is wider.

In production, the checkout is moved only by `bin/k3dm-repo-sync`, which takes the same `repo-sync/lock` directory that
hub-deploy's `take_lock` takes, so the two never run git in the checkout at the same time. The background checkout in
the test skips that lock, so the race exists only in the test.

## Fix direction

Make the test's background mover behave like repo-sync: take `$HOME/.local/share/k3d-manager/repo-sync/lock`
(mkdir, retrying until free) around the checkout. Do not change hub-deploy for this. Positive control: the test still fails if hub-deploy stops waiting
(`K3DM_HUB_DEPLOY_CHECKOUT_WAIT=0`).
