# Bug: acg-up realm import fails — realm-shopping-cart.json path points to identity/keycloak/ instead of identity/config/

**Branch:** `k3d-manager-v1.4.7`
**File:** `bin/acg-up`

---

## Problem

`make up` fails at the Keycloak realm import step with:

```
sed: .../shopping-cart-infra/identity/keycloak/realm-shopping-cart.json: No such file or directory
```

The realm JSON lives at `identity/config/realm-shopping-cart.json` but `bin/acg-up` references `identity/keycloak/realm-shopping-cart.json`.

---

## Fix

**File:** `bin/acg-up` line ~769

**Old:**
```bash
      "${REPO_ROOT}/../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json")
```

**New:**
```bash
      "${REPO_ROOT}/../shopping-carts/shopping-cart-infra/identity/config/realm-shopping-cart.json")
```

---

## Definition of Done

- [ ] Path corrected in `bin/acg-up`
- [ ] `shellcheck -S warning bin/acg-up` passes
- [ ] Committed to `k3d-manager-v1.4.7` with message: `fix(acg-up): correct realm-shopping-cart.json path to identity/config/`
