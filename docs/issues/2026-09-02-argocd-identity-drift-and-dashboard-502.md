# ArgoCD identity drift and public observability failures

## Observed

- `shopping-cart-identity` is `OutOfSync/Degraded` with:
  `Service "keycloak" is invalid: spec.ports[2].name: Duplicate value: "http"`.
- The Git-rendered Keycloak Service contains exactly `http:80` and `https:443`.
- The live Service had the legacy Helm shape `http:8080`; replacing it with the
  rendered ports did not clear Argo's cached strategic-merge error.
- Grafana intermittently returns Cloudflare 502 while its local port-forward
  restarts; Grafana also shows a stale “Page not found” dashboard route.
- ArgoCD application comparisons for `kube-prometheus-stack` time out while
  evaluating CRD health.

## Root cause

ArgoCD is replaying a stale strategic merge against a legacy Helm-managed
Keycloak Service and constructs a duplicate port entry. Independently, the
single-node hub API/datastore is saturated, causing port-forward flaps and
comparison timeouts. `make status` is a point-in-time probe and does not detect
these intermittent failures or stale dashboard routes.

## Recovery attempted

The live ArgoCD URL was corrected to the public hostname. The Keycloak Service
was recreated from the Git-rendered manifest and the Application refreshed.
Agents/server were restarted during the control-plane incident. Public checks
temporarily returned 200 before the API load recurred.

## Required durable fixes

1. Perform a controlled ArgoCD `Replace` sync (or equivalent resource recreate)
   for `identity/keycloak` and verify `Synced/Healthy`.
2. Apply hub load-shed/resource-governance changes and identify the workload
   driving the API event storm.
3. Replace stale Grafana dashboard links/UIDs and add sustained public endpoint
   probes to `make status`.
