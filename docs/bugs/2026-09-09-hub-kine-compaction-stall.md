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

---

## Deep dive — 2026-09-20 (read-only), answering the three open questions

### Correction to the recurrence section above

The claim "**none in a 24 h window**" and the derived "zero compaction events per day" were
produced by a `grep -i compact` that matched the string `compact_rev_key` **inside the Slow SQL
statement text**. That pattern matches 50,039 lines in the current server log and none of them
are compaction events. The correct predicate is a case-sensitive `msg="COMPACT`.

With the right predicate, compaction history is unambiguous:

| Date | `COMPACT deleted` events |
|---|---|
| 2026-09-14 (from 19:31 boot) | 54 |
| 2026-09-15 | 288 |
| 2026-09-16 | 288 |
| 2026-09-17 | 288 |
| 2026-09-18 | **27, then nothing** |
| 2026-09-19 | 0 |
| 2026-09-20 | 0 |

288 events/day is exactly one per 5 minutes — the compaction interval running perfectly.

### Q1 — Why does compaction emit zero events? ANSWERED

Compaction did not degrade. It **died at a single instant** and was never rescheduled:

```text
time="2026-09-18T02:16:06Z" level=info msg="COMPACT compactRev=1159837 targetCompactRev=1160605 currentRev=1161605"
time="2026-09-18T02:16:19Z" level=error msg="Compact failed: failed to record compact revision: sql: transaction has already been committed or rolled back"
```

That is the **last** `COMPACT` line in the log. The 02:16:06 cycle began, took 13 s instead of
the usual 150–800 ms, and its transaction was torn down underneath the compactor before it could
write `compact_rev_key`. Kine logged the error and the compaction loop stopped. Nothing has
retried it for 2.5 days.

The only subsequent compaction signal is the apiserver's own periodic call failing at the socket:

```text
E0919 15:12:40 compact.go:124] etcd: endpoint ([unix://kine.sock]) compact failed: rpc error: code = Unavailable desc = keepalive ping failed to receive ACK within timeout
E0919 15:18:00 compact.go:124] ... (same)
E0920 09:40:09 compact.go:124] ... (same)
```

So this is **not** "compaction cannot keep pace with churn" — the 2026-09-09 diagnosis. It is a
single unretried transaction failure that silently disables retention. The remedy is a restart of
the k3s server process (which restarts the compaction loop), not a rebuild, and not storage
expansion.

### Q2 — Is the ArgoCD repo-server outage cause or effect? EFFECT (then an amplifier)

`argocd-repo-server-5ddccb56d7-wkq5l`, 243 restarts. It is not failing for any repo-server
reason. Each incarnation starts cleanly and serves traffic:

```text
msg="argocd-repo-server is listening on [::]:8081"
msg="starting grpc server"
msg="Error serving health check request" component=healthcheck duration=11.278187802s error="rpc error: code = Canceled desc = context canceled"
msg="Error serving health check request" component=healthcheck duration=2.277411312s
msg="got signal terminated, attempting graceful shutdown"
msg="clean shutdown"
```

`lastState.terminated` is `exitCode: 0, reason: Completed` — a graceful SIGTERM from the kubelet,
not a crash. Both probes are `timeoutSeconds: 1`:

```text
liveness:  httpGet /healthz?full=true  periodSeconds=10 timeoutSeconds=1 failureThreshold=3
readiness: httpGet /healthz            periodSeconds=10 timeoutSeconds=1 failureThreshold=3
resources: limits cpu=500m memory=1Gi
```

Health checks taking 1.1–11.3 s against a 1 s timeout and a 500m CPU limit is the known
probe-timeout kill loop, not an application fault. So the outage is an **effect** of the
starvation. It then becomes an amplifier: 27 of 37 Applications sit at `sync=Unknown`, the
application controller retries them, and those retries write into the datastore that has no
retention. Cause and effect run in a loop, but the datastore is upstream.

### Q3 — Is WAL checkpointing also stalled? NO

The WAL is **not** growing. Three samples: 523,421,312 bytes at 13:50, at 14:05 and at 14:09,
byte-identical, with mtime advancing each time. A WAL that is checkpointed is reset to offset
zero and **reused in place** — the file stays at its high-water mark and never shrinks. Constant
size plus advancing mtime is the signature of checkpointing working, not failing. 499 MiB is the
high-water mark set during the incident, not a backlog. Q3 was a false alarm; no journal-mode
change is needed.

### Correction to the growth rate and the deadline

The "~310 MB/day → 19 days" figure averaged the 4.5 days when compaction was healthy together
with the 2.5 days since it died. The post-failure rate is much higher. Three direct samples:

```text
2337374208  2026-09-20 14:04:47
2337374208  2026-09-20 14:04:47
2341658624  2026-09-20 14:14:55
```

+4,284,416 bytes over 10.1 minutes ≈ **580 MB/day**, bursty because SQLite extends in chunks.
At that rate 8 GiB arrives in roughly **7–10 days**, not 19.

