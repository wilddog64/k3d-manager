# Bug: orders PostgreSQL init SQL uses SERIAL but entity model uses UUID

**Date:** 2026-04-27
**Severity:** High (order-service fails to start without ddl-auto workaround)
**Status:** Open — workaround applied in k3d-manager kustomization
**Repos:** `shopping-cart-infra` (fix), `shopping-cart-order` (fix SecurityConfig)

---

## Summary

Two bugs block `order-service` from starting on a fresh cluster:

1. `shopping-cart-infra` init SQL creates `orders.id SERIAL PRIMARY KEY` and
   `order_items.id SERIAL PRIMARY KEY` — but `Order` and `OrderItem` entities use
   `@GeneratedValue(strategy = GenerationType.UUID) private UUID id`.
   Hibernate `ddl-auto: validate` fails because the column types don't match.
   Hibernate `ddl-auto: update` warns but succeeds — however it cannot cast existing
   SERIAL rows to UUID automatically, leaving the schema inconsistent.

2. `SecurityConfig.java` permits only `/actuator/health` but the readiness and liveness
   probes hit `/actuator/health/readiness` and `/actuator/health/liveness`. These return
   401, causing the pod to stay `0/1` indefinitely.

---

## Workarounds in place (k3d-manager `services/shopping-cart-order/kustomization.yaml`)

- `SPRING_JPA_HIBERNATE_DDL_AUTO: update` in ConfigMap patch → lets Hibernate build the schema
- Readiness/liveness/startup probe paths patched to `/actuator/health` → bypasses the security gap

These workarounds survive ArgoCD syncs because they are in git (kustomize patches).
They do NOT fix the root causes.

---

## Root Cause 1 — shopping-cart-infra init SQL

File: `data-layer/postgresql/orders/configmap.yaml`

### Current (wrong)
```sql
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    ...
    user_id INTEGER NOT NULL,
    ...
);

CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    ...
);
```

### Required (correct — matches entity model)
```sql
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    total_amount NUMERIC(10, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id VARCHAR(255) NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL,
    total_price NUMERIC(10, 2) NOT NULL
);
```

Remove the sample data INSERTs (they use INTEGER ids). Remove functions that reference
`orders_id_seq` (does not exist with UUID schema).

---

## Root Cause 2 — shopping-cart-order SecurityConfig

File: `src/main/java/com/shoppingcart/order/config/SecurityConfig.java`

### Current (wrong)
```java
.requestMatchers("/actuator/health", "/actuator/info", "/actuator/prometheus").permitAll()
```

### Required (correct)
```java
.requestMatchers("/actuator/health", "/actuator/health/**", "/actuator/info", "/actuator/prometheus").permitAll()
```

---

## Definition of Done

### Repo: shopping-cart-infra
- [ ] `data-layer/postgresql/orders/configmap.yaml` updated to UUID schema
- [ ] Sample INSERT statements removed (or updated to use `gen_random_uuid()`)
- [ ] Functions referencing `orders_id_seq` removed
- [ ] Committed on branch `fix/orders-init-sql-uuid` in `shopping-cart-infra`
- [ ] Pushed: `git push origin fix/orders-init-sql-uuid`

### Repo: shopping-cart-order
- [ ] `SecurityConfig.java` updated to permit `/actuator/health/**`
- [ ] Committed on branch `fix/actuator-health-security` in `shopping-cart-order`
- [ ] Pushed: `git push origin fix/actuator-health-security`

### Repo: k3d-manager (cleanup — after both above are merged)
- [ ] Remove `SPRING_JPA_HIBERNATE_DDL_AUTO: update` patch from
  `services/shopping-cart-order/kustomization.yaml`
- [ ] Remove health probe path patches from
  `services/shopping-cart-order/kustomization.yaml`

### Verification
- [ ] Drop all orders tables and restart order-service — pod reaches `1/1 Running`
  without any kustomize workaround patches

## What NOT to Do
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the listed targets
- Do NOT commit to `main` — always work on the specified feature branch
- Do NOT edit `shopping-cart-infra` or `shopping-cart-order` from k3d-manager context
