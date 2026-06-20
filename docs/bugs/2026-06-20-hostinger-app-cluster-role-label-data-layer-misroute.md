# Bugfix: Hostinger app cluster missing `k3d-manager/role: app-cluster` label → data-layer misrouted; ESO never bootstrapped

**Date:** 2026-06-20
**Severity:** High — shopping-cart apps on `ubuntu-hostinger` cannot start (no DB, no secrets)
**Affects:** `k3d-manager` (ArgoCD GitOps wiring, `k3s-hostinger` provider)
**Work repo / branch:** `k3d-manager` branch `fix/hostinger-app-cluster-role-label`
**Assignee:** Codex

---

## Symptom (from `make status` + cluster health, 2026-06-20)

```
shopping-cart-product-catalog   OutOfSync   Missing
shopping-cart-frontend          Synced      Degraded   (CrashLoopBackOff)
shopping-cart-basket            Synced      Degraded   (CrashLoopBackOff)
shopping-cart-order             Synced      Degraded   (CreateContainerConfigError)
shopping-cart-payment           Synced      Degraded   (CreateContainerConfigError)
data-layer                      Unknown     Healthy    (targets dead ubuntu-k3s)
```
Health probe: `Frontend / Pushgateway / Product images: connection refused`;
`Data layer: postgresql-orders, postgresql-payment not ready`.

**Not the tunnel.** ArgoCD/Keycloak/Grafana all return HTTP 200 through the same
tunnel; reachable apps show `Synced` (control plane reached the cluster). The failures
are workload-level on `ubuntu-hostinger`.

---

## Root cause (two faults, confirmed on the live hub)

### Fault B — `data-layer` is misrouted (THIS SPEC FIXES THIS)

The `data-git` ApplicationSet selects clusters by label:

```yaml
# scripts/etc/argocd/applicationsets/data-git.yaml
generators:
  - clusters:
      selector:
        matchLabels:
          k3d-manager/role: app-cluster
```

Live cluster-secret labels (`kubectl get secret cluster-* -n cicd -o jsonpath='{.metadata.labels}'`):

```
cluster-ubuntu-hostinger -> {secret-type: cluster, cluster-name: ubuntu-hostinger}
cluster-ubuntu-k3s       -> {secret-type: cluster, cluster-name: ubuntu-k3s}
```

**Neither cluster carries `k3d-manager/role: app-cluster`.** So the `data-git`
generator matches **zero clusters** and produces no data-layer Application. The live
`data-layer` app (destination `ubuntu-k3s` / `host.k3d.internal:6443`, `Unknown` —
"connection reset by peer") is a stale **orphan** (no `ownerReferences`) from a prior
deployment, pointing at a dead cluster.

Root cause: `_hostinger_register_cluster` registers `ubuntu-hostinger` **without** the
`k3d-manager/role: app-cluster` label, so the cluster the apps actually run on is never
selected by the data-layer generator.

### Fault A — ESO is not bootstrapped on the app cluster (OUT OF SCOPE — needs a decision)

`shopping-cart-product-catalog` sync fails:

```
ExternalSecret/product-catalog-secrets: SyncFailed
  The Kubernetes API could not find external-secrets.io/ExternalSecret ...
  Make sure the "ExternalSecret" CRD is installed on the destination cluster.
```

The hub's "ESO 5/5 ExternalSecrets synced" is on the **hub**, not Hostinger. On
`ubuntu-hostinger`:
- ESO operator + CRDs are absent (`deploy_eso` was never run there; ESO is installed
  **imperatively** via Helm in `scripts/plugins/eso.sh` — there is **no ArgoCD
  Application** that installs it on sync).
- The hub `ClusterSecretStore vault-backend` targets `http://vault.secrets.svc:8200`
  (in-cluster Vault) with **Kubernetes auth bound to hub-cluster service accounts**.
  That service does not exist on Hostinger, and Hostinger's SAs are not registered with
  the hub Vault's k8s auth backend.

Consequence: `payment-db-credentials` (and the other ESO-managed secrets) are never
created on Hostinger → `order`/`payment` → `CreateContainerConfigError`; product-catalog
can't sync → its Service never exists → `frontend` nginx `[emerg] host not found in
upstream "product-catalog...svc"` → CrashLoop; `basket` can't reach its (absent) DB.

**This is an architectural gap, not a config one-liner, and it will NOT "heal on sync."**
It requires a decision on how app-cluster workloads obtain secrets when Vault lives on
the hub. See "Fault A — options" at the end. **Do not implement Fault A in this spec.**

---

## Scope of THIS fix (Fault B only)

Make the `k3s-hostinger` provider label the registered cluster secret with
`k3d-manager/role: app-cluster` so the `data-git` generator routes `data-layer` to the
correct cluster. Pure git change; the live secret is relabeled / re-registered as a
one-time operator step (documented below).

### Before You Start
- `git pull origin fix/hostinger-app-cluster-role-label` (k3d-manager)
- Read in full: this spec, `scripts/lib/providers/k3s-hostinger.sh` (function
  `_hostinger_register_cluster`), `scripts/etc/argocd/applicationsets/data-git.yaml`,
  `scripts/etc/argocd/cluster-secret.yaml.tmpl`.

### Change 1 — `scripts/lib/providers/k3s-hostinger.sh` (`_hostinger_register_cluster`)

Add the `k3d-manager/role: app-cluster` label to the rendered cluster-secret heredoc.

OLD (exact):
```bash
  labels:
    argocd.argoproj.io/secret-type: cluster
    argocd.argoproj.io/cluster-name: ${_HOSTINGER_KUBE_CONTEXT}
