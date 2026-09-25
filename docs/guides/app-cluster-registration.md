# App-cluster registration

A hub app-cluster registration is the ArgoCD cluster Secret in the `cicd` namespace with the
`k3d-manager/role=app-cluster` label. Four ApplicationSets select that label, so the Secret is
load-bearing state, not bookkeeping: removing it can remove the Applications that manage the
cluster's workloads.

## Inventory and creation paths

The single declaration of remotely registered app clusters is
[`scripts/etc/argocd/app-clusters.tsv`](../../scripts/etc/argocd/app-clusters.tsv). Its rows contain
the kubeconfig context, hub Secret name, and provider. The hub's own in-cluster registration is
not in this file because the rebuild creates it directly.

A registration is created in three ways:

- The rebuild's own `register_app_cluster` call creates the in-cluster registration.
- The S3 reconcile `argocd_reconcile_app_cluster_registrations` checks every inventory row and
  calls the existing registration-only provider action for a missing Secret.
- An operator can run `make refresh-registration CLUSTER_PROVIDER=k3s-hostinger` by hand.

The reconcile invokes the dispatcher as a child process and remains additive. If a remote cluster
is unavailable, it reports the gap but does not abort the rebuild.

## Why additive-only matters

Exclusive mode strips `k3d-manager/role=app-cluster` from the other registration. The four
ApplicationSets then stop selecting it and can prune its Applications. In the hub-as-app-cluster
topology that would take down the shopping cart served by the public edge, so reconciliation and
manual registration must remain additive-only.

## Triage

| Symptom | Check |
| --- | --- |
| Hostinger workloads are unmanaged | Check the hub registration Secret and its `app-cluster` label, not the workload first. |
| All `ubuntu-hostinger-*` Applications are gone | Check whether the remotely registered app cluster is missing from the hub. |
| A CronJob logs `secrets "cluster-ubuntu-hostinger" not found` | Check the registration Secret; the workload is downstream of that missing state. |

`make status` now prints `REGISTRATION GAP:` when a cluster has a kubeconfig context locally but
no corresponding hub Secret. Run the command shown on the next line, for example:

```bash
make refresh-registration CLUSTER_PROVIDER=k3s-hostinger
```

## History

The original loss and safe restoration are documented in
[`2026-09-13-hostinger-app-cluster-registration-lost-orphaned-workloads.md`](../bugs/2026-09-13-hostinger-app-cluster-registration-lost-orphaned-workloads.md).
The repeated loss during hub rebuilds and the durable reconcile fix are documented in
[`2026-09-23-hostinger-registration-does-not-survive-a-hub-rebuild.md`](../bugs/2026-09-23-hostinger-registration-does-not-survive-a-hub-rebuild.md).
