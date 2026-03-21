# Gemini Task: Force ArgoCD Sync — Post Manifest Fix (2026-03-21)

## Context

Three shopping-cart app manifest PRs were merged to `main` today (2026-03-21):

| Repo | PR | Merge SHA | Key Fix |
|---|---|---|---|
| shopping-cart-order | #15 | `d109004` | `VAULT_ENABLED: false` alongside `SPRING_CLOUD_VAULT_ENABLED: false` |
| shopping-cart-product-catalog | #14 | `aa5de3c` | Env var keys fixed (`DATABASE_*` → `DB_*`, readiness probe `/health` → `/ready`) |
| shopping-cart-infra | #20 | `1a5c34d` | RabbitMQ README updated to 1-replica |

ArgoCD may not have auto-synced yet. All 5 apps need to be force-synced so the new manifests deploy.

---

## Before You Start

```
First command: hostname && uname -n
```

Confirm you are on the **Ubuntu k3s EC2 instance** (not the M2 Air). If on M2 Air, switch context:
```bash
kubectl config use-context ubuntu-k3s
```

Then confirm ArgoCD CLI works:
```bash
argocd app list
```

If not logged in:
```bash
argocd login localhost:8080 --insecure --username admin --password $(kubectl get secret argocd-initial-admin-secret -n cicd -o jsonpath='{.data.password}' | base64 -d)
```

---

## Task

### Step 1 — Force sync all 5 apps

```bash
for app in basket-service order-service product-catalog frontend payment-service; do
  echo "=== Syncing $app ==="
  argocd app sync $app --force
done
```

Wait for each to complete before moving to the next. If a sync fails, note the error and continue.

### Step 2 — Verify pod status

```bash
kubectl get pods -n shopping-cart-apps
kubectl get pods -n shopping-cart-payment
```

Expected:
- `basket-service` — Running ✅ (was already Running)
- `product-catalog` — Running ✅ (env var fix should resolve localhost fallback)
- `frontend` — Running ✅ (was already Running)
- `order-service` — Running or CrashLoopBackOff (RabbitMQ `Connection refused` still possible)
- `payment-service` — Pending or Running (memory constraints on t3.medium)

### Step 3 — Check order-service logs if still crashing

```bash
kubectl logs -n shopping-cart-apps deployment/order-service --tail=50
```

Look for:
- RabbitMQ connection errors → expected (infra issue, not manifest issue)
- PostgreSQL auth errors → should be gone after manifest fix
- Vault connection errors → should be gone (`VAULT_ENABLED: false` now)

### Step 4 — Check product-catalog specifically

```bash
kubectl logs -n shopping-cart-apps deployment/product-catalog --tail=50
kubectl exec -n shopping-cart-apps deployment/product-catalog -- env | grep -E 'DB_|RABBIT'
```

Confirm `DB_HOST` points to `postgresql-products.shopping-cart-data.svc.cluster.local` (not `localhost`).

---

## Definition of Done

- [ ] All 5 apps synced (ArgoCD shows `Synced` + `Healthy` or known error)
- [ ] `product-catalog` is Running and connecting to PostgreSQL (not localhost)
- [ ] Pod status table reported with actual output (paste, don't summarize)
- [ ] order-service and payment-service status noted with root cause if still failing

**Report format:**
```
=== Pod Status ===
<paste of kubectl get pods -n shopping-cart-apps>
<paste of kubectl get pods -n shopping-cart-payment>

=== product-catalog env check ===
<paste of env | grep DB_ output>

=== order-service logs (last relevant lines) ===
<paste>
```

---

## What NOT to Do

- Do NOT update `memory-bank/` — Claude will do that after verifying output
- Do NOT create a PR
- Do NOT modify any manifest files — this is verification/sync only
- Do NOT skip ArgoCD login if CLI returns 401
