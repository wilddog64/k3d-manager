# Keycloak realm JSON should reconcile live without rebuilding clusters

## Problem
Keycloak realm changes are still effectively tied to startup behavior and cluster rebuilds.
That makes the `shopping-cart` realm brittle:
- startup import can rerun against an already-initialized database
- a rebuilt cluster is often needed to pick up identity changes
- the current guard is not durable enough to handle restarts safely

## Desired behavior
The realm JSON should be usable as a live reconciliation input:
- if the realm does not exist, import it once
- if the realm already exists, reconcile the mutable fields in place
- repeated runs must be idempotent
- no cluster rebuild should be required to apply realm JSON changes

## Proposed shape
Introduce a dedicated reconcile step outside Keycloak startup:
- render the current realm JSON from `shopping-cart-infra`
- connect to the live Keycloak API or DB-backed admin path
- create the realm only when it is missing
- patch existing realm/client settings when it already exists
- treat startup import as a first-boot convenience only, not the normal update path

## Constraints
- Do not rely on `EmptyDir` for a skip marker; it disappears on pod restart.
- Do not re-run `kc.sh import` on every pod boot.
- Preserve the current live login flow for `admin@shopping-cart.local`.
- Keep the reconcile path safe to run multiple times.

## Success criteria
- `make up` can reapply Keycloak realm JSON without a full cluster rebuild.
- Restarting Keycloak does not re-trigger the duplicate realm import error.
- Live updates to realm/client config can be applied on demand.

## Follow-up
- Implement the reconcile path in `shopping-cart-infra`.
- Update `k3d-manager` docs/memory-bank with the final command flow once the live reconcile step exists.
