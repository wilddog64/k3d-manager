# Bugfix: orders schema missing 11 columns — order-service CrashLoopBackOff

**Date:** 2026-05-02
**Branch:** `bug/order-service-schema-expansion`
**File:** `data-layer/postgresql/orders/configmap.yaml`
**Issue doc:** `docs/issues/2026-05-03-order-service-schema-expansion-mismatch.md`

---

## Before You Start

1. `git pull origin bug/order-service-schema-expansion` in the shopping-cart-infra repo
2. Read `data-layer/postgresql/orders/configmap.yaml` in full before touching anything

---

## Problem

`order-service` pod enters CrashLoopBackOff. Application logs show:

```
Schema-validation: missing column [cancelled_at] in table [orders]
```

The init SQL in the ConfigMap is missing 11 columns that the Java `Order` entity now requires.

---

## Root Cause

`data-layer/postgresql/orders/configmap.yaml` `CREATE TABLE orders` block was never updated
to match the expanded Java entity. Eleven columns are absent:
lifecycle timestamps (`paid_at`, `shipped_at`, `completed_at`, `cancelled_at`),
shipping address fields (5), and tracking fields (`tracking_number`, `carrier`).

---

## Fix

### Change 1 — `data-layer/postgresql/orders/configmap.yaml`: add 11 missing columns

**Exact old block:**

```sql
    CREATE TABLE IF NOT EXISTS orders (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        customer_id VARCHAR(255) NOT NULL,
        status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
        total_amount NUMERIC(10, 2) NOT NULL,
        currency VARCHAR(3) NOT NULL DEFAULT 'USD',
        cancellation_reason VARCHAR(255),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
```

**Exact new block:**

```sql
    CREATE TABLE IF NOT EXISTS orders (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        customer_id VARCHAR(255) NOT NULL,
        status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
        total_amount NUMERIC(10, 2) NOT NULL,
        currency VARCHAR(3) NOT NULL DEFAULT 'USD',
        cancellation_reason VARCHAR(255),
        tracking_number VARCHAR(255),
        carrier VARCHAR(255),
        shipping_street VARCHAR(255),
        shipping_city VARCHAR(255),
        shipping_state VARCHAR(255),
        shipping_postal_code VARCHAR(20),
        shipping_country VARCHAR(255),
        paid_at TIMESTAMP WITH TIME ZONE,
        shipped_at TIMESTAMP WITH TIME ZONE,
        completed_at TIMESTAMP WITH TIME ZONE,
        cancelled_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
```

**Scope limitation:** This init SQL only runs when PostgreSQL initialises a brand-new data directory.
Existing `orders` PVCs will retain the old schema. To fix an already-provisioned sandbox, either
delete and recreate the PVC or run a one-time migration:

```sql
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS tracking_number VARCHAR(255),
  ADD COLUMN IF NOT EXISTS carrier VARCHAR(255),
  ADD COLUMN IF NOT EXISTS shipping_street VARCHAR(255),
  ADD COLUMN IF NOT EXISTS shipping_city VARCHAR(255),
  ADD COLUMN IF NOT EXISTS shipping_state VARCHAR(255),
  ADD COLUMN IF NOT EXISTS shipping_postal_code VARCHAR(20),
  ADD COLUMN IF NOT EXISTS shipping_country VARCHAR(255),
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS shipped_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMP WITH TIME ZONE;
```

---

## Files Changed

| File | Change |
|------|--------|
| `data-layer/postgresql/orders/configmap.yaml` | Add 11 missing columns to `CREATE TABLE orders` |

---

## Rules

- `yamllint data-layer/postgresql/orders/configmap.yaml` — zero new errors
- Only `data-layer/postgresql/orders/configmap.yaml` may be modified

---

## Definition of Done

- [ ] All 11 columns present in `CREATE TABLE orders` block
- [ ] Column ordering: tracking + shipping fields after `cancellation_reason`, lifecycle timestamps before `created_at`/`updated_at`
- [ ] YAML indentation unchanged (4-space indent for SQL lines under `01-init-schema.sql:`)
- [ ] `yamllint data-layer/postgresql/orders/configmap.yaml` passes
- [ ] Committed and pushed to `bug/order-service-schema-expansion`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(orders): add 11 missing columns to orders schema (lifecycle, shipping, tracking)
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `data-layer/postgresql/orders/configmap.yaml`, `memory-bank/activeContext.md`, `memory-bank/progress.md`, and files under `docs/`
- Do NOT commit to `main` — work on `bug/order-service-schema-expansion`
- Do NOT add `NOT NULL` constraints to the new columns — they must be nullable to allow existing rows
