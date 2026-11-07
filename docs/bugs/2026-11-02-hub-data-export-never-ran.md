# Bug: HubDataExportNeverRan on hub

**Status:** OPEN — fix implemented 2026-11-07 (Flash run exited; 4 files changed in its worktree, uncommitted); Claude verification and land next. Gap explained: the M5 hub build never ran `hub_data_export_setup`. A restore is untested.
**Priority:** P2
**Waiting on:** fix running — since 2026-11-07
**Approval:** operator 2026-11-07: "fix to for spec and dispatch to Flash 3.8"
**Assigned:** Gemini Flash 3.8 (`AGENT=agy MODEL=gemini-3.8-flash-medium`)
**Filed:** 2026-11-02
**Detected by:** operator Gmail Alertmanager screenshot (messages visible Nov 1–2)
**Branch:** `k3d-manager-v1.43.15` (moved 2026-11-07 by Claude, operator: "go ahead to move that four bugs to v1.43.15"; no landed fix to verify in v1.43.14; filed on `k3d-manager-v1.43.14`)
**Area:** monitoring / alerting / cluster operations

## Observed failure

Determine whether the hub export scheduler has ever run, whether it was disabled during M5 migration, and whether backup artifacts exist and are restorable. Distinguish missing telemetry from missing backup. Do not trigger destructive backup/restore.

## Evidence and limitations

The operator screenshot shows a FIRING Alertmanager email for this alert family. This is not live cluster evidence; the underlying cause, exact impacted objects, duration, and current firing state remain unverified. No production remediation was performed.

## Investigation

1. Query Alertmanager for current alerts and full labels, including job_name, namespace, instance and timestamps.
2. Correlate with Prometheus series and the owning component's recent execution logs, events and configuration.
3. Check existing bug documents and recent changes before proposing a fix; link related incidents and avoid duplicate root-cause work.
4. Identify root cause, blast radius, safe mitigation and regression test. Preserve evidence before deleting Jobs or resetting alerts.

## Acceptance (initial triage, superseded)

The triage checklist that stood here is replaced by the fix spec's Acceptance block at the end of this doc.

## Prior-art / duplication check (2026-11-02)

Related existing bug: `docs/bugs/2026-10-11-hub-data-export-fails-under-launchd-and-dr-alerts-never-deployed.md` — marked FIXED with live proof on M4 (export success and rule deployed). The current screenshot shows `HubDataExportNeverRan` on hub after the M5 migration. Treat this as a **possible recurrence or metric migration gap**, not a confirmed new export implementation defect. Compare Pushgateway series identity, export artifacts and launchd schedule on current hub. If the same Oct 11 defect is confirmed, consolidate this report into the older bug and close/remove this duplicate.

## Read-only M5 check, 2026-11-06 about 17:40Z

- `HubDataExportNeverRan` last fired 2026-11-05 11:33Z. The history available starts 2026-11-03 12:03Z and it fired from then on.
- The export metric first appears 2026-11-05 11:39Z. The latest success is 2026-11-06 11:39Z, with 3 exports kept, 243931174 bytes, and launchd reports exit 0.
- The Pushgateway pod has not restarted since 2026-10-30, so a wiped metric does not explain the gap: the run due about 2026-11-04 11:30Z did not leave a metric. Why is not established.
- Whether an export can be restored was not tested; this check was read-only.

## Gap investigation, 2026-11-07 (Claude, read-only; operator: "might want to investigate where is the gap")

**Answer: the export job ran every night on the M5, and every run failed until 2026-11-04 because the hub build never created the export's ServiceAccount.**

Timeline (times UTC; the job runs at 03:30 local, 10:30Z in PDT and 11:30Z in PST):

| When | Where | What | Source |
|---|---|---|---|
| through 2026-10-30 10:34 | M4 | Daily exports succeed; last snapshot `20261030T103446Z` | M4 `~/Library/Logs/k3dm-hub-data-export.log` (born 2026-10-11, last write 2026-10-30) |
| 2026-10-30 22:28 | M5 | launchd job installed (plist birth); hub build in progress | M5 `/usr/bin/stat` of `~/Library/LaunchAgents/com.k3d-manager.hub-data-export.plist` |
| 2026-10-31 10:30 | M5 | Run 1 fails before export: `Host key verification failed` cloning `github-k3dm-hub-data` | M5 export log, lines 1-8 |
| 2026-11-01 to 2026-11-04 | M5 | Runs 2-5 fail: `serviceaccounts "hub-data-export" not found` ... `nothing was pushed`; each pushes `k3dm_hub_data_export_last_run_success 0` (the 99-byte curl lines), so no success timestamp exists and `HubDataExportNeverRan` fires 48h after the hub's Pushgateway started | M5 export log, lines 9-50 |
| 2026-11-04 12:37:28 | M5 hub | ServiceAccount `secrets/hub-data-export` created by a client-side `kubectl apply` (it has `last-applied-configuration`, no ArgoCD labels) | `kubectl -n secrets get sa hub-data-export` |
| 2026-11-04 12:43 | M5 | Manual export, snapshot `20261104T124301Z` | export repo prune log |
| 2026-11-05 11:31 onward | M5 | Scheduled exports succeed daily (`runs = 8`, last exit 0) | M5 export log; `launchctl print` |

**Cause.** The ServiceAccount (and the Vault role the export logs in with) is created only by `hub_data_export_setup` (`scripts/plugins/hub_data.sh:284-290`, `make hub-data-export-setup`). Nothing in the hub build calls it. `scripts/etc/machine/not-installed.list:4` says the export is "installed by the cluster deploy (hub build, v1.43.12 plan 2)". That is true of the launchd job, which was installed on 2026-10-30, but not of the setup the job depends on. `hub_recover` already knows this: it prints `make hub-data-export-setup && make hub-data-export` as a manual next step (`hub_data.sh:1205`). The M5 build was not a recovery, so nothing printed it. Who ran the setup on 2026-11-04 is not recorded.

