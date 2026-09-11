# Hub post-rebuild verification gaps and recurring Kine compaction stall

## What was observed

Independent verification of the controlled hub rebuild (`c62a0f63`, recorded as
"final hub recovery verification") confirmed the headline recovery claims but
found the closing gate was not actually met.

Confirmed accurate:

- Kine `state.db` fell from 8.3 GiB to 554 MiB (+150 MiB WAL).
- Four nodes `Ready`, 62 pods `Running`, all 14 durable PVCs `Bound`.
- All nine public probes reproduced exactly as recorded (frontend 200,
  keycloak 302, argocd 200, grafana 200, prometheus 302, `/api/products` 200,
  `/realms/master` 200, `/api/health` 200, `/-/ready` 200).
- `scripts/tests/plugins/hub_recovery.bats` passes 10/10; `shellcheck -x`
  reports no findings on `scripts/plugins/hub_recovery.sh`.

## Finding 1 - Kine compaction is stalled again (primary)

The rebuild reset the symptom, not the cause. Compaction walked 1000-revision
batches from `compactRev=0` to `12000`, then stalled permanently:

```text
11:30:56 COMPACT compactRev=12000 targetCompactRev=13000 currentRev=91567
11:31:04 COMPACT compacted from 0 to 12000 in 12 transactions over 22.661s
11:31:41 ERROR Compact failed: failed to record compact revision:
         sql: transaction has already been committed or rolled back
11:35:45 COMPACT compactRev=12000 targetCompactRev=13000 currentRev=92579
11:35:52 ERROR Compact failed: failed to record compact revision: ...
```

`11:35:52` is the last compaction line of any kind. No further attempt occurred
in the following 2h17m, so the compaction loop is not merely failing - it has
stopped retrying. `compactRev` is pinned at `12000` against a `currentRev` of
`92579`, leaving roughly 80,000 revisions of unreclaimable history.

Contributing load at the time of observation:

- `k3d-k3d-cluster-server-0` at 314% CPU; host load average 15.84.
- 133 `Slow SQL` entries in a 30-minute window.
- 9 of 23 Argo CD Applications `Degraded` / `Progressing` / `OutOfSync`,
  producing continuous reconcile churn and therefore continuous revisions.

This is the same failure described in
`docs/bugs/2026-09-09-hub-kine-compaction-stall.md`, whose stated follow-up gate
was "confirm regular K3s `COMPACT` events after churn stops". That gate is not
met. Batches that completed under low load took 0.16-4.6s; the `12000-13000`
batch exceeds the transaction window on a CPU-starved host, so every retry
restarts at the identical batch and fails identically.

## Finding 2 - The rebuilt server is outside k3d management

```text
$ k3d cluster list
NAME          SERVERS   AGENTS   LOADBALANCER
k3d-cluster   0/0       3/3      true
```

The server container reports hostname `457182e619fc` and carries no
`k3d.cluster` or `k3d.role` labels, while every agent carries both. It was
recreated outside k3d, so k3d lifecycle operations cannot see or manage the
control-plane node.

## Finding 3 - Missing mount propagation breaks two node-local workloads

A direct consequence of Finding 2. The hand-built server lacks the shared mount
propagation k3d normally configures:

- `istio-system/istio-cni-node`: `path "/var/run/netns" is mounted on
  "/var/run" but it is not a shared or slave mount` - 526 failure events.
- `monitoring/kube-prometheus-stack-prometheus-node-exporter`: `path "/" is
  mounted on "/" but it is not a shared or slave mount` - 538 failure events.

Both sit in `CreateContainerError` indefinitely, so Istio CNI and node metrics
are absent on the control-plane node.

## Finding 4 - Ingress load-balancer pods cannot schedule

Four `svclb-istio-ingressgateway` pods are `Pending`:
`0/4 nodes are available: 1 node(s) didn't have free ports for the requested
pod ports, 3 node(s) didn't satisfy plugin(s) [NodeAffinity]`. Two
`keycloak-realm-reconcile` pods are in `Error`.

