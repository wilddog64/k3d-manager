# Two-Cluster Infrastructure Plan

## Overview

Split the current single-cluster deployment into two clusters:

- **infra cluster** — OrbStack on m2-air
- **app cluster** — k3s on Ubuntu/Parallels

This separates infrastructure concerns (secrets, identity, CI/CD, observability) from
application workloads (shopping-cart services and data layer).

---

## Cluster Layout

```
infra cluster (OrbStack / m2-air)
├── secrets/          Vault + ESO
├── identity/         OpenLDAP + Keycloak
├── cicd/             Jenkins + Argo CD
├── observability/    Prometheus + Grafana + Loki
└── istio-system/     Istio ingress gateway

app cluster (k3s / Ubuntu / Parallels)
├── shopping-cart/    basket, order, payment, catalog, frontend
├── data/             PostgreSQL, Redis, RabbitMQ
└── observability/    app-side metrics + logging
```

---

## Key Decisions

- Cluster name carries the context — no prefix needed on namespaces
- `istio-system` stays as-is — Istio hardcodes this namespace
- `observability/` exists in both clusters — infra observes infra, app observes apps
- Machines on same WiFi — use `.local` mDNS hostnames, no VPN needed
  (`m2-air.local` for infra cluster, `10.211.55.14` for app cluster)

---

## ESO Cross-Cluster

ESO lives on **app cluster** — pulls secrets from Vault on **infra cluster**:
- App cluster ESO authenticates to Vault via Kubernetes auth method
- Vault addr: `https://m2-air.local:8200` (or NodePort)
- App services get DB credentials, Keycloak client secrets via k8s Secrets

---

## Authentication Re-Architecture

Shopping cart apps currently have no centralised auth. Target state:
- Keycloak (`identity/` on infra cluster) is the OIDC broker
- Apps never touch LDAP directly — LDAP is Keycloak's user store only
- Frontend redirects to Keycloak for login, receives JWT
- Backend services validate Bearer tokens against Keycloak JWKS endpoint
- Keycloak client secrets live in Vault, ESO syncs them to app cluster

---

## CI/CD with Two Clusters

```
Developer pushes code
    ↓
GitHub Actions (CI) — builds image, runs tests, pushes to GHCR,
                      updates image tag in git manifests
    ↓
Argo CD (CD) on infra cluster — detects manifest change,
                                syncs to app cluster
```

Jenkins on infra cluster handles CI as an alternative to GitHub Actions.
Both Jenkins and Argo CD already scaffolded in `cicd/`.

---

## k3d-manager Changes Required

### New deploy targets
- `deploy_infra_cluster` — creates OrbStack cluster, deploys Vault/ESO/LDAP/Keycloak/Jenkins/Argo CD/Istio
- `deploy_app_cluster` — targets k3s/Ubuntu, deploys shopping-cart namespaces + data layer

### New configuration
- `INFRA_CLUSTER_PROVIDER=orbstack`
- `APP_CLUSTER_PROVIDER=k3s`
- `VAULT_ADDR` — accessible from app cluster (NodePort or Istio gateway)

### ESO cross-cluster wiring
- New plugin or extension to `deploy_eso` that configures cross-cluster SecretStore
- App cluster ESO SecretStore points to infra cluster Vault endpoint

---

## Prerequisites Before Starting

- [ ] Current Ubuntu cluster namespaces documented (run `kubectl get ns`)
- [ ] Current running workloads inventoried (run `kubectl get pods -A`)
- [ ] Confirm Vault is accessible from Ubuntu via `m2-air.local:8200` or NodePort
- [ ] Backup any persistent data if needed
- [ ] Delete current cluster on Ubuntu (`k3d-manager destroy_cluster` or `k3s uninstall`)

---

## Implementation Order

1. Document and tear down current Ubuntu cluster
2. Set up infra cluster on OrbStack (already working via k3d-manager)
3. Set up app cluster on Ubuntu k3s
4. Wire ESO cross-cluster (app → infra Vault)
5. Deploy shopping-cart namespaces on app cluster
6. Wire Keycloak OIDC auth for shopping-cart apps
7. Wire Argo CD on infra cluster to sync app cluster

---

## Status

- [ ] Plan documented (this file)
- [ ] Prerequisites checked
- [ ] Implementation started