**Exposure.** The last M4 snapshot is from 2026-10-30. The next is from 2026-11-04. For five days no export was taken, while the hub's data (Vault, Keycloak, LDAP) was live on the M5. The M4 snapshots from 10-26 to 10-30 had aged out of the export repo by 2026-11-05 under its retention rule.

**Alerting worked.** `HubDataExportFailed` (`last_run_success == 0`) and `HubDataExportNeverRan` (no success timestamp for 48h) both had what they needed. The failure was visible. It was not acted on until 11-04.

**Run 1's host-key failure** (2026-10-31) did not recur: run 2 cloned the repo. The `known_hosts` entry for `github-k3dm-hub-data` was added between the two runs; by what is not recorded.

**Proposed fix (needs the operator's go; hub work):** the hub build calls `hub_data_export_setup` after Vault is unsealed and before it installs the export job. The hub build's checks then fail if `secrets/hub-data-export` is missing. Correct the `not-installed.list` note. Acceptance: a test that the hub build's install sequence calls setup before the launchd install. Live evidence: the next hub rebuild drill shows a successful export on the first scheduled run.

## Fix spec (2026-11-07)

### Change

1. `bin/hub-new`, the `data` stage: after `make hub-data-recover` succeeds, run `make hub-data-export-setup`. A failure fails the stage with this next step: `make hub-data-export-setup`, then `HUB_NEW_FROM=data make hub-new`. It goes after the data restore because the setup writes a Vault policy and a Kubernetes auth role. Its self-test also lists `secret/`, which only works once Vault holds restored data. The `prepare-singletons` stage, which installs the export's launchd job, comes after `data`, so the job is never installed without its ServiceAccount.
2. `bin/hub-new` `verify_hub`: fail with `hub-data-export ServiceAccount secrets/hub-data-export is missing` when `kubectl --context "$context" -n secrets get serviceaccount hub-data-export` fails. The next step is `make hub-data-export-setup`. Add `"hub_data_export_sa":"pass"` to the verify JSON and the check table.
3. `scripts/etc/machine/not-installed.list:4`: change the note to `installed by the cluster deploy (hub build: data stage runs make hub-data-export-setup, prepare-singletons installs the job)`. Do not change the label or the installer.
4. `scripts/tests/bin/hub_new.bats`: add the tests in Acceptance. The `make` stub records `make hub-data-export-setup` to `$CALLS` like the other targets. The `kubectl` stub answers `-n secrets get serviceaccount hub-data-export` with exit 0, or exit 1 when `STUB_NO_EXPORT_SA=1`. Copy the wording of the exit-1 error from a real read-only capture on the M5 (`kubectl -n secrets get serviceaccount does-not-exist`) and put the host and date in a comment beside it.
5. `docs/howto/m5-hub-migration.md`: one sentence saying the data stage now runs `make hub-data-export-setup`.

### What NOT to Do

- Do not change `hub_data_export_setup`, `hub_data_export_scheduled`, the launchd template, the alert rules or `hub_recover`.
- Do not run `make hub-new`, `make hub-data-export-setup` or any `kubectl` against a real cluster. Do not edit `CLAUDE.md`, `memory-bank/` or `docs/roadmap.md`.
- Do not reorder `STAGES`.
- No commit, no PR. Do not skip hooks.

## Files

- `bin/hub-new`
- `scripts/etc/machine/not-installed.list`
- `scripts/tests/bin/hub_new.bats`
- `docs/howto/m5-hub-migration.md`

## Acceptance

```yaml
interface:
  - "bin/hub-new (make hub-new), HUB_NEW_FROM=<stage>; stages listed in STAGES"
  - "env: PATH stubs for make, kubectl, docker, launchctl, security as in scripts/tests/bin/hub_new.bats; HUB_NEW_STATE_DIR scratch dir"
must:
  - id: M1
    text: "A full hub-new run calls make hub-data-export-setup after make hub-data-recover and before make hub-data-export-schedule."
  - id: M2
    text: "verify_hub checks that secrets/hub-data-export exists and reports hub_data_export_sa pass in the verify JSON."
  - id: M3
    text: "not-installed.list line for install-hub-data-export names the data-stage setup; label and installer are unchanged."
must_not:
  - id: N1
    text: "hub-new never installs the export job without running the setup: when make hub-data-export-setup fails, the data stage fails, the run stops, and make hub-data-export-schedule is not called (paired control: M1's run calls it)."
  - id: N2
    text: "verify_hub never reports pass when the ServiceAccount is missing: with STUB_NO_EXPORT_SA=1 it exits non-zero, names secrets/hub-data-export, and writes no hub-new-report.json with status pass (paired control: the stubbed SA present gives pass)."
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    what: "bats scripts/tests/bin/hub_new.bats; N1 and N2 shown red on the pre-fix bin/hub-new; the whole suite green after."
  - id: E2
    proves: [M1, M2]
    kind: live
    what: "Operator or Claude: the next hub rebuild drill's hub-new report shows hub_data_export_sa pass, and its first scheduled export succeeds (k3dm_hub_data_export_last_run_success 1, no HubDataExportNeverRan)."
```

## Triage 2026-11-07 (Claude)

The Flash worker has exited, and its four spec-listed files are changed in `~/.local/share/k3d-manager/worktrees/v1.43.15/2026-11-02-hub-data-export-never-ran`. Nothing is landed yet. Next: N1/N2 red on pre-fix, full `hub_new.bats`, land, then E2 at the next hub rebuild drill.
