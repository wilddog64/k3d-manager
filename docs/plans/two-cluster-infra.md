# Two-Cluster Infrastructure Plan

_Established: 2026-02-27 | Updated: 2026-02-28 (Codex implementation spec)_

---

## Current State (2026-02-28)

Both clusters are now live:

| Cluster | Provider | Context | State |
|---|---|---|---|
| Infra | k3d (OrbStack) | `k3d-k3d-test-orbstack-exists` | Vault ✅ ESO ✅ Jenkins ✅ OpenLDAP ✅ Istio ✅ |
| App | k3s (Ubuntu, 10.211.55.14) | SSH: `ssh ubuntu` | Istio ✅ — app layer not yet deployed |

**Next step:** Codex implements k3d-manager changes → Claude destroys + redeploys infra cluster with new namespaces → Claude deploys app layer on Ubuntu.

---

## Target Cluster Layout

```
infra cluster (k3d / OrbStack / m2-air)
├── secrets/          Vault + ESO
├── identity/         OpenLDAP + Keycloak
├── cicd/             Jenkins + Argo CD
├── observability/    Prometheus + Grafana + Loki
└── istio-system/     Istio (hardcoded — do not rename)

app cluster (k3s / Ubuntu / 10.211.55.14)
├── shopping-cart-apps/   basket, order, payment, catalog, frontend
├── shopping-cart-data/   PostgreSQL ×2, Redis ×2, RabbitMQ
└── observability/        app-side Prometheus + Grafana
```

---

## Codex Implementation Spec

> **Codex:** implement all items in this section on branch `feature/two-cluster-infra`.
> Do not break single-cluster mode — all changes must be backwards-compatible via env vars.

### 1. Namespace Rename — vars files (change defaults)

| File | Current | Change to |
|---|---|---|
| `scripts/etc/vault/vars.sh` | (no namespace var) | Add: `export VAULT_NS="${VAULT_NS:-secrets}"` |
| `scripts/etc/jenkins/vars.sh` | `JENKINS_NAMESPACE="jenkins"` | `JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-cicd}"` |
| `scripts/etc/ldap/vars.sh` | `LDAP_NAMESPACE="${LDAP_NAMESPACE:-directory}"` | `LDAP_NAMESPACE="${LDAP_NAMESPACE:-identity}"` |
| `scripts/etc/argocd/vars.sh` | `ARGOCD_NAMESPACE="argocd"` | `ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-cicd}"` |
| `scripts/etc/ldap/ldap-password-rotator.sh` | `VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"` | `VAULT_NAMESPACE="${VAULT_NAMESPACE:-secrets}"` |

### 2. Namespace Rename — plugin code (change hardcoded defaults)

**`scripts/plugins/vault.sh`:**
- Lines with `VAULT_NS_DEFAULT:-vault` → change default to `secrets`
- Lines with `eso_ns="${4:-external-secrets}"` → change default to `secrets`
- Lines with `service_namespace="${4:-external-secrets}"` → change default to `secrets`

**`scripts/lib/test.sh`:**
- All `-n jenkins` → `-n "${JENKINS_NAMESPACE:-cicd}"`
- All `-n vault` → `-n "${VAULT_NS:-secrets}"`
- All hardcoded `vault-0` pod lookups: wrap with `${VAULT_NS:-secrets}`

**`scripts/ci/check_cluster_health.sh`:**
- `namespace="${1:-vault}"` → `namespace="${1:-${VAULT_NS:-secrets}}"`

**`scripts/tests/run-cert-rotation-test.sh`:**
- All `-n jenkins` → `-n "${JENKINS_NAMESPACE:-cicd}"`

**`scripts/lib/dirservices/openldap.sh`:**
- `namespace="${1:-${LDAP_NAMESPACE:-directory}}"` → `namespace="${1:-${LDAP_NAMESPACE:-identity}}"`

### 3. New env var: `CLUSTER_ROLE`

Add to `scripts/k3d-manager` dispatcher and document in help text:

```
CLUSTER_ROLE=infra   (default) — deploy full infra stack: Vault, ESO, Jenkins, ArgoCD, LDAP, Istio
CLUSTER_ROLE=app     — deploy app stack only: ESO (remote Vault), shopping-cart-data, shopping-cart-apps
```

When `CLUSTER_ROLE=app`:
- Skip: `deploy_vault`, `deploy_jenkins`, `deploy_ldap`, `deploy_argocd`
- Run: `deploy_eso` (with remote Vault config), then shopping-cart manifests

### 4. Remote Vault support for ESO (`REMOTE_VAULT_ADDR`)

