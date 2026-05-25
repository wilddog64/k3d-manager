# Bug: acg-up regenerates postgres passwords on every run — ESO lag causes auth failure

**Date:** 2026-05-24
**File:** `bin/acg-up`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

`bin/acg-up` generates a fresh random password for each postgres database on every run
(lines 623–634) and unconditionally writes them to Vault:

```bash
_pg_pass_products=$(openssl rand -base64 24 | tr -d '=+/')
_vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_products}\"}" postgres/products
```

Step 11b then runs `ALTER USER postgres PASSWORD '${_pg_pass_products}'` to align the
running postgres instance with the new Vault value. This works for postgres — but ESO
ExternalSecrets for the app layer (`product-catalog-secrets`, `postgres-products-app`,
etc.) have `refreshInterval: 24h`. They do NOT re-sync immediately when Vault changes.

**Result on a running cluster (e.g. after `make up` is re-run without a full cluster
rebuild):**

- Vault → new password Y (written this run)
- postgres → new password Y (set via ALTER USER in step 11b)
- `product-catalog-secrets.DB_PASSWORD` → old password X (ESO hasn't re-synced)
- product-catalog pod → tries to connect with X → `FATAL: password authentication failed`

The `ldap/admin` and `keycloak/admin` blocks already handle this correctly with a
`_vault_kv_exists` guard. The three postgres paths (`postgres/orders`,
`postgres/products`, `postgres/payment`) are missing this guard.

---

## Root Cause

Lines 623–634 always generate new passwords and always overwrite Vault, even when a
stable credential already exists from a prior run. The ESO 24h refresh window means
app-layer secrets lag behind the new Vault value.

---

## Fix

### Change 1 — `bin/acg-up`: wrap postgres password generation in `_vault_kv_exists` guard

Apply the same idempotency pattern already used for `ldap/admin` (line 640) and
`keycloak/admin` (line 650).

**Exact old block (lines 623–634):**

```bash
_pg_pass_orders=$(openssl rand -base64 24 | tr -d '=+/')
_pg_pass_products=$(openssl rand -base64 24 | tr -d '=+/')
_pg_pass_payment=$(openssl rand -base64 24 | tr -d '=+/')
_redis_pass_cart=$(openssl rand -base64 24 | tr -d '=+/')
_redis_pass_orders=$(openssl rand -base64 24 | tr -d '=+/')
_rabbitmq_pass=$(openssl rand -base64 24 | tr -d '=+/')

_vault_kv_put "{\"password\":\"${_redis_pass_cart}\"}"                                           redis/cart
_vault_kv_put "{\"password\":\"${_redis_pass_orders}\"}"                                         redis/orders-cache
_vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_orders}\"}"                  postgres/orders
_vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_products}\"}"                postgres/products
_vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_payment}\"}"                 postgres/payment
```

**Exact new block:**

```bash
_redis_pass_cart=$(openssl rand -base64 24 | tr -d '=+/')
_redis_pass_orders=$(openssl rand -base64 24 | tr -d '=+/')
_rabbitmq_pass=$(openssl rand -base64 24 | tr -d '=+/')

_vault_kv_put "{\"password\":\"${_redis_pass_cart}\"}"                                           redis/cart
_vault_kv_put "{\"password\":\"${_redis_pass_orders}\"}"                                         redis/orders-cache

if _vault_kv_exists "postgres/orders"; then
  _info "[acg-up] Reusing existing Vault secret postgres/orders"
  _pg_pass_orders=$(_vault_kv_get_field "postgres/orders" "password")
else
  _pg_pass_orders=$(openssl rand -base64 24 | tr -d '=+/')
  _vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_orders}\"}"                postgres/orders
fi

if _vault_kv_exists "postgres/products"; then
  _info "[acg-up] Reusing existing Vault secret postgres/products"
  _pg_pass_products=$(_vault_kv_get_field "postgres/products" "password")
else
  _pg_pass_products=$(openssl rand -base64 24 | tr -d '=+/')
  _vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_products}\"}"              postgres/products
fi

if _vault_kv_exists "postgres/payment"; then
  _info "[acg-up] Reusing existing Vault secret postgres/payment"
  _pg_pass_payment=$(_vault_kv_get_field "postgres/payment" "password")
else
  _pg_pass_payment=$(openssl rand -base64 24 | tr -d '=+/')
  _vault_kv_put "{\"username\":\"postgres\",\"password\":\"${_pg_pass_payment}\"}"               postgres/payment
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Wrap postgres/orders, postgres/products, postgres/payment Vault writes in `_vault_kv_exists` guard — reuse existing secret if present |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched
- The Step 11b `ALTER USER postgres PASSWORD '${_pg_pass_products}'` block (lines 1400–1403) must remain unchanged — it is still needed as a safety net for fresh cluster initializations

---

## Definition of Done

- [ ] `bin/acg-up` updated — postgres password blocks wrapped in `_vault_kv_exists` guard
- [ ] `_pg_pass_orders`, `_pg_pass_products`, `_pg_pass_payment` variables removed from the unconditional generation block at lines 623–625
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-up): reuse postgres Vault secrets across runs — stop regenerating on every acg-up
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
- Do NOT remove the Step 11b `ALTER USER postgres PASSWORD` block — it remains as a safety net
- Do NOT apply the same pattern to `_redis_pass_cart`, `_redis_pass_orders`, or `_rabbitmq_pass` in this PR — scope is postgres only
