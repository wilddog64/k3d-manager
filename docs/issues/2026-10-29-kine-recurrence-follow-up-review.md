# Kine recurrence follow-up review — 2026-10-29

The operator requested review and Luna dispatch if appropriate. A GPT-6-Luna
agent independently reviewed the existing incident and prior readiness report
offline. The 2026-10-28 log confirms a revision-record transaction failure,
but does not establish what ended the transaction. The September high-load,
long-transaction episode is a hypothesis for that earlier occurrence, not proof
of the cause of this one. Kine is bundled in the pinned K3s image; an upstream
fix, matching embedded Kine version and reproducer have not been established.
A source change or version upgrade is therefore not sufficiently scoped yet.
The Hermes sensor detects the failure; it does not repair it.

Recommended follow-up: correlate the failure window with compaction durations,
Slow SQL, CPU/throttling and reconciliation activity if retained; identify the
image digest and embedded Kine version; inspect the matching source and known
fixes, and reproduce the transaction failure in isolation. Gather any further
live diagnostic evidence without restarting K3s or mutating the datastore.
Recovery readiness and authorization remain separate; see the [Luna readiness
review](2026-10-28-hub-kine-recurrence-luna-review.md) and [open bug](../bugs/2026-10-28-hub-kine-compaction-recurred-after-transaction-rollback.md).

## Read-only checks

At `2026-10-29T12:45:22Z` on M4, the following outputs were observed:

```text
$ docker inspect --format '{{.State.Status}} started={{.State.StartedAt}} restarts={{.RestartCount}}' k3d-k3d-cluster-server-0
running started=2026-10-25T12:40:00.428960292Z restarts=0
$ kubectl --context k3d-k3d-cluster get --raw='/readyz'
ok
$ docker exec k3d-k3d-cluster-server-0 sh -c 'stat -c "%n %s" /var/lib/rancher/k3s/server/db/state.db /var/lib/rancher/k3s/server/db/state.db-wal'
/var/lib/rancher/k3s/server/db/state.db 583081984
/var/lib/rancher/k3s/server/db/state.db-wal 78090512
```

A sandboxed Docker log attempt initially returned:

```text
permission denied while trying to connect to the docker API at unix:///Users/cliang/.orbstack/run/docker.sock
```

The approved retry below returned no matching lines, exit 0 from the pipeline:

```text
$ docker logs --since 90m --tail 120000 k3d-k3d-cluster-server-0 2>&1 | rg 'msg="COMPACT deleted|Compact failed' | tail -12
```

This is a bounded search, not proof that no event exists outside the window or
beyond the tail limit. Readiness does not prove compaction or database integrity.
No live recovery, restart, database mutation or code fix was performed. The P2
remains open pending recovery and its required observation and verification.
