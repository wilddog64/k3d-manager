# Bug: a stray `instance="m4-air"` repo-sync group sits on the hub Pushgateway

**Status:** OPEN — captured 2026-11-13 by Claude while watching plan 3 E6
**Priority:** P3 (stale series; no alert fires from it today)
**Waiting on:** operator decision — since 2026-11-13
**Introduced by:** unknown
**Should have been caught by:** unknown
**Prior art:** exact-slug glob: none; memory `feedback_pushgateway_tests_leak_to_real_hub` (same class). `make find-similar-docs` not run

## Symptom

Read-only GET of the hub Pushgateway (`ssh m5-air.local curl 127.0.0.1:19094/metrics`, 2026-11-13 14:23Z):
`k3dm_repo_sync_promote_lookup_failed{instance="m4-air",job="k3dm_repo_sync",repo="k3d-manager"} 1`, group pushed 2026-11-13 14:03:08Z.

- The M4 is a worker, and its own launchd `com.k3d-manager.repo-sync` exits 1 at startup (`machine-role file missing or empty`), so the M4 job did not publish this group.
- On the M4, 127.0.0.1:19094 is an ssh forward to the hub Pushgateway, so a hub-role `bin/k3dm-repo-sync` run on the M4 without `PUSHGATEWAY_URL` reaches the hub (the default is `http://localhost:19094`, `bin/k3dm-repo-sync:502`).
- Every committed suite that runs repo-sync isolates it: a curl stub or `PUSHGATEWAY_URL=127.0.0.1:9` (repo_sync.bats, repo_sync_promote_backlog.bats, repo_sync_launchd_env.bats; hub_sync.bats does not run repo-sync). The source is therefore probably an ad-hoc reproduction or an agent run around the 14:03Z repo-sync landing, not a suite.

## Impact

Pushgateway groups never expire. A panel that sums `promote_lookup_failed` without filtering `instance` shows 1. If a stray push ever carries `k3dm_repo_sync_promotable`, `K3dmPromoteWaiting` fires for a SHA the hub did not compute.

## Options (operator decision)

1. Delete the group: `curl -X DELETE http://127.0.0.1:19094/metrics/job/k3dm_repo_sync/instance/m4-air` on the M5 (write to the hub; operator runs it).
2. Make the default safe: have repo-sync publish only when the role is hub and the hostname matches the hub host, or require `PUSHGATEWAY_URL` to be set explicitly.
3. Write the M4's machine-role file (`worker`) so the M4 job runs as intended. Its own logs show an error every 5 minutes.
