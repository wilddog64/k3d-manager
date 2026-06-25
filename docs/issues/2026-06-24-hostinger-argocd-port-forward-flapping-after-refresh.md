# Issue: Hostinger `make refresh` still left `localhost:8080` flapping after restart

**Date:** 2026-06-24  
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`  
**Area:** `scripts/lib/providers/k3s-hostinger.sh`, `scripts/etc/argocd/port-forward-wrapper.sh.tmpl`

## What was tested

I ran the live Hostinger refresh path and then checked the local ArgoCD listener:

```bash
make refresh CLUSTER_PROVIDER=k3s-hostinger
curl -I --max-time 5 http://localhost:8080/healthz
```

## Actual output

The refresh completed, but the ArgoCD port-forward kept cycling through bind conflicts:

```text
INFO: [k3s-hostinger] Refreshing ubuntu-hostinger kubeconfig + ArgoCD registration…
INFO: [k3s-hostinger] Removed stale ubuntu-hostinger context
INFO: [k3s-hostinger] ubuntu-hostinger merged into ~/.kube/config (current-context preserved: k3d-k3d-cluster)
INFO: [k3s-hostinger] Registering 'ubuntu-hostinger' (https://2.25.146.252:6443) with hub ArgoCD ns cicd...
secret/cluster-ubuntu-hostinger configured
INFO: [k3s-hostinger] Registered — verify: kubectl get secret cluster-ubuntu-hostinger -n cicd
INFO: [k3s-hostinger] Refreshing local access layer listeners...
INFO: [k3s-hostinger] Port 8080 is in use — killing stale ArgoCD port-forward listener(s)...
INFO: [k3s-hostinger] launchd com.k3d-manager.argocd-port-forward: restarted
INFO: [k3s-hostinger] launchd com.k3d-manager.argocd-browser-https: restarted
INFO: [k3s-hostinger] launchd com.k3d-manager.keycloak-browser-http: restarted
INFO: [k3s-hostinger] launchd com.k3d-manager.frontend-browser-http: restarted
INFO: [k3s-hostinger] launchd com.k3d-manager.grafana-port-forward: restarted
INFO: [k3s-hostinger] Refresh complete — ubuntu-hostinger reachable
__WEBHOOK_SUCCESS__
```

The local listener log showed repeated `8080` bind conflicts:

```text
[argocd-pf] healthz reachable — monitoring backend availability
Handling connection for 8080
Unable to listen on port 8080: Listeners failed to create with the following errors: [unable to create listener: Error listen tcp4 127.0.0.1:8080: bind: address already in use unable to create listener: Error listen tcp6 [::1]:8080: bind: address already in use]
error: unable to listen on any of the requested ports: [{8080 8080}]
```

The direct health check still failed during the flap:

```text
curl: (7) Failed to connect to localhost port 8080 after 0 ms: Couldn't connect to server
```

## Root cause

The Hostinger refresh path was clearing `8080`, but there was still a stale
`~/.local/share/k3d-manager/bin/argocd-port-forward.sh` wrapper process running outside the
current launchd job. That orphan wrapper kept respawning `kubectl port-forward` on `8080`, so
the freshly restarted `com.k3d-manager.argocd-port-forward` agent could bind briefly, lose the
port again, and fall back into the same bind-conflict cycle.

## Follow-up

- Kill stale `argocd-port-forward.sh` wrapper processes before restarting the Hostinger launchd job.
- Keep the fix portable across the shared ArgoCD wrapper and the Hostinger provider path.
- Re-run `make refresh CLUSTER_PROVIDER=k3s-hostinger` and confirm `curl -I http://localhost:8080/healthz` succeeds after the restart settles.
