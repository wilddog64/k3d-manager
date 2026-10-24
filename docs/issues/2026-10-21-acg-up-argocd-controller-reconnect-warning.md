# ACG `make up` continues after ArgoCD controller reconnect timeout

**Date:** 2026-10-21  
**Type:** Unexpected live behavior / follow-up investigation  
**Status:** Open — bring-up completed, but controller reconnect warning is unexplained

## What was observed

During the operator-run `make up CLUSTER_PROVIDER=k3s-aws`, ArgoCD registered
`ubuntu-k3s` but its application controller did not report reconnecting within
the 120-second wait. The script warned and continued. The operator later
confirmed the complete `make up` run finished. No follow-up diagnosis or runtime
mutation was performed by Codex.

## Captured terminal output

The following lines are verbatim from the inspected tmux pane (credentials and
secret names redacted):

```text
INFO: [acg-up] ArgoCD cluster registered: ubuntu-k3s → https://host.k3d.internal:16443
INFO: [acg-up] Reconciling other app-cluster registrations (additive)...
INFO: [argocd] ubuntu-hostinger: already registered (cicd/cluster-ubuntu-hostinger)
INFO: [acg-up] Waiting for ArgoCD controller to reconnect to ubuntu-k3s (max 120s)...
INFO: [acg-up] ArgoCD controller not yet connected to ubuntu-k3s — waiting...
WARN: [acg-up] ArgoCD controller did not reconnect to ubuntu-k3s within 120s — proceeding anyway
INFO: [acg-up] argocd-redis secret exists on ubuntu-k3s
INFO: [acg-up] Step 10b/14 — Deploying shopping-cart data layer (PostgreSQL, Redis, RabbitMQ)...
INFO: [acg-up] data-layer StatefulSets already ready on ubuntu-k3s — writing checkpoint and skipping sync
INFO: [acg-up] Step 10c/14 — Deploying identity stack (Keycloak) via ArgoCD...
INFO: [acg-up] LDAP group sync complete
INFO: [acg-up] Step 10f/14 — Wiring ArgoCD SSO (Keycloak VirtualService + argocd-cm + secret [REDACTED]
deployment.apps/argocd-server restarted
Waiting for deployment spec update to be observed...
Waiting for deployment "argocd-server" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "argocd-server" rollout to finish: 1 old replicas are pending termination...
INFO: [argocd] platform-ops deployed — CVE scan: 1st+15th, expiry check: every 30m
```

The pane returned to the operator's zsh prompt after the deploy output; the
operator confirmed `make up completed`. This excerpt is not the full command
transcript; only the relevant visible lines were retained, with sensitive values
redacted.

## Recommended follow-up

If this warning recurs, inspect the ArgoCD controller logs and the registered
cluster connection state immediately after the wait. Determine why the controller
does not acknowledge the new cluster within 120 seconds, and whether proceeding
can leave applications unsynced. Do not infer a failed deployment from this
warning alone: this run continued through later setup and completed.
