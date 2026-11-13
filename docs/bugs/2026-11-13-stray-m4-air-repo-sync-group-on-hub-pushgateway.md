# Bug: a stray `instance="m4-air"` repo-sync group sits on the hub Pushgateway

**Status:** OPEN — captured 2026-11-13 by Claude while watching plan 3 E6
**Priority:** P3 (Claude proposal, revised 2026-11-13 16:25Z after the group was deleted; the earlier P2 proposal is withdrawn)
**Waiting on:** operator decision — since 2026-11-13 (P3 confirmation, then batch with the next repo-sync dispatch)
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

## Update 2026-11-13 15:57Z: the stray group now pages

After the promote of `6375f228` loaded the plan 3 rules at 15:24Z, a read-only GET of hub Prometheus (`ssh m5-air.local curl -s 127.0.0.1:19091/api/v1/alerts`) shows
`K3dmPromoteLookupFailed{instance="m4-air",cluster="hub",job="k3dm_repo_sync",repo="k3d-manager",severity="warning"}` **firing**, active since 15:25:56Z.
The hub's own job (`instance="m5-air"`) is healthy: at the same moment it holds `K3dmPromoteWaiting{sha="cf8cfc2"}` pending.
That alert is false: the M4 is not the hub and computes no promotion. Until option 1 or 2 lands, every K3dmPromoteLookupFailed page has to be checked for `instance`.
The rule could also be scoped to the hub instance, but that only hides the symptom. Options 1 and 2 above still stand.

## Update 2026-11-13 16:25Z: group deleted, M4 role written, cause corrected

- Operator deleted the group on the M5 (`curl -s -X DELETE http://127.0.0.1:19094/metrics/job/k3dm_repo_sync/instance/m4-air`). Claude confirmed: 0 `instance="m4-air"` series on the hub Pushgateway, and `K3dmPromoteLookupFailed` is no longer listed in hub Prometheus alerts (16:20Z); the hub's own `K3dmPromoteWaiting{instance="m5-air"}` is unaffected.
- Push time of the deleted group: `push_time_seconds` 1794578588 = 2026-11-13 14:03:08Z, a single push, never refreshed.
- Correction to "Make the default safe" above: `bin/k3dm-repo-sync` already pushes only when the role is `hub` (`is_hub`, :358, push block :488-509), and the M4 had no role file at all (its launchd job exits 1). So the 14:03Z push came from a run that was **given** a hub role — most likely a test or verifier reproduction with a scratch `XDG_CONFIG_HOME` holding `hub`, and `PUSHGATEWAY_URL` unset. The default `http://localhost:19094` (:502) then reached the hub through the M4's ssh forward (an `ssh` process listens on 127.0.0.1:19094 here).
- Fix shape (option 2, refined): drop the default. Push only when `PUSHGATEWAY_URL` is set; warn and skip otherwise. The hub's launchd template `scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl` does not set it today (only PATH), so it gains `PUSHGATEWAY_URL=http://localhost:19094`. This is a contract change (env var): the spec must list every reader and writer, and rollout must run `make install-repo-sync` on the M5 right after the promote, or the hub stops pushing and its own promote alerts go silent. Tests: unset URL → no curl (with a positive control: set URL → one PUT), plist carries the variable.
- Option 3 done: `~/.config/k3d-manager/machine-role` on the M4 = `worker` (operator go, 16:20Z). `bin/k3dm-repo-sync --check` dry-run: every repo `current`, `skipped:ahead` or `skipped:no-upstream`, nothing would update; worker mode never pushes metrics.
- Ruled out (16:50Z): `scripts/tests/bin/repo_sync.bats` cannot be the source. Since `aa1196ed` (2026-11-12) its `setup()` puts a `curl` stub first on PATH and asserts `command -v curl` is the stub (:81, :119), and the hub-role tests set `PUSHGATEWAY_URL=http://127.0.0.1:9`. The remaining candidate is an ad-hoc verifier or reproduction run of `bin/k3dm-repo-sync` with a hub role between 13:35Z and 14:35Z (independent verifiers ran then); not provable after the fact. The fix above covers it either way.
