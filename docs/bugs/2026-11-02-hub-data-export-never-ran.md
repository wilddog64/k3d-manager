# Bug: HubDataExportNeverRan on hub

**Status:** OPEN — investigation required; screenshot evidence only
**Priority:** P2
**Filed:** 2026-11-02
**Detected by:** operator Gmail Alertmanager screenshot (messages visible Nov 1–2)
**Branch:** k3d-manager-v1.43.14
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
