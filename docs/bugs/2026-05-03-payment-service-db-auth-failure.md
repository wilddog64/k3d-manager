# Bug: payment-service DB auth failure at startup (Flyway password mismatch)

**Status:** Open
**Branch:** `bug/payment-service-db-auth-failure`
**Severity:** P1 — service cannot start; payment flows unavailable
**Observed:** 2026-05-03
**Repo:** `shopping-cart-infra`

---

## Symptom

`payment-service` pod enters `CrashLoopBackOff` immediately after the GHCR image pull
recovers. Flyway fails on the first DB migration attempt:

```
org.flywaydb.core.api.exception.FlywaySqlException:
  Unable to obtain connection from database
  (jdbc:postgresql://postgresql-payment.shopping-cart-data.svc.cluster.local:5432/payments)
Caused by: org.postgresql.util.PSQLException:
  FATAL: password authentication failed for user "postgres"
```

Service never reaches `Running` state.

---

## Root Cause

Two conflicting credential sources for the `payment-db-credentials` Secret:

| Source | Secret target | Password value |
|--------|---------------|----------------|
| `postgres-payment-app` ESO (repo: `data-layer/secrets/postgres-payment-externalsecret.yaml`) | `payment-db-credentials` | Vault `secret/data/postgres/payment` → **random password seeded by `acg-up`** |
| `payment-db-credentials-eso` ExternalSecret (**imperative, not in any repo**) | `payment-db-credentials` | Unknown / `CHANGE_ME` |
| Base secret (`shopping-cart-payment/k8s/base/secret.yaml`) | `payment-db-credentials` | `CHANGE_ME` |

`postgresql-payment` StatefulSet was initialized via `postgres-payment-admin` ESO which
reads the **same** Vault random password. So PostgreSQL was seeded with the random password,
but at some point `payment-db-credentials` reverted to `CHANGE_ME` — either because:

- The imperative `payment-db-credentials-eso` overwrote the repo-managed secret with stale
  values, **or**
- `postgres-payment-app` ESO was never synced (ArgoCD application not targeting its namespace),
  leaving only the base secret with `CHANGE_ME` on the cluster.

Evidence: `kubectl get secret payment-db-credentials -n shopping-cart-payment -o yaml` shows
`DATA: 4` with `CHANGE_ME` values for `password` and `DB_PASSWORD` — matching `base/secret.yaml`
exactly, not a Vault-synced secret.

---

## Diagnosis Steps Taken

1. Pod logs confirmed `PSQLException: password authentication failed for user "postgres"`.
2. `kubectl get externalsecret -n shopping-cart-payment` — found `payment-db-credentials-eso`
   (`SecretSynced: True`, `DATA: 4`) and `postgres-payment-app` (`Ready: True`).
3. `payment-db-credentials-eso` is **not** defined in any repo file — imperative drift.
4. `postgres-payment-externalsecret.yaml` (repo) already contains the correct config:
   target `payment-db-credentials`, reads `DB_USERNAME`/`DB_PASSWORD` from
   `secret/data/postgres/payment`, and `RABBITMQ_USERNAME`/`RABBITMQ_PASSWORD` from
   `secret/data/rabbitmq/default`.
5. Base secret (`shopping-cart-payment/k8s/base/secret.yaml`) has `password: CHANGE_ME`.

---

## Fix

### Option A — Delete imperative ESO and verify repo ESO wins (preferred)

Delete the out-of-repo `payment-db-credentials-eso` from the cluster so `postgres-payment-app`
ESO (already in the repo) is the sole owner and syncs the correct Vault password.

```bash
kubectl delete externalsecret payment-db-credentials-eso -n shopping-cart-payment
```

Then force ESO to re-sync:
```bash
kubectl annotate externalsecret postgres-payment-app -n shopping-cart-payment \
  force-sync=$(date +%s) --overwrite
```

Verify the secret now contains the Vault password (not `CHANGE_ME`):
```bash
kubectl get secret payment-db-credentials -n shopping-cart-payment \
  -o jsonpath='{.data.password}' | base64 -d
```

Restart the pod:
```bash
kubectl rollout restart deployment/payment-service -n shopping-cart-payment
```

### Option B — Codify the imperative ESO (if Option A fails)

If `postgres-payment-app` ESO is not in ArgoCD scope, add the imperative ESO to the repo
by reconciling it with `data-layer/secrets/postgres-payment-externalsecret.yaml`.
This file already has the correct spec — the issue is whether ArgoCD is syncing it.

Check: `argocd app get data-layer --show-managed-fields | grep payment` — confirm
`postgres-payment-app` ExternalSecret is managed.

---

## Files

| File | Status |
|------|--------|
| `data-layer/secrets/postgres-payment-externalsecret.yaml` | Already correct — no change needed |
| `apps/shopping-cart-payment/` (ArgoCD Application) | Verify `data-layer` app includes `shopping-cart-payment` namespace resources |

---

## What NOT to Do

- Do NOT recreate the PostgreSQL PVC — data would be lost; fix is credential alignment only.
- Do NOT hardcode the Vault password in `postgres-payment-externalsecret.yaml`.
- Do NOT add `optional: true` to the payment-service deployment's `envFrom` as a workaround
  — the service will silently use `CHANGE_ME` and still fail at Flyway.

---

## Related

- `data-layer/secrets/postgres-payment-externalsecret.yaml` — repo ESO (already correct)
- `shopping-cart-payment/k8s/base/secret.yaml` — base secret with `CHANGE_ME` placeholder
- `docs/issues/2026-04-05-crashloopbackoff-diagnosis.md` — prior payment credential fix (PR #28)
