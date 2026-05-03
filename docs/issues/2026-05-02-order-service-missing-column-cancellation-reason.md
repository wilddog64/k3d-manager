# Bug: order-service missing column 'cancellation_reason' in table 'orders'

**Date:** 2026-05-02
**Severity:** High — blocks order-service startup (CrashLoopBackOff)
**Status:** Fixed
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
Update `data-layer/postgresql/orders/configmap.yaml` so the init SQL's `CREATE TABLE orders` statement includes `cancellation_reason VARCHAR(255)`.

Because this SQL only runs when Postgres initializes a fresh data directory, existing volumes that were already initialized also need a one-time migration or recreation before the new column will appear.
