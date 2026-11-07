# Bug: HubDataExportNeverRan on hub

**Status:** OPEN — alert cleared 2026-11-05 and exports run; the earlier gap is unexplained and a restore is untested
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-06
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

## Acceptance

- [ ] Capture actual failing resource/run IDs, timestamps and diagnostic evidence.
- [ ] Reproduce or independently verify the failure mode and root cause.
- [ ] Implement or document safe remediation with regression coverage.
- [ ] Confirm healthy subsequent execution and alert resolution using live evidence.
- [ ] Record human intervention and link any related bug or plan.

**Note:** Initial triage; not a confirmed diagnosis or a claim that remediation has occurred.

## Prior-art / duplication check (2026-11-02)

Related existing bug: `docs/bugs/2026-10-11-hub-data-export-fails-under-launchd-and-dr-alerts-never-deployed.md` — marked FIXED with live proof on M4 (export success and rule deployed). The current screenshot shows `HubDataExportNeverRan` on hub after the M5 migration. Treat this as a **possible recurrence or metric migration gap**, not a confirmed new export implementation defect. Compare Pushgateway series identity, export artifacts and launchd schedule on current hub. If the same Oct 11 defect is confirmed, consolidate this report into the older bug and close/remove this duplicate.

## Read-only M5 check, 2026-11-06 about 17:40Z

- `HubDataExportNeverRan` last fired 2026-11-05 11:33Z. The history available starts 2026-11-03 12:03Z and it fired from then on.
- The export metric first appears 2026-11-05 11:39Z. The latest success is 2026-11-06 11:39Z, with 3 exports kept, 243931174 bytes, and launchd reports exit 0.
- The Pushgateway pod has not restarted since 2026-10-30, so a wiped metric does not explain the gap: the run due about 2026-11-04 11:30Z did not leave a metric. Why is not established.
- Whether an export can be restored was not tested; this check was read-only.
