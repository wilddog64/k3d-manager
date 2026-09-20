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

The local Hermes LaunchAgent was then armed with
`K3DM_HERMES_AUTO_KINE_GUARD=1` and restarted. Its launchd state is `running`;
the first two new samples recorded the Kine metrics and executed no repair,
because `stale_acg_registration` remains `false`.

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

---

## Recurrence — 2026-09-20 (observed live, read-only)

The hub was rebuilt after the 2026-09-09 incident: `k3d-k3d-cluster-server-0` has
`StartedAt=2026-09-13T19:26:02Z`, `RestartCount=0`. The datastore was therefore reset ~7 days
ago. It has already regrown:

| Measure | 2026-09-09 | 2026-09-20 |
|---|---|---|
| `state.db` | 8,831,115,264 (8.3 GiB) | 2,323,902,464 (2.16 GiB) |
| `state.db-wal` | not recorded | 523,421,312 (499 MiB) |
| `COMPACT` events | none in a 30 min window | **none in a 24 h window** |

That is roughly **310 MB/day**, which reaches the 8 GiB protection threshold again in about
19 days. Compaction is not merely lagging — it is producing zero events per day.

### Measured consequences

- Kine SQL latency 1.0–5.1 s on ordinary `SELECT ... FROM kine` and `INSERT INTO kine`,
  continuously.
- `metrics.go:299 "Failed to get storage metrics" storage_cluster_id="etcd-0" err="context
  deadline exceeded"` → apiserver `/healthz` reports **`[-]etcd failed`** on 5/5 consecutive
  probes. `kubectl` intermittently returns
  `stream error: stream ID 1; INTERNAL_ERROR`.
- `controller.go:195 "Failed to update lease"` for `kube-node-lease/457182e619fc`, repeatedly.
  The control-plane node is **`Ready=False (KubeletNotReady) container runtime is down`** with
  taint `node.kubernetes.io/not-ready` added `2026-09-20T13:47:57Z`.
- Load average **60.03** inside the server container against `nproc=10`; the container is
  consuming 511% CPU and 6.9 GiB of 15.66 GiB. Host load average 21.56 on 10 CPUs.
- ArgoCD repo-server at `10.43.86.193:8081` is refusing connections, so ~20 Applications sit at
  `sync=Unknown` with `Failed to load target state`. The controller retries, which feeds the
  churn.
- Collateral restart loops: `prometheus-node-exporter` 190 restarts, `trivy-server`
  CrashLoopBackOff ×14, `payment-service` ×7.

### Why the existing circuit breaker did not fire

`K3DM_HERMES_AUTO_KINE_GUARD=1` gates on sustained Kine pressure **AND** the exact
`stale_acg_registration` signature from 2026-09-09 (`host.k3d.internal`). Today
`ubuntu-k3s-app-cluster` resolves to `https://kubernetes.default.svc`, so that predicate is
false, and the size threshold is 8 GiB while the database is at 2.16 GiB. The breaker is
therefore inert for this recurrence and will stay inert until the cluster is already in the
state it was meant to prevent.

Applications generated for the `ubuntu-k3s` ACG cluster (`istio-base-ubuntu-k3s`,
`istio-cni-ubuntu-k3s`, `istiod-ubuntu-k3s`) still exist even though no `ubuntu-k3s` kubectl
context is present — the sandbox is not provisioned. This is the 2026-09-09 follow-up item
("Remove stale generated ACG Applications") still outstanding.

### Relationship to the apiserver scrape-timeout fix

`0d663a40` gave the apiserver ServiceMonitor a 45s `scrapeTimeout` and was applied live on
2026-09-20. It is correct and it stops `KubeAPIDown` flapping, but it treats a **symptom**: the
8.36 MB `/metrics` payload takes 7–25 s to serve because the control plane is CPU-starved and
datastore-bound, not because 10s was an unreasonable timeout. The scrape timeout should not be
read as closing this bug.

### Open questions for the fix

1. Why does compaction emit zero events per day? Establish whether the compaction goroutine is
   erroring, starved, or disabled before choosing a remedy.
2. Is the ArgoCD repo-server outage a cause of the churn, an effect of CPU starvation, or both?
3. The unbounded WAL (499 MiB) suggests checkpointing is also not completing — confirm the
   journal mode and `wal_autocheckpoint` in effect.

**Do not** script raw SQLite retention deletion (unchanged from the original guidance). Do not
delete the `profile` or `pw-profile` directories. Any hub rebuild is the operator's action.