```

NEW (exact):
```bash
  labels:
    argocd.argoproj.io/secret-type: cluster
    argocd.argoproj.io/cluster-name: ${_HOSTINGER_KUBE_CONTEXT}
    k3d-manager/role: app-cluster
```

### Change 2 — `scripts/etc/argocd/cluster-secret.yaml.tmpl` (consistency)

The generic app-cluster registration template must also carry the role label so any
cluster registered through it is selected by `data-git`.

OLD (exact):
```yaml
  labels:
    argocd.argoproj.io/secret-type: cluster
```

NEW (exact):
```yaml
  labels:
    argocd.argoproj.io/secret-type: cluster
    k3d-manager/role: app-cluster
```

### What NOT to do
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file outside the two listed above.
- Do NOT commit to `main` — work only on `fix/hostinger-app-cluster-role-label`.
- Do NOT touch the live cluster (no `kubectl`/`argocd` mutations) — git only.
- Do NOT attempt Fault A (ESO / Vault on app cluster) — separate decision pending.
- Do NOT change `data-git.yaml`'s selector or the `data-layer` app name.

## Rules
- `shellcheck scripts/lib/providers/k3s-hostinger.sh` — zero new warnings.
- Run `./scripts/k3d-manager _agent_audit` before reporting done (mandatory gate).
- BATS: if a suite asserts the rendered hostinger cluster-secret labels, update it to
  include the new label; otherwise no test change.

## Definition of Done
- [ ] Both label additions applied exactly as above.
- [ ] `shellcheck` + `_agent_audit` clean; LF endings; no inline comments added.
- [ ] Commit message (verbatim):
      `fix(hostinger): label app-cluster secret k3d-manager/role=app-cluster for data-layer routing`
- [ ] `git push origin fix/hostinger-app-cluster-role-label` — do NOT report done until push succeeds.
- [ ] Update `memory-bank/activeContext.md` + `memory-bank/progress.md` with the commit SHA and status.
- [ ] Report back: commit SHA + the memory-bank lines you updated.

---

## One-time operator steps (Claude/user — NOT Codex; live, applied after merge)

Because cluster-secret labels are not ArgoCD-synced, the running cluster needs a one-time
nudge (chosen under "git fix only", performed by the user/Claude, not in this spec):

```bash
# 1. Label the live Hostinger cluster secret so data-git selects it
kubectl label secret cluster-ubuntu-hostinger -n cicd k3d-manager/role=app-cluster

# 2. Remove the stale orphan data-layer app (targets dead ubuntu-k3s); the generator
#    will recreate data-layer -> ubuntu-hostinger once the label is present
kubectl delete application data-layer -n cicd

# 3. (optional) deregister the dead ubuntu-k3s cluster
kubectl delete secret cluster-ubuntu-k3s -n cicd
```
Then confirm `data-layer` reappears with destination `ubuntu-hostinger` and syncs.

**Note:** this restores the data layer to the correct cluster, but apps will remain
Degraded until **Fault A** (app-cluster ESO/secrets) is resolved.

---

## Fault A — options (for user decision; separate spec/milestone, e.g. v1.8.x)

How app-cluster workloads get ESO-managed secrets when Vault is hub-internal:

1. **GitOps ESO ApplicationSet + external Vault** *(recommended — "heals on sync")*:
   add an ApplicationSet (selector `k3d-manager/role: app-cluster`) that installs the
   `external-secrets` Helm chart (operator + CRDs) on app clusters, plus a
   `ClusterSecretStore` manifest pointing at an **externally reachable** Vault endpoint
   (via the existing tunnel/ingress, TLS — no `--insecure`), authenticated by AppRole or
   a Vault Kubernetes-auth backend registered for the Hostinger API. Consistent with the
   GitOps model; survives cluster rebuilds.
2. **Push model (ESO on hub writes into app cluster)**: hub ESO uses a Kubernetes/PushSecret
   provider to push rendered secrets into Hostinger. Keeps Vault private; adds hub→app
   credential + RBAC coupling.
3. **Imperative bootstrap step**: wire `deploy_eso` (targeting the app-cluster context) +
   a `ClusterSecretStore` apply into the `k3s-hostinger` bringup. Simple, but not
   "heals on sync" and re-run on every rebuild.

Security constraints (per CLAUDE.md): TLS only (no `--insecure`/`-k`), least-privilege
Vault policy/role for the app cluster, no tokens in argv/CI logs. Recommend **Option 1**.
