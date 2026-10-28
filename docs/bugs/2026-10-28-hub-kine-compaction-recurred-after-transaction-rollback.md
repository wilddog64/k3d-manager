# Hub Kine compaction stops again after revision-record transaction rollback

**Status:** OPEN — live recurrence confirmed 2026-10-28; controlled recovery pending
**Priority:** P2 — retention is stalled with a controlled rebuild workaround; API remains ready
**Filed:** 2026-10-28
**Release:** v1.43.9 bug; no new enhancement plan
**Branch:** `k3d-manager-v1.43.9`
**Approval:** explicit operator 2026-10-28: "then you may file a proper bug for the recurrence kine issue". Filing/investigation only; no restart, rebuild or remediation authorization.
**Component:** hub K3s/Kine datastore, `k3d-k3d-cluster-server-0` on M4
**Related:** [earlier compaction incidents](2026-09-09-hub-kine-compaction-stall.md), [sensor/alert fix](2026-10-11-hermes-kine-sensor-misses-dead-compaction.md), [rebuild orchestration fix](2026-10-11-hub-recover-all-never-rebuilds-the-hub.md), [rebuild runbook](../howto/hub-rebuild-from-gitops-vault.md)

## Observed recurrence

Operator supplied a firing `HubKineCompactionStalled` email. Read-only Prometheus
queries confirm the warning is currently firing. This is a new October28
recurrence: successful compactions occurred today before the latest error,
whereas the earlier parent record described the October24 episode.

The last successful cycle was **2026-10-28 17:45:03 UTC (10:45:03 PDT)**.
The next cycle started at17:50:03 and failed at **17:50:14 UTC (10:50:14 PDT)**:

```text
time="2026-10-28T17:45:03Z" level=info msg="COMPACT deleted 462 rows from 450 revisions in 70.683595ms - compacted to 1773483/1774483"
time="2026-10-28T17:50:03Z" level=info msg="COMPACT compactRev=1773483 targetCompactRev=1773955 currentRev=1774955"
time="2026-10-28T17:50:14Z" level=error msg="Compact failed: failed to record compact revision: sql: transaction has already been committed or rolled back"
```

No later successful compaction appeared in the bounded current Docker log
window. The log search uses case-sensitive `msg="COMPACT` / `COMPACT deleted`,
not a broad compact search that can match SQL text. Prometheus independently
reports last-compaction epoch1793209503.378494, matching the successful log.

## Current impact and telemetry

- Alert expression: `time() - k3dm_hub_kine_last_compaction_timestamp_seconds > 1800`, held for15minutes; current state firing.
- At the sampled query, compaction age4336seconds (about72minutes), Kine metrics push age627seconds, Hermes tick age490seconds. Direct logs corroborate the fault; this is not inferred only from an old email.
- `state.db`:583081984bytes (556.07MiB); WAL:78090512bytes (74.47MiB), from read-only byte counts. Main-file size matches the published gauge.
- `/readyz?verbose` passes, including etcd readiness. All four nodes report Ready=True. These checks establish current readiness, not database integrity or recovery.
- Container running, image `rancher/k3s:v1.32.0-k3s1`, StartedAt `2026-10-25T12:40:00.428960292Z`, RestartCount0. No restart was performed during investigation.

Full actual read-only outputs, query results and limits are in
[the investigation evidence](../issues/2026-10-28-hub-kine-recurrence-investigation.md).

## Diagnosis and remaining uncertainty

The immediate failure is the revision-record transaction rollback at17:50:14,
followed by no successful compaction cycles. This matches the prior stalled
compaction signature. The underlying reason the transaction was cancelled is
not established; sleep/wake, workload and other service actions are not proven
causes for this occurrence. No goroutine inspection or SQLite write/query was
performed. Database file allocation alone is not a reliable growth forecast.

Retention remains impaired even while the API is ready. Unbounded history can
increase control-plane pressure over time; current measurements do not show a
control-plane outage. The alert should remain visible until recovery is proved.

## Recovery scope and operator decision

**Do not restart the K3s server as the remedy.** The parent incident documents
bootstrap crash loops after restart against a backed-up datastore. Do not
manually delete SQLite rows, vacuum/rewrite the live database or remove profile
state as an attempted fix.

Prepare a controlled `make hub-recover-all` recovery under the existing runbook:
first validate current backups/export integrity, restore prerequisites and
rollback/recovery readiness, then obtain explicit operator go for the operation.
The parent record names an October29 rebuild slot; scheduling and readiness have
not been independently reconfirmed here. This filing does not execute or approve
that rebuild.

Rebuild is a recovery workaround, not proof the underlying Kine transaction
failure has been permanently corrected. A preventive fix/version change needs
its own evidence and approved scope; no enhancement plan is added by this bug.

## Acceptance evidence required

1. Record explicit operator recovery authorization and the exact approved operation, with successful backup/restore preflight evidence.
2. Record actual recovery/restore output and verify API/node readiness plus the runbook's service/data checks.
3. Observe consecutive successful `COMPACT deleted` cycles over at least30minutes, with fresh Hermes/Pushgateway samples and last-compaction age remaining below the alert threshold.
4. Verify `HubKineCompactionStalled` resolves in Prometheus/Alertmanager and remains resolved during that observation window. Missing/stale telemetry is not a pass.
5. Record datastore and WAL before/after values without assuming the SQLite main file must shrink. Continue follow-up for a later recurrence; short recovery observation does not prove prevention.

## Current authorization boundary

This is a live-confirmed incident filing only. No implementation task dispatched,
new plan, PR, restart, database mutation or hub rebuild. The separate M4 test-all
run is still being watched; its start is later than the compaction error and
has not been established as a cause.
