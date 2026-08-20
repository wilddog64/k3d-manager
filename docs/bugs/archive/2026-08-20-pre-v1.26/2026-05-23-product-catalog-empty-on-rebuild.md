# Bug: Product catalog DB empty on every cluster rebuild

**Branch:** `k3d-manager-v1.4.9`
**File:** `bin/acg-up`

---

## Problem

After `make up`, the products page shows "No products found." The `products` table has 0 rows.

Two compounding failures:

1. **Password drift** — PostgreSQL `postgresql-products-0` is initialized on first boot using
   `POSTGRES_PASSWORD` from the `postgres-products-admin` ESO secret. On a fresh cluster, ESO
   may not have synced Vault yet, so the pod starts with whatever was seeded by Vault at that
   moment. On subsequent `make up` runs Vault/ESO may have rotated the secret, leaving the
   pgdata password and the ESO secret out of sync. The seed job (and any newly-started pod)
   picks up the rotated ESO password and gets `FATAL: password authentication failed`.

2. **DNS timing** — the `product-catalog-seed` PostSync hook fires before cross-namespace DNS
   (`postgresql-products.shopping-cart-data.svc.cluster.local`) is stable, causing the job to
   fail immediately. The `ttlSecondsAfterFinished: 300` cleans up the failed job and the DB
   stays empty.

---

## Fix

Add **Step 11b** to `bin/acg-up` (after ClusterSecretStore is confirmed Ready, so ESO secrets
are synced) that:

1. Reads the intended PostgreSQL password from the ESO-synced `postgres-products-admin` secret.
2. Runs `ALTER USER postgres PASSWORD '...'` via local trust auth (`kubectl exec psql`) to
   reconcile pgdata with Vault — idempotent, safe to run every rebuild.
3. Restarts `product-catalog` only when its running env `$DB_PASSWORD` doesn't match the
   intended password (avoids unnecessary downtime on clean rebuilds).
4. Waits for the rollout to complete.
5. Checks whether the `products` table is empty and, if so, applies the seed job via kustomize
   and waits up to 5 minutes for completion.

---

## Definition of Done

- [ ] `bin/acg-up` Step 11b present between Step 11 and Step 12
- [ ] `shellcheck -S warning bin/acg-up` — zero new warnings
- [ ] `make up` on a fresh cluster produces a non-zero product count
- [ ] `make up` on an already-seeded cluster skips the seed step cleanly
