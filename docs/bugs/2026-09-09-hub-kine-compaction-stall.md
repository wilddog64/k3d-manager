# Hub Kine compaction stall causes control-plane saturation

## What was observed

The hub K3s Kine SQLite datastore reached 8.3 GiB with 1,013,597 rows. An
offline integrity check and `VACUUM INTO` completed but produced another 8.3
GiB database with zero freelist pages: this is retained history, not reclaimable
SQLite fragmentation.

Read-only follow-up on 2026-09-10 showed:

```text
8831115264
time="2026-09-10T00:52:47Z" level=info msg="Slow SQL ... INSERT INTO kine..."
time="2026-09-10T01:00:49Z" level=info msg="Slow SQL ... INSERT INTO kine..."
time="2026-09-10T01:15:44Z" level=info msg="Slow SQL ... SELECT ... FROM kine..."
```

No `COMPACT` event appeared in the preceding 30-minute K3s log window. The
same incident included an ArgoCD registration for an expired ACG endpoint
(`host.k3d.internal`), which drove reconciliation retries.

The implemented Hermes probe was then live-verified read-only:

```text
(0, '{"available": true, "state_db_bytes": 8831115264, "slow_sql_count": 3, "compaction_recent": true, "stale_acg_registration": false}')
```

This later sample observed a compaction event in its 20-minute window, but the
database remains above the 8 GiB protection threshold. The stale registration
is absent now, so the automatic circuit breaker cannot pause anything merely
because of historical DB size.

## Root cause

Kine compaction was not keeping pace with revision churn. The stale ACG
registration amplified that churn. Storage expansion or SQLite vacuuming does
not correct the active history/compaction failure.

## Fix

`docs/plans/v1.33.0-hermes-kine-circuit-breaker.md` adds a read-only Hermes
Kine sensor and a narrow, opt-in circuit breaker: it pauses only the hub ArgoCD
application controller when sustained Kine pressure and the exact stale ACG
signature are both present. It never deletes Kine rows.

## Follow-up

Remove stale generated ACG Applications before resuming the controller. Confirm
regular K3s `COMPACT` events after churn stops. If compaction still cannot keep
up, design a controlled hub rebuild from GitOps/Vault; do not script raw SQLite
retention deletion.