## Finding 5 - The new recovery plugin has no CI coverage

`.github/workflows/ci.yml` enumerates its BATS targets explicitly and did not
include `scripts/tests/plugins/hub_recovery.bats`. The suite therefore only ran
locally and could regress without any CI signal.

## Finding 6 - Confusing registration name

The recovery note records the Argo CD app-cluster registration recreated as
`ubuntu-k3s`, which is the dead/renamed AWS context name, for what is the local
hub. This is cosmetic but misleading during an incident.

## Finding 7 - The Kine sensor cannot detect a compaction stall (root cause of the blind spot)

`bin/k3dm-hermes` computed the compaction signal with a bare substring test:

```python
"compaction_recent": "compact" in text.lower(),
```

Every Kine `Slow SQL` line embeds the literal column name `compact_rev_key`, so
that substring is present precisely when compaction has stalled and Slow SQL is
spiking. Measured against a 20-minute live window during the stall:

```text
slow_sql_count                  = 132
'compact' substring matches     = 107   <- sensor read this as healthy
real compaction progress events = 0
```

The sensor's degraded rule is `db_bytes >= max_db_bytes or (slow_sql > 0 and not
compacting)`. Because `compacting` was always `True`, the stall branch was
unreachable and only the 8 GiB size threshold could ever fire. This is why
Hermes stayed silent through a 2h17m compaction outage at 0.7 GiB.

The unit tests did not catch it because they inject the probe payload directly
and never exercise the log parsing.

## Finding 8 - R5 cannot fire on a compaction stall

Independently of Finding 7, `_r5_precondition` requires `stale_acg_registration
is True` **and** `state_db_bytes >= 8 GiB`. Neither holds in this recurrence
(stale registration is absent; the database is 0.7 GiB). Even with the sensor
corrected, the circuit breaker would not engage on a compaction stall alone.
This is left unchanged deliberately - R5 scales the hub Argo CD application
controller to zero, so widening an auto-executing actuator's trigger is an
owner decision, not a drive-by fix.

## Finding 9 - Vestigial probe command

The sensor passes `bin/k3dm-hub-datastore-status` as its command, but that
script exists on no branch and has never been committed. `_datastore_run`
ignores the argument and probes inline, so nothing breaks today, but any runner
that honoured the command would fail closed.

## Fix

- Finding 5 is fixed by adding the suite to the CI BATS list.
- Finding 7 is fixed by `kine_log_signals()` in `scripts/lib/hermes/sensors.py`,
  which matches the K3s event markers (`COMPACT compacted from`, `COMPACT
  deleted`) instead of the bare substring, and additionally surfaces
  `compaction_failed` from `Compact failed` lines. The sensor now treats a
  reported compaction failure as degraded regardless of database size. Two
  regression tests cover the parsing directly. Verified against the live
  20-minute window: the old logic returned `compaction_recent=True`, the new
  logic returns `False` and the sensor reaches `degraded` after debounce.
- Finding 1 requires reducing control-plane CPU pressure so the stalled batch
  can complete inside its transaction window, then restarting the K3s server to
  revive the stopped compaction loop, then confirming `compactRev` advances past
  `12000`. Raw SQLite retention deletion remains prohibited.
- Findings 2, 3 and 4 share a root cause and should be resolved together by
  re-adopting the control-plane node under k3d with correct mount propagation.

## Recovery outcome (2026-09-11)

Finding 1 is resolved. Two levers were applied in order.

**Lever 1 - pause the Argo CD application controller** (`scale
statefulset/argocd-application-controller --replicas=0`, `cicd`). This relieved
the pressure but did not revive compaction:

| Metric | Before | After |
| --- | --- | --- |
| Revision churn | ~1000 / 5 min | 557 / 5 min |
| Slow SQL | 133 / 30 min | ~0 |
| Load average | ~17 | 9.7 |
| `state.db` | growing | stable, then slow creep |
| Real compaction events | 0 | 0 |

Twelve minutes of sampling produced zero compaction events, confirming a dead
compaction goroutine rather than a slow one. Note Argo CD accounted for only
~45% of churn; the 557/5min remainder is ordinary baseline (lease renewals,
kubelet status) and is not pathological. Churn was never the real problem -
nothing was being reclaimed.

**Lever 2 - restart the K3s server.** `docker restart
k3d-k3d-cluster-server-0` at 14:46:33 (safe: `AutoRemove=false`,
`RestartPolicy=unless-stopped`). K3s restarted cleanly, Kine came up, apiserver
`/readyz` passed in ~30s, all four nodes returned `Ready`.

Compaction revived immediately and cleared the entire backlog:

```text
14:51:52 COMPACT deleted 1001 rows ... - compacted to 46000/121724
14:51:53 COMPACT deleted 998 rows  ... - compacted to 50000/121732
         ... compacted to 120613/121763
