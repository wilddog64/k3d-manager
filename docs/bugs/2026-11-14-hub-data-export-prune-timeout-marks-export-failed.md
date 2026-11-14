# Bug: hub data export reports failure when only the prune push timed out

**Status:** OPEN — captured 2026-11-14 by Claude
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-14
**Introduced by:** unknown
**Should have been caught by:** unknown
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unreachable from the M4); read `docs/bugs/2026-11-02-hub-data-export-never-ran.md` (different: setup never ran)
**Approval:** none yet (capture only)

## Symptom

`HubDataExportFailed` (warning) active since 2026-11-14 03:43:49 PST (11:43Z). `~/Library/Logs/k3dm-hub-data-export.log` on m5-air (read-only, 2026-11-14):

    To github-k3dm-hub-data:wilddog64/k3dm-hub-data.git
       aab0107..89f0211  snapshots -> snapshots
    ...
    prune: 20261108T114515Z
    prune: 20261109T113141Z
    Read from remote host github.com: Operation timed out
    ERROR: [hub-data] export 20261114T113323Z pushed; prune failed

The snapshot reached GitHub; only the retention prune push failed, and `k3dm_hub_data_export_last_run_success` went to 0. Snapshots carry files up to 68 MB (`identity-postgres-keycloak-pvc.tar.age`, GH001 warning).

## Questions for triage

Should a prune-only failure page as an export failure (data is safe), or set a separate prune metric? Was the timeout an early sign of `2026-11-14-hub-internet-downloads-stall-at-first-receive-window.md` (onset seen 15:48Z, four hours later; the clone in the same run succeeded)? Does the next 11:3xZ run retry the prune?
