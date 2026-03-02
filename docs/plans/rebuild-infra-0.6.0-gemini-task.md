# Gemini Task: End-to-End Infra Cluster Rebuild — v0.6.0

**Branch:** `rebuild-infra-0.6.0`
**Created:** 2026-03-02
**Author:** Claude

---

## Objective

Rebuild the infra cluster from scratch to verify every component deploys and
passes its test suite at v0.6.0. Document every issue found in `docs/issues/`
and fix it before moving to the next step. Commit fixes to the branch as you go.

---

## House Rules

- **Pipe all command output to `scratch/logs/<cmd>-<timestamp>.log`** — always
  print the log path to the terminal before running the command
- **Document every issue** in `docs/issues/YYYY-MM-DD-<short-title>.md` before
  fixing it
- **Fix before proceeding** — do not advance to the next step with a broken state
- **Commit after each successful step** — include any issue docs and fixes
- **No hints provided** — investigate root cause yourself
- **STOP and report** if a step cannot be fixed

---

## Environment

- **Machine:** m4-air (macOS, ARM64)
- **Cluster provider:** OrbStack (`CLUSTER_PROVIDER=orbstack`)
- **All commands:** `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager <cmd>`
- **Ubuntu app cluster SSH:** `ssh ubuntu` (ForwardAgent yes)
- **Stale SSH socket fix:** `ssh -O exit ubuntu`

---

## Step 1 — Destroy existing infra cluster

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager destroy_cluster
```

Verify: `kubectl config get-contexts` — `k3d-k3d-cluster` should be gone.

---

## Step 2 — Deploy cluster (includes Istio)

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_cluster
```

Verify:
```bash
kubectl get nodes                          # node Ready
kubectl -n istio-system get pods          # istiod + ingressgateway Running
```

---

## Step 3 — Deploy Vault

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_vault
```

Verify:
```bash
kubectl -n secrets get pods               # vault-0 Running
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_vault
```

---

## Step 4 — Deploy ESO

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_eso
```

Verify:
```bash
kubectl -n secrets get pods               # eso pods Running
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_eso
```

---

## Step 5 — Deploy OpenLDAP

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_ldap
```

Verify:
```bash
kubectl -n identity get pods             # openldap pod Running
```

---

## Step 6 — Deploy Jenkins

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault --enable-ldap
```

Verify:
```bash
kubectl -n cicd get pods                 # jenkins-0 Running
kubectl -n cicd get externalsecret       # Ready
```

---

## Step 7 — Deploy ArgoCD

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_argocd --enable-vault --enable-ldap --bootstrap
```

Verify:
```bash
kubectl -n cicd get pods                 # argocd-server, argocd-repo-server, argocd-application-controller Running
kubectl -n cicd get externalsecret       # argocd-admin-secret Ready
```

---

## Step 8 — Deploy Keycloak

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_keycloak --enable-vault --enable-ldap
```

Verify:
```bash
kubectl -n identity get pods             # keycloak-0 Running
kubectl -n identity get externalsecret   # admin + ldap secrets Ready
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_keycloak
```

---

## Step 9 — Run full test suite

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_vault
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_eso
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_istio
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_keycloak
```

All must pass before proceeding.

---

## Step 10 — Configure Vault app cluster auth (Ubuntu SSH required)

From the Ubuntu app cluster, retrieve the k3s API URL and CA cert:

```bash
# On Ubuntu (via ssh ubuntu):
cat /etc/rancher/k3s/k3s.yaml   # find server: https://<ip>:<port>
cat /var/lib/rancher/k3s/server/tls/server-ca.crt   # CA cert
```

Copy the CA cert to the Mac, then run:

```bash
APP_CLUSTER_API_URL=https://<ubuntu-ip>:6443 \
APP_CLUSTER_CA_CERT_PATH=/path/to/app-cluster-ca.crt \
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager configure_vault_app_auth
```

Verify:
```bash
kubectl -n secrets exec vault-0 -- vault auth list   # kubernetes-app/ present
kubectl -n secrets exec vault-0 -- vault read auth/kubernetes-app/role/eso-app-cluster
```

---

## Deliverables

- All 10 steps completed successfully
- Any issues documented in `docs/issues/` and fixed
- Fixes committed to `rebuild-infra-0.6.0`
- Final commit message: `chore: v0.6.0 end-to-end rebuild verified`
- Report back with: pass/fail per step, list of issues found + fixed, any remaining open items

---

## Out of Scope

- ESO deploy on Ubuntu app cluster (Step 11+) — separate task after this PR merges
- shopping-cart-data / apps deployment — separate task
