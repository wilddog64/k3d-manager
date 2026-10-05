# Issue: hub `agent-0` `k3s agent` grew to 7.8 GB and its kube-proxy stopped syncing

**Date:** 2026-10-05
**Cluster:** hub (`k3d-k3d-cluster`); the node containers started 2026-10-03T15:51Z
**Impact:** every pod started on `agent-0` after about 22:41Z lost Service DNS and ClusterIP
routing. `make up` failed at Step 10 because the ArgoCD controller landed on that node.

## Evidence (read-only, 23:20–23:30Z)

| Node | `k3s agent` VmRSS | Threads | kube-proxy last sync | `kube-dns` DNAT |
|---|---|---|---|---|
| agent-0 | **7,799,948 kB** | 25 | **~35 min old** (`last_queued` current) | **missing** |
| agent-1 | 114,244 kB | 24 | current | `-> 10.42.0.253:53` |
| agent-2 | 113,932 kB | 24 | current | `-> 10.42.0.253:53` |

- `docker stats`: agent-0 at 135% CPU and 7.7 GiB. Inside the node, `top` showed 136 MB free of
  16.4 GB, with a load average of 15.
- On agent-0, `nslookup … 10.43.0.10` (the Service IP) timed out, while `nslookup … 10.42.0.253`
  (the pod IP) answered.
- agent-0's NAT table still routed `argocd-application-controller-metrics` to the deleted pod
  `10.42.0.202`.
- No iptables restore failures were counted. The sync loop was not failing; it had stopped
  running.
- The pods on agent-0 were all small (top: image-updater at 54 Mi). The memory belongs to the agent
  process itself.

## Recovery

The operator restarts the node container:
`docker restart k3d-k3d-cluster-agent-0`. Then confirm:

- `VmRSS` of PID 86 is back near 100 MB
- the `kube-dns` DNAT rule is present on agent-0
- `argocd-application-controller-0` is `2/2`

Watch the host-network pods afterwards (`svclb-*`, node-exporter); see
`docs/bugs/2026-09-29-hostnetwork-pods-keep-stale-ip-after-node-restart.md`.

## Open questions

- **What leaked:** only one of three identical agents grew. Capture the growth rate after the
  restart: VmRSS of PID 86 at intervals over a day. No profile was taken before the restart.
- **Detection:** nothing alerted. A hub rule on kube-proxy sync staleness
  (`time() - kubeproxy_sync_proxy_rules_last_timestamp_seconds > 600`), or on node-process memory,
  would have caught this before `make up` did. Spec it once the growth rate is known, so the
  threshold is grounded.
