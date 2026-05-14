# `acg-up` realm import path points at removed shopping-cart-infra file

## What was attempted
- Ran `make up`

## Actual output
```text
INFO: [acg-up] Step 10d/14 — Importing Keycloak realm shopping-cart...
sed: /Users/cliang/src/gitrepo/personal/k3d-manager/../shopping-carts/shopping-cart-infra/identity/config/realm-shopping-cart.json: No such file or directory
make: *** [up] Error 1
```

## Root cause
- `bin/acg-up` still referenced the old shopping-cart-infra realm import source at `identity/config/realm-shopping-cart.json`
- the current `shopping-cart-infra` branch now stores the import artifact at `identity/keycloak/realm-shopping-cart.json`

## Recommended follow-up
- Update `bin/acg-up` to read the current `shopping-cart-infra/identity/keycloak/realm-shopping-cart.json`
- Align the related BATS fixture so the regression test uses the same path