### Note on the load average

In-container load average is 67–75 against `nproc=10`, but `top` reports **26% idle**. The load
is dominated by threads blocked waiting on the datastore, not by CPU exhaustion — consistent
with 631 `error in txn compare` events (kine optimistic-concurrency failures). The control-plane
node also returned to `Ready` on its own between the recurrence observation and this dive, so
`KubeletNotReady` was transient pressure, not a broken runtime.

### Revised remedy

The narrow fix is to restart the k3s server process so the compaction loop resumes, then confirm
`msg="COMPACT deleted"` returns at one per 5 minutes and that `state.db` stops growing. A hub
rebuild is not indicated by this evidence. Raw SQLite retention deletion remains forbidden, and
any restart or rebuild is the operator's action.

The durable fix belongs in the Hermes sensor, whose current predicate cannot see this failure:
detect **compaction liveness** (no `msg="COMPACT deleted"` for more than ~15 minutes) rather than
only absolute database size plus the 2026-09-09 stale-registration signature.

---

## Restart attempted 2026-09-20 14:26Z — DID NOT FIX IT, and made the cluster worse

The "revised remedy" above (restart the k3s server process) was **wrong**. The operator ran
`docker restart k3d-k3d-cluster-server-0`. Result:

**Compaction resumed but cannot complete.** It picked up at exactly the revision where it died,
confirming the loop was simply unscheduled — then failed, repeatedly, at the same target:

```text
14:32:12 msg="COMPACT compactRev=1159837 targetCompactRev=1160837 currentRev=1566699"
14:37:53 msg="COMPACT compactRev=1159837 targetCompactRev=1160837 currentRev=1567207"
14:38:03 level=error msg="Compact failed: failed to compact to revision 1160837: sql: transaction has already been committed or rolled back"
14:44:10 msg="COMPACT compactRev=1159837 targetCompactRev=1160837 currentRev=1567694"
14:44:15 level=error msg="Compact failed: failed to compact to revision 1160837: sql: transaction has already been committed or rolled back"
```

`compactRev` never advances from 1159837. Zero progress across every attempt.

Two things this reveals that the pre-restart evidence could not:

1. **The original 2026-09-18 death was the same failure, not a fluke.** The transaction is rolled
   back underneath the compactor because the delete cannot finish in its window against a 2.36 GiB
   table. So it is self-reinforcing: compaction must complete to shrink the database, and the
   database is too large for compaction to complete. A restart cannot break that.
2. **Backlog is ~407,000 revisions** (`currentRev` 1,567,694 vs `compactRev` 1,159,837), and kine
   advances the target by only **1000 revisions per cycle** when the gap is large (healthy cycles
   set `target = currentRev - 1000`; here it is `compactRev + 1000`). Even if every cycle
   succeeded, that is ~407 cycles ≈ **34 hours minimum** of convalescence.

**The restart also put the k3s server into a crash loop**, which it was not in before:

```text
14:32:13 level=fatal msg="failed to start controllers: failed to create new server context: failed to register CRDs: failed to list apiextensions.k8s.io/v1, Kind=CustomResourceDefinition ... stream error: stream ID 27; INTERNAL_ERROR"
14:38:21 level=fatal msg="failed to start controllers: ... failed to register CRDs: failed to list..."
14:44:46 level=fatal msg="failed to start controllers: ... failed to register CRDs: failed to list..."
14:49:23 level=fatal msg="cloud-controller-manager panic: F0920 ... error building co..."
```

`RestartCount` went 0 → 4 in 23 minutes, one fatal every 5–6 minutes, `ExitCode 0`,
`OOMKilled false`. Every incarnation must re-list CRDs during bootstrap; those reads cannot be
served in time by the saturated datastore, so k3s exits fatal before it finishes starting. It gets
exactly one compaction attempt per incarnation, which fails, and then the process dies. The API
does still answer between restarts and all four nodes report `Ready`, so this is a bootstrap loop
rather than an outage — but it is strictly worse than the pre-restart state, where the cluster was
stable and only retention was broken.

**Lesson: a long-running k3s server holding a saturated kine is stable only because it has already
bootstrapped.** Restarting it forfeits that and forces it to re-read the CRD set through the same
bottleneck. Do not restart a k3s server to fix compaction unless the datastore can serve a
bootstrap.

### Revised remedy (again)

A controlled **rebuild from GitOps/Vault** — the path the original 2026-09-09 follow-up
contemplated — is now the indicated fix, not a restart and not waiting. The evidence is that this
database cannot be compacted in place on this hardware.

If a rebuild is not acceptable, the only in-place avenue worth trying is to quiesce churn first so
that a single compaction transaction can finish: stop the ArgoCD application controller and the
agent nodes, give the control plane the datastore to itself, and watch for the first
`COMPACT deleted` line. That is unproven, costs ~34 h at 1000 revisions/cycle, and is the
operator's decision. Raw SQLite retention deletion remains forbidden, and the `profile` and
`pw-profile` directories must not be deleted.
