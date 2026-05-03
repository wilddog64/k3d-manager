# Bugfix: payment-service DB auth failure — ArgoCD/ESO credential conflict

**Branch:** `bug/payment-service-db-auth-failure`
**Files:** `argocd/applications/payment-service.yaml`

---

## Problem

`payment-service` enters `CrashLoopBackOff` immediately at startup. Flyway fails with:

```
org.flywaydb.core.api.exception.FlywaySqlException:
  Unable to obtain connection from database
  (jdbc:postgresql://postgresql-payment.shopping-cart-data.svc.cluster.local:5432/payments)
Caused by: org.postgresql.util.PSQLException:
  FATAL: password authentication failed for user "postgres"
```

**Root cause:** ArgoCD `payment-service` Application has `selfHeal: true` and deploys
`k8s/base/secret.yaml` from `shopping-cart-payment`, which contains hardcoded `CHANGE_ME`
values. ArgoCD continuously overwrites `payment-db-credentials` (in `shopping-cart-payment`
namespace) back to `CHANGE_ME` whenever ESO syncs the correct Vault password. The
`postgres-payment-app` ExternalSecret has a 24h refresh interval — ArgoCD's self-heal fires
every few minutes and wins the race.

`postgresql-payment` was initialized by `acg-up` via `postgres-payment-admin` ESO with a
random Vault password. ArgoCD's CHANGE_ME cannot authenticate against it.

---

## Reproduction

After sandbox boot:
1. `kubectl get secret payment-db-credentials -n shopping-cart-payment -o jsonpath='{.data.password}' | base64 -d`
   → outputs `CHANGE_ME`
2. `kubectl logs -n shopping-cart-payment -l app.kubernetes.io/name=payment-service --tail=20`
   → `FATAL: password authentication failed for user "postgres"`

---

## Fix

### Change 1 — `argocd/applications/payment-service.yaml`: add ignoreDifferences for payment-db-credentials

Stop ArgoCD from treating ESO-managed Secret data as out-of-sync. ArgoCD will still create
the Secret initially (so the resource exists), but will no longer overwrite `/data` on
self-heal cycles. ESO then owns the actual credential values.

**Exact old block (lines 59–64):**

```yaml
  # Health checks
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas  # Ignore HPA-managed replicas
```

**Exact new block:**

```yaml
  # Health checks
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas  # Ignore HPA-managed replicas
    - group: ""
      kind: Secret
      name: payment-db-credentials
      jsonPointers:
        - /data
```

---

## Files Changed

| File | Change |
|------|--------|
| `argocd/applications/payment-service.yaml` | Add `ignoreDifferences` entry for `payment-db-credentials` Secret `/data` |

---

## Rules

- No shell scripts — YAML-only change; shellcheck does not apply
- Do not modify any other file

---

## Definition of Done

- [ ] `argocd/applications/payment-service.yaml` has the new `ignoreDifferences` entry
- [ ] YAML is valid: `python3 -c "import yaml; yaml.safe_load(open('argocd/applications/payment-service.yaml'))"` exits 0
- [ ] Committed and pushed to `bug/payment-service-db-auth-failure`
- [ ] `memory-bank/activeContext.md` updated: change status to `FIXED (<sha>)`
- [ ] `memory-bank/progress.md` updated with the commit SHA

**Commit message (exact):**
```
fix(payment): stop ArgoCD self-heal from overwriting ESO-managed payment-db-credentials
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `argocd/applications/payment-service.yaml`,
  `memory-bank/activeContext.md`, and `memory-bank/progress.md`
- Do NOT commit to `main` — work on `bug/payment-service-db-auth-failure`
- Do NOT delete the `payment-db-credentials-eso` from the cluster — that is a manual
  step documented in `docs/bugs/2026-05-03-payment-service-db-auth-failure-tracking.md`

---

## Post-Fix Manual Step (not for Codex)

After this PR merges and ArgoCD syncs, the imperative `payment-db-credentials-eso`
(not in any repo) should be removed from the cluster to eliminate ESO ownership ambiguity:

```bash
kubectl delete externalsecret payment-db-credentials-eso -n shopping-cart-payment
kubectl annotate externalsecret postgres-payment-app -n shopping-cart-payment \
  force-sync=$(date +%s) --overwrite
kubectl rollout restart deployment/payment-service -n shopping-cart-payment
```