New env var: `REMOTE_VAULT_ADDR` — when set, ESO SecretStore points to external Vault.

**In `scripts/plugins/eso.sh` or the ESO SecretStore template:**

```yaml
# When REMOTE_VAULT_ADDR is set:
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: shopping-cart-data
spec:
  provider:
    vault:
      server: "${REMOTE_VAULT_ADDR}"   # e.g. https://10.211.55.3:8200
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes-app"  # separate mount for app cluster
          role: "eso-app-cluster"
          serviceAccountRef:
            name: external-secrets-sa
```

**Vault side (run on infra cluster after app cluster is up):**
```bash
# Enable a second k8s auth mount for the app cluster
vault auth enable -path=kubernetes-app kubernetes
vault write auth/kubernetes-app/config \
  kubernetes_host="https://10.211.55.14:6443" \
  kubernetes_ca_cert=@/tmp/app-cluster-ca.crt

# Create role for ESO on app cluster
vault write auth/kubernetes-app/role/eso-app-cluster \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=eso-policy \
  ttl=1h
```

Add helper function `_eso_configure_remote_vault` to `scripts/plugins/eso.sh`.

### 5. Cluster naming

Current infra cluster name `k3d-k3d-test-orbstack-exists` is a leftover test name.
When Claude redeploys the infra cluster:
- New cluster name: `automation` (matches original `k3d-automation` intent)
- Context will be: `k3d-automation`

No Codex change needed — user sets `CLUSTER_NAME=automation` at deploy time.

### 6. ESO namespace consolidation

`vault` + `external-secrets` → both move to `secrets` namespace.
In the new layout, ESO is deployed into the `secrets` namespace alongside Vault.

Update any ESO Helm values or namespace references in:
- `scripts/plugins/eso.sh`
- Any ESO SecretStore / ClusterSecretStore templates

---

## What Codex Must NOT Break

- Single-cluster mode (no `CLUSTER_ROLE` set) must still work end-to-end
- All existing CLI flags (`--enable-vault`, `--enable-ldap`, etc.) must still work
- Env var overrides must still take precedence (e.g. `LDAP_NAMESPACE=my-ns ./k3d-manager deploy_ldap`)
- CI tests (`test_vault`, `test_eso`, `test_istio`) must pass with new namespace defaults

---

## Key Decisions

- `istio-system` stays — Istio hardcodes this namespace
- `observability/` exists in both clusters — infra observes infra, app observes apps
- Jenkins + ArgoCD share `cicd` namespace (no resource name conflicts)
- Vault + ESO share `secrets` namespace
- OpenLDAP + Keycloak share `identity` namespace (Keycloak not yet deployed — add during infra redeploy)

---

## ESO Cross-Cluster Architecture

```
App cluster (Ubuntu k3s)                Infra cluster (k3d OrbStack)
─────────────────────────               ──────────────────────────────
ESO (secrets ns)                        Vault (secrets ns)
  └── SecretStore                         └── auth/kubernetes-app/
       └── vault.server=                       └── role: eso-app-cluster
            https://10.211.55.3:8200
            auth.kubernetes.mount=
              kubernetes-app
```

App cluster ESO authenticates to Vault using its own ServiceAccount JWT.
Vault validates the JWT against the app cluster's k8s API server.

---

## Deployment Order (after Codex lands)

```
1. Claude: destroy current infra cluster (k3d-k3d-test-orbstack-exists)
2. Claude: redeploy infra cluster — CLUSTER_NAME=automation CLUSTER_ROLE=infra
           → secrets/ (Vault + ESO)
           → identity/ (OpenLDAP + Keycloak)
           → cicd/ (Jenkins + ArgoCD)
           → istio-system/
3. Claude: configure Vault kubernetes-app auth mount for app cluster
4. Claude: deploy app layer — CLUSTER_ROLE=app REMOTE_VAULT_ADDR=https://10.211.55.3:8200
           → ESO (pointing to infra Vault)
           → shopping-cart-data/
           → shopping-cart-apps/
```

---

## Status

- [x] Plan documented
- [x] Both clusters live (infra k3d OrbStack, app Ubuntu k3s fresh)
- [x] SSH agent forwarding fixed on Ubuntu
- [ ] **Codex: namespace rename + CLUSTER_ROLE + remote Vault ESO** ← current task
- [ ] Claude: destroy + redeploy infra cluster with new namespaces
- [ ] Claude: deploy app layer on Ubuntu
- [ ] Wire ArgoCD on infra to sync app cluster
- [ ] Deploy Keycloak in identity/ on infra cluster
- [ ] Deploy observability on both clusters
