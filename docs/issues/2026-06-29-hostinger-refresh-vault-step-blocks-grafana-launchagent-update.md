# Issue: Hostinger `make refresh` can fail before Grafana LaunchAgent rewrite

**Found:** 2026-06-29  
**Branch:** `k3d-manager-v1.12.0`

## What was attempted

To apply the Grafana access-layer fix in the supported way, I ran:

```text
$ make refresh CLUSTER_PROVIDER=k3s-hostinger
running under bash version 5.3.15(1)-release
INFO: [k3s-hostinger] Refreshing ubuntu-hostinger kubeconfig + ArgoCD registration…
INFO: [k3s-hostinger] Removed stale ubuntu-hostinger context
INFO: [k3s-hostinger] ubuntu-hostinger merged into ~/.kube/config (current-context preserved: k3d-k3d-cluster)
INFO: [k3s-hostinger] ensured argocd-manager SA/RBAC on ubuntu-hostinger
INFO: [k3s-hostinger] Registering 'ubuntu-hostinger' (https://2.25.146.252:6443) with hub ArgoCD ns cicd...
INFO: [argocd] registering app cluster 'ubuntu-hostinger' -> https://2.25.146.252:6443
secret/cluster-ubuntu-hostinger configured
INFO: [argocd] cluster secret applied — verify with: kubectl get secret cluster-ubuntu-hostinger -n cicd
INFO: [argocd] app-cluster role label set on 'ubuntu-hostinger' (cleared from others)
INFO: [k3s-hostinger] Registered — verify: kubectl get secret cluster-ubuntu-hostinger -n cicd
INFO: [vault] in-cluster profile: configuring app-cluster auth on 'ubuntu-hostinger' Vault
INFO: [vault] configuring app cluster auth at mount: kubernetes-app
Error enabling kubernetes auth: Error making API request.

URL: POST http://127.0.0.1:8200/v1/sys/auth/kubernetes-app
Code: 400. Errors:

* path is already in use at kubernetes-app/
command terminated with exit code 2
ERROR: failed to execute kubectl -n secrets exec -i vault-0 -c vault -- sh -lc VAULT_TOKEN=hvs.REDACTED\ vault\ auth\ enable\ -path=kubernetes-app\ kubernetes: 2
```

## Actual impact

The Grafana LaunchAgent rewrite did not happen through the supported refresh path, because
`_provider_k3s_hostinger_refresh_cluster()` exits on the Vault reconcile failure before reaching
`_hostinger_refresh_access_layer()`.

That left the installed LaunchAgent on this Mac stale:

- `svc/acg-kube-prometheus-stack-grafana`
- `--context ubuntu-hostinger`

So `grafana.3ai-talk.org` kept serving the wrong Grafana instance even though the repo code had
already been fixed.

## Operator workaround used

I rewrote `~/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist` to:

- `svc/kube-prometheus-stack-grafana`
- `--context k3d-k3d-cluster`

Then restarted `com.k3d-manager.grafana-port-forward`. After that:

- `http://127.0.0.1:3001/api/dashboards/uid/argocd-image-updater-hub` returned the dashboard
- `https://grafana.3ai-talk.org/api/dashboards/uid/argocd-image-updater-hub` returned the same
  dashboard

## Recommended follow-up

Make the Vault auth step idempotent enough that `make refresh CLUSTER_PROVIDER=k3s-hostinger`
continues to `_hostinger_refresh_access_layer()` when `kubernetes-app` already exists, or move the
Grafana access-layer refresh ahead of the Vault reconcile so the public path does not stay stale.
