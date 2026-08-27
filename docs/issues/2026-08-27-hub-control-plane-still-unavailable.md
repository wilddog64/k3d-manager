# Hub control plane remains unavailable after agent/server restart

## Evidence

The status report showed Prometheus HTTP 502 while other endpoints intermittently
returned 200. Kubernetes inspection found `k3d-k3d-cluster-agent-0` `NotReady`
with `Kubelet stopped posting node status`; Prometheus was stuck `Terminating` on
that node, and kube-prometheus operator/kube-state-metrics were crash-looping.

Restarting `k3d-k3d-cluster-agent-0` and then `k3d-k3d-cluster-server-0` did not
restore the API. Subsequent bounded checks returned:

```text
Unable to connect to the server: context deadline exceeded
```

The server log contained repeated Kine slow-SQL and API handler timeouts, for
example:

```text
http: Handler timeout
Slow SQL ... total time: 1–4s
Housekeeping took longer than expected
```

Container CPU was highly saturated before recovery attempts:

```text
k3d-k3d-cluster-server-0 551.88%
k3d-k3d-cluster-agent-0 297.69%
k3d-k3d-cluster-agent-1 242.76%
k3d-k3d-cluster-agent-2 394.07%
```

## Root cause

The hub k3s control plane/Kine datastore is overloaded or stalled, with the
OrbStack runtime also becoming unresponsive to bounded Docker queries. This is
not a Prometheus-only or tunnel-only failure.

## Follow-up

Recover the OrbStack VM/runtime, then verify the k3s API, all nodes, monitoring
StatefulSets, and public endpoints before rerunning `make status`. Investigate
CPU-heavy workloads and add control-plane resource protection after recovery.
