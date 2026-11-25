# Bug: `dr-drill` teardown ignores a failed `k3d cluster delete`, so the next drill is refused

**Status:** OPEN — captured 2026-11-23 by Claude from the m2-air drill runs
**Priority:** P3 (operator, 2026-11-23)
**Introduced by:** 38fbf3ab (v1.43.1, clean-room DR drill)
**Should have been caught by:** offline test (teardown with a failing `k3d cluster delete` stub)
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-23
**Prior art:** `docs/bugs/2026-10-10-dr-drill-keep-deletes-kubeconfig.md` (exact-slug glob; vector store unavailable) — read, different root cause (KEEP path)
**Detected by:** Claude, m2-air, 2026-11-23 ~05:25 PST

## Symptom

A drill that failed in Phase 3 (`2026-11-23-dr-drill-restore-empty-age-identity-locked-keychain.md`) ran Phase 6
teardown, yet `k3d cluster list` afterwards showed `dr-drill 0/0 0/1` (server gone, one agent left). The next
`make dr-drill` stopped at preflight with `ERROR: [dr-drill] leftover drill cluster exists`, rc=2. A manual
`k3d cluster delete dr-drill` then succeeded (rc=0).

## Root cause

`bin/dr-drill:99` runs `k3d cluster delete dr-drill >/dev/null 2>&1 || true`: a failed or partial delete is
discarded, the exit code and output are lost, and teardown reports nothing. Preflight (`bin/dr-drill:168-170`) then
refuses correctly, but with no hint why the previous teardown left the cluster.

## Expected

Teardown checks `k3d cluster list` after the delete; if `dr-drill` is still present it retries once, then logs a
warning with the delete output and the manual command, and the drill's exit code reflects the leftover.

## Workaround

`k3d cluster delete dr-drill`, then rerun.

## Recurrence (2026-11-24, m2-air, Claude over SSH)

A `dr-drill` cluster left from the 2026-11-23 runs (`1/1 3/3`, containers up 23 h) blocked `make dr-drill` at preflight.
`k3d cluster delete dr-drill` (k3d v5.9.0) **returned 0** but left `dr-drill 0/0 0/2` (two agents `Exited (137)`). A
second delete printed `WARN Failed to delete cluster network … not found`, then `Successfully deleted cluster dr-drill!`,
rc 0, and the cluster was gone. So checking the delete's exit code is not enough: k3d reports success on a partial
delete. The fix must re-check `k3d cluster list` after the delete and retry once (as Expected above already says).
