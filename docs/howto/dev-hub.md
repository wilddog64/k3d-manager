# Development hub

The development hub is a vCluster named `dev-hub` hosted by the M5 hub. It gives release branches a live place
for checks without promoting their manifests into the hub. It is isolated in host namespace `dev-hub`; do not use
the shared `vclusters` namespace, whose lifecycle helper reconciles other vClusters out of that namespace.

## Start and stop

Run these commands on the hub machine, whose machine role must be `hub`:

```bash
make dev-hub-up
make dev-hub-status
make dev-hub-down
```

`dev-hub-up` applies the `k3dm-dev-preemptible` PriorityClass, namespace quota and limit defaults before creating
the vCluster on local port 11444. It is safe to run again: existing namespace and vCluster are retained, and the
quota and defaults are reconciled. The vCluster kubeconfig is `~/.kube/vclusters/dev-hub.yaml`.

`dev-hub-down` deletes only the vCluster, its host namespace, its local proxy container and its kubeconfig. It
does not run the shared `vcluster_destroy` path, which deregisters resources from hub ArgoCD. The PriorityClass
remains installed and has no effect when no matching pods exist.

## Sync a pushed branch

Push the branch first, then run `make dev-hub-sync` to use the current branch or
`make dev-hub-sync BRANCH=<branch>` to choose one. The command requires the local branch head to match the head
published on `origin`, and refuses `main` and `deploy/hub`. It applies only the `grafana-dashboards-hub`
ApplicationSet with the dev-hub kubeconfig; it never reads the working tree's dashboard files. The in-vCluster
ArgoCD then pulls the dashboards and `k3dm-tests` ConfigMap from that branch. Other hub and app-cluster
ApplicationSets are not part of this workflow.

## Grafana and hub data

`dev-hub-status` prints the port-forward command and URL. Run the command on the hub, then open
`http://127.0.0.1:13000`. Sign in as `admin` with the password stored in the operator's Keychain under service
`k3dm-dev-hub-grafana-admin` and account `k3dm`. Grafana reads the hub Prometheus through a replicated read-only
Service. vCluster's `networking.replicateServices.fromHost` needs a ClusterRole with cluster-wide `get`, `list`
and `watch` on Services and Endpoints so it can discover the named host Service; it does not grant writes.

The Loki panels show no data in this isolated Grafana because the dev hub has no Loki datasource. Dashboard
ConfigMaps are discovered by Grafana's sidecar inside `monitoring`; they are not mounted as volumes or synced to
the host namespace.

## Resource priority and alerts

The host namespace has a 3 GiB memory limit quota, a 1 GiB memory request quota, CPU quotas and a 30 pod cap.
LimitRange supplies small defaults to containers without explicit resources. The vCluster control plane has a
768 MiB memory limit and writes data to a 2 GiB `local-path` volume; its CoreDNS pod is limited to 128 MiB.

Every synced development pod and the control-plane pod use PriorityClass `k3dm-dev-preemptible` (value -100,
`preemptionPolicy: Never`). This lets the scheduler choose hub pods first when priorities differ, and kubelet
eviction can rank development pods lower. PriorityClass does not protect the hub from the kernel OOM killer, and
each k3d node advertises the VM's full memory. The namespace quota and `HubVmMemoryLow` alert are the actual
capacity safeguards. `DevHubNearQuota` warns when measured container working set exceeds 90% of the quota.
Both alerts have warning severity and route to the existing platform warning email receiver, not the
`k3dm-analyze` route.

Trivy excludes both `vclusters` and `dev-hub`: scanner jobs run outside the dev-hub namespace and are not covered
by its resource quota.
