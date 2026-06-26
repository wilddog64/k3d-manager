# Bug: `make status` reports sandbox-only smoke results on Hostinger

**Branch:** `k3d-manager-v1.7.1`
**Files:** `bin/cluster-status`, `bin/k3dm-webhook`, `scripts/lib/provider.sh`

## Symptom

Running `make status` against the Hostinger app cluster shows a mixed report:

```text
=== Service Health ===
  ✅ ArgoCD: HTTP 200
  ❌ Frontend: <urlopen error [Errno 61] Connection refused>
  ✅ Keycloak: HTTP 200
  ✅ Prometheus: HTTP 200
  ✅ Grafana: HTTP 200
  ❌ Pushgateway: <urlopen error [Errno 61] Connection refused>
  ❌ Product images: <urlopen error [Errno 61] Connection refused>
  ✅ ESO ClusterSecretStore: Ready=True
  ✅ ESO ExternalSecrets: 5/5 synced
  ❌ Data layer: 4 not ready: postgresql-orders, postgresql-payment
```

The report is misleading because the Hostinger cluster does not use the same local
ACG endpoints for frontend/keycloak/data-layer probing.

## Root Cause

The webhook health probe still assumed the ACG topology unless the caller explicitly
passed a provider through to `/api/v1/health`. The old smoke path also mixed local
`*.shopping-cart.local` URLs with Hostinger public URLs, so Hostinger runs inherited
the sandbox probe surface.

## Fix

- `bin/cluster-status` now passes `provider=<current provider>` to `/api/v1/health`.
- `bin/k3dm-webhook` resolves the provider before building smoke checks and uses:
  - `frontend.3ai-talk.org` for Hostinger frontend checks
  - `keycloak.3ai-talk.org` for Hostinger Keycloak checks
  - provider-specific app cluster context for the data-layer readiness probe
- `scripts/lib/provider.sh` and `bin/k3dm-webhook` now accept the `k3s-hostiger`
  typo alias and normalize it to `k3s-hostinger`.

## Follow-up

If Hostinger still reports unhealthy services after this change, the failure is in
the cluster itself rather than the status probe wiring.
