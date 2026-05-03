# Bug: order-service schema expansion mismatch

**Date:** 2026-05-03
**Severity:** High — blocks order-service startup (CrashLoopBackOff)
**Status:** Fixed (`2e8d0bf` — `bug/order-service-schema-expansion`)
**Assignee:** Gemini CLI

## Symptom
The `order-service` pod fails to start with `CrashLoopBackOff`.
Application logs show sequential failures as each missing column is encountered:
```
Schema-validation: missing column [cancelled_at] in table [orders]
```

## Root Cause
A deep audit of the Java `Order` entity reveals that the database schema in `shopping-cart-infra` is missing 11 columns required for the current application logic (lifecycle tracking and embedded shipping address).

## Missing Columns (Table: orders)
- **Metadata:** `tracking_number`, `carrier`
- **Lifecycle Timestamps:** `paid_at`, `shipped_at`, `completed_at`, `cancelled_at`
- **Shipping Address:** `shipping_street`, `shipping_city`, `shipping_state`, `shipping_postal_code`, `shipping_country`

## Required Fix
Update `data-layer/postgresql/orders/configmap.yaml` to include the full schema.

> **Scope limitation:** The init SQL runs only when PostgreSQL initialises a brand-new data directory.
> Any already-provisioned `orders` PVC will retain the old schema and must be either recreated
> or migrated with `ALTER TABLE orders ADD COLUMN …` before `order-service` stops failing
> schema validation.

```sql
ALTER TABLE orders 
ADD COLUMN tracking_number VARCHAR(255),
ADD COLUMN carrier VARCHAR(255),
ADD COLUMN paid_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN shipped_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN completed_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN cancelled_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN shipping_street VARCHAR(255),
ADD COLUMN shipping_city VARCHAR(255),
ADD COLUMN shipping_state VARCHAR(255),
ADD COLUMN shipping_postal_code VARCHAR(20),
ADD COLUMN shipping_country VARCHAR(255);
```
