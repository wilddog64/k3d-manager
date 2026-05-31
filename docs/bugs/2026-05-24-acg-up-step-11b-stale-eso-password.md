# Bug: Step 11b ALTER USER uses stale ESO secret — seed job fails with password auth error

**Date:** 2026-05-24
**File:** `bin/acg-up`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

`product-catalog-seed` and `product-catalog-fts-index` ArgoCD PostSync Jobs both fail with
`FATAL: password authentication failed for user "postgres"` on every fresh cluster build.

**Root cause:** ESO `refreshInterval` for `postgres-products-admin` is `24h`. Step 11b read
the ESO-synced secret to get `_pg_intended_pw` and ran `ALTER USER postgres PASSWORD`. But
on a fresh `make up`, Vault was just written with a **new random password** moments earlier.
ESO had not yet synced, so the secret still held the **previous run's password**. PostgreSQL
got set to the old password; eventually ESO synced and updated both `postgres-products-admin`
and `product-catalog-secrets` to the new Vault value. The seed job then connected with the
new password — PostgreSQL rejected it.

Timeline:
1. `make up` generates `_pg_pass_products` (new random), writes to Vault
2. Step 11b reads `postgres-products-admin` (ESO not yet synced) → gets **old** password
3. `ALTER USER postgres PASSWORD = old_password` ✓
4. ESO refreshes → `postgres-products-admin` and `product-catalog-secrets` = **new** password
5. Seed job connects with **new** password → PostgreSQL has **old** password → **FAIL**

---

## Fix

Use `_pg_pass_products` (the in-scope variable that was written to Vault) directly instead
of re-reading the ESO secret.

**Commit:** applied directly in `bin/acg-up` on `k3d-manager-v1.4.9`.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Step 11b: replace ESO secret read with `_pg_pass_products` variable |
