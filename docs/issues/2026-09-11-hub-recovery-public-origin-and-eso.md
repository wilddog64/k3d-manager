# Hub recovery: missing app registration, Vault ESO policy, and stale tunnel origins

## What was observed

After the controlled K3s server rebuild, the control plane became reachable but
public frontend/Grafana/Keycloak routes returned Cloudflare 502/1033 errors and
the service ApplicationSet generated no shopping-cart workloads.

## Root causes

1. The Argo CD cluster secret labelled `k3d-manager/role=app-cluster` was lost
   during the rebuild. `services-git` therefore generated zero service
   Applications.
2. The restored Vault role `eso-ldap-directory` only had LDAP, Keycloak,
   observability, and platform-ops paths. Application ExternalSecrets failed
   with `could not get secret data from provider`, including `secret/data/github/pat`.
3. The Cloudflare config still pointed frontend to `127.0.0.2:80` and used
   stale dedicated origins. The recovered load-balancer needed Istio's NodePort
   (`192.168.97.5:31284`) rather than the cluster IP from inside serverlb.
4. The payment Java service's existing liveness probe killed it during its
   ~90-second startup; the recovered deployment needed a startup grace probe.

## Recovery actions and evidence

- Recreated the Argo app-cluster registration as `ubuntu-k3s` and regenerated
  service/data Applications.
- Added a scoped `eso-apps` Vault policy for restored application secret
  prefixes and attached it to the ESO Kubernetes role; ExternalSecrets then
  reported `SecretSynced=True`.
- Recreated GHCR pull secrets while ESO reconciled, allowing private images to
  pull.
- Rebuilt the serverlb Nginx upstream to Istio NodePort 31284 and restarted the
  Cloudflare tunnel with current origins.
- Added a payment-service startup probe and restarted affected workers.

Final public probes during recovery:

```
frontend.3ai-talk.org 200
keycloak.3ai-talk.org 302
argocd.3ai-talk.org 200
grafana.3ai-talk.org 200
prometheus.3ai-talk.org 302
https://frontend.3ai-talk.org/api/products 200
https://keycloak.3ai-talk.org/realms/master 200
https://grafana.3ai-talk.org/api/health 200
https://prometheus.3ai-talk.org/-/ready 200
```

## Follow-up

Make the app-cluster registration and Vault ESO policy declarative in the
recovery/bootstrap path, and make Cloudflare origins provider-aware so a
server-container rebuild cannot restore stale loopback addresses.
