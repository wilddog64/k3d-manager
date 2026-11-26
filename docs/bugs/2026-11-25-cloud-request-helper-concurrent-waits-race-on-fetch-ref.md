# Bug: two `k3dm-cloud-request --wait` runs in one checkout race on the fetch ref; one exits 4

**Status:** OPEN — capture
**Priority:** P3 (the request itself is unaffected and its response still lands; only the waiting helper gives up)
**Introduced by:** pre-existing (`bin/k3dm-cloud-request` fetches into a fixed `refs/remotes/origin/cloud-requests`)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** `docs/bugs/2026-11-25-cloud-request-helper-push-runs-fast-gate-and-times-out.md` (same helper) — read, different root cause
**Filed:** 2026-11-25
**Detected by:** Claude, v1.46.0 plan 1 E-P1-live step c (m4)

## Observed

m4, 2026-11-25 17:43–17:44 PST: `bin/k3dm-cloud-request make-e2e --wait` (request `20261126T014345Z-make-e2e`) and,
20 s later, `bin/k3dm-cloud-request cluster-status --wait` in the same checkout. The cluster-status run returned `ok`; the
make-e2e run printed `awaiting operator approval (c1-e3c802ec)` and exited 4 after 41 s. Its response later landed normally
(`304d2564`).

## Cause (likely, not yet reproduced)

Both runs call `git fetch origin +refs/heads/cloud-requests:refs/remotes/origin/cloud-requests` in the same repo; a fetch
that loses the ref lock raises `RuntimeError`, and the wait loop returns 4 on any fetch error
(`bin/k3dm-cloud-request`, the `except RuntimeError: return 4` in `main`).

## Fix direction

Retry a failed fetch inside the wait loop (bounded, before the deadline) instead of exiting 4, and print the git error.
Test: a fake `_git` that fails the first fetch then succeeds still returns the response.
