# Bug: order-service missing column 'cancellation_reason' in table 'orders'

**Date:** 2026-05-02
**Severity:** High — blocks order-service startup (CrashLoopBackOff)
**Status:** Open
**Assignee:** Gemini CLI

## Symptom
The `order-service` pod fails to start with `CrashLoopBackOff`.
Application logs show:
```
Schema-validation: missing column [cancellation_reason] in table [orders]
```

## Root Cause
The JPA entity in the `order-service` application code has been updated to include a `cancellation_reason` field, but the PostgreSQL initialization SQL in the `shopping-cart-infra` repository (`data-layer/postgresql/orders/configmap.yaml`) has not been updated to match the new schema. Hibernate validation fails during startup because the actual database table is missing the required column.

## Required Fix
Update `data-layer/postgresql/orders/configmap.yaml` to include the `cancellation_reason` column in the `CREATE TABLE orders` statement:
```sql
ALTER TABLE orders ADD COLUMN cancellation_reason VARCHAR(255);
```
Or update the base `CREATE TABLE` definition if starting from scratch.
