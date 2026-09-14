# Re-adopt the hub control-plane node under k3d

## Problem

Findings 2, 3 and 4 of
`docs/issues/2026-09-11-hub-post-rebuild-verification-gaps.md` are one defect
with three symptoms. During the controlled rebuild the K3s server container was
recreated by hand rather than through the repository's own creation path, so it
diverges from every other node in three ways:

| Property | Agents (correct) | Server (drifted) |
| --- | --- | --- |
| Hostname | `k3d-k3d-cluster-agent-N` | `457182e619fc` |
| k3d labels | `k3d.cluster`, `k3d.role`, ... | none |
| Root mount propagation | `shared:166` | private (no `shared:` tag) |
| K3s args | per `cluster.yaml.tmpl` | `server --tls-san ... --tls-san ...` |

Consequences:

- **Finding 2** - `k3d cluster list` reports `SERVERS 0/0`. k3d cannot see or
  manage the control-plane node, so k3d lifecycle operations are broken.
- **Finding 3** - without shared propagation, `istio-cni-node` fails with
  `path "/var/run/netns" ... is not a shared or slave mount` and
  `node-exporter` with `path "/" ... is not a shared or slave mount`. Both sit
  in `CreateContainerError` permanently on that node.
- **Finding 4** - the server was started without `--disable=traefik`, which
  `scripts/etc/cluster.yaml.tmpl:23` and `scripts/etc/k3s/config.yaml.tmpl:14`
  both mandate. k3s therefore deployed Traefik, whose `svclb-traefik-7601dc13`
  DaemonSet holds host ports 80 and 443 on all four nodes. The Istio
  `svclb-istio-ingressgateway` DaemonSet wants 15021/80/443 and can never
  schedule, leaving four pods `Pending` and `istio-ingressgateway` with
  `EXTERNAL-IP: <pending>`.

Traefik is confirmed unused: zero `Ingress` objects, zero `IngressRoute` CRs,
and the tunnel path is `serverlb` -> Istio NodePorts (80 -> 31284,
443 -> 30242), not Traefik.

## Why the piecemeal fixes were rejected

`mount --make-rshared /` and writing `/etc/rancher/k3s/config.yaml` inside the
running container both work, but they live in the container's writable layer.
They evaporate on any container recreation and leave the node still invisible to
k3d. Fixing the cause once is correct; three `docker exec` patches are not.

## Blocking constraint - PV node affinity

**Three PersistentVolumes are pinned to the drifted node name** and will be
stranded the moment the node is re-adopted under its correct hostname:

```text
457182e619fc:
   shopping-cart-data/data-rabbitmq-0
   identity/postgres-keycloak-pvc
   trivy-system/data-trivy-server-0
```

`local-path` PVs carry `nodeAffinity` on `kubernetes.io/hostname`. Renaming the
node from `457182e619fc` to `k3d-k3d-cluster-server-0` makes these three match
no node, so their pods become unschedulable. This is the same class of trap
`scripts/plugins/hub_recovery.sh` was written to avoid, and it must be handled
inside the change window, not discovered after it.

## Plan

Rungs are ordered; each gate must pass before the next.

1. **Capture.** Record the server container's full inspect output, the k3d label
   set from `k3d-k3d-cluster-agent-0`, the cluster token, network name and IP
   range, and the current PV -> node map. Store under the incident directory.
2. **Back up.** Take an offline-consistent copy of the Kine datastore after
   quiescing, per the retained procedure in
   `docs/plans/v1.33.0-hub-kine-controlled-rebuild.md`. Do not use an online
   stream; that produced an invalid archive on 2026-09-09.
3. **Relocate or repin the three affected claims.** Either drain those workloads
   to agents before the rename, or patch each PV's `nodeAffinity` to the new
   hostname while the workloads are stopped. Verify all three `Bound` and their
   pods `Running` afterwards.
4. **Recreate the server container** with the correct hostname, the full k3d
   label set, shared mount propagation, the existing data volume
   `k3d-k3d-cluster-recovery-server-data`, and the repository's K3s args
   including `--disable=traefik --disable=servicelb`.
5. **Remove the Traefik remnants** - delete the `traefik` and `traefik-crd`
   HelmChart CRs in `kube-system` so the helm controller uninstalls the release
   and `svclb-traefik-7601dc13` releases ports 80 and 443.

## Acceptance

- `k3d cluster list` reports `SERVERS 1/1`.
- The server's root mount shows a `shared:` tag, matching the agents.
- `istio-cni-node` and `node-exporter` are `Running` on the control-plane node.
- All four `svclb-istio-ingressgateway` pods schedule and
  `istio-ingressgateway` reports a real `EXTERNAL-IP`.
- All 14 PVCs `Bound`; the three formerly pinned claims have `Running` pods.
- All nine public probes return their recorded codes.
- Kine compaction continues to advance, with `compactRev` tracking `currentRev`.

## Not in scope

Finding 6 (the Argo CD registration named `ubuntu-k3s` for the local hub) is
deliberately excluded. Twelve Applications reference `destination.name:
ubuntu-k3s` and ApplicationSets carry 16 more references, so the rename is a
coordinated GitOps change requiring an ApplicationSet reapply, and it would
churn 28 Application objects. Sequence it into this same maintenance window only
after compaction has been stable, or run it as its own change.