```

`compactRev` moved from `12000` - where it had been pinned for 3h20m - to
`120613`, a normal small window behind `currentRev` `121763`, with **zero**
`Compact failed` events. The Argo CD controller was then restored to
`replicas=1` and compaction remained healthy with it running.

`state.db` went 618 MiB -> 595 MiB and the WAL 150 MiB -> 59 MiB. The file does
not shrink further without an offline `VACUUM`, which is not required: freed
pages are reused, and the runaway growth has stopped.

Post-recovery: 7 of 9 public probes green. The two `prometheus` 502s are the
expected consequence of `make monitoring-pause` still being in effect
(Prometheus is scaled to zero); reverse with `make monitoring-resume`. Load
fell from ~17 to 11.2.

Findings 2, 3, 4 and 6 remain open and were not addressed by this recovery.

## Findings 2, 3 and 4 resolved (2026-09-11)

The control-plane node was re-adopted under k3d per
`docs/bugs/2026-09-11-hub-control-plane-readoption.md`, with one improvement on
the written plan: **the container hostname was deliberately kept as
`457182e619fc`**. k3d identifies nodes by label and the agents reach the server
by container name, both already correct, so only the hostname was wrong. Keeping
it meant the Kubernetes node name never changed and the three PVs pinned to it
were never stranded - removing the plan's blocking constraint entirely. No PV
repin or workload drain was needed.

The container was recreated with the full k3d label set, the k3d entrypoint, the
existing data volume, and `--disable=traefik`, then the Traefik HelmChart CRs
were deleted so the helm controller uninstalled the release.

Acceptance, all met:

```text
k3d:        SERVERS 1/1  AGENTS 3/3      (was SERVERS 0/0)
mount:      shared:272                   (was private)
nodes:      4/4 Ready
PVCs:       14/14 Bound
pods:       57 Running, 0 CreateContainerError, 0 Pending
compaction: 2 successes, 0 failures
probes:     7/9 green (the two prometheus 502s are `make monitoring-pause`)
```

`istio-ingressgateway` now holds a real EXTERNAL-IP on all four node addresses,
and all four `svclb-istio-ingressgateway` pods are `Running`.

### Execution finding - the k3d entrypoint is not in the stock image

The first recreate failed with exit 127 because `/bin/k3d-entrypoint.sh` does
**not** exist in `rancher/k3s:v1.32.0-k3s1`; k3d writes the entrypoint scripts
into the container at creation time. Recovery was to `docker cp` the four
`k3d-entrypoint-*.sh` scripts from a live agent into the `Created` container
before starting it.

This is almost certainly the original defect: whoever rebuilt the server by hand
used the stock image with `Entrypoint=/bin/k3s`, which skips
`k3d-entrypoint-mounts.sh` - literally `mount --make-rshared /` - and that single
omission produced Finding 3. Any future manual node build must inject these
scripts or reuse k3d's own creation path.

A second process note: the failing `docker run` had its output suppressed with
`>/dev/null 2>&1`, so the failure was silent and the cluster sat with no server
container while the cause was diagnosed. Never suppress stderr on a destructive
step.

## Follow-up

Treat the recovery as open, not closed. A closing verification note must assert
the follow-up gate of the incident it closes; here the gate was restated but
never measured.
