# Bug: acg-up step 10d realm JSON path points to wrong directory

> **STALE — DO NOT USE AS A FIX REFERENCE.**
> The correct path is `identity/keycloak/realm-shopping-cart.json`. Any reference in this doc
> to `identity/config/` is wrong. Fix already applied in `c2c6227a` on `k3d-manager-v1.4.11`.

**Date:** 2026-05-24
**File:** `bin/acg-up`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

Step 10d reads `realm-shopping-cart.json` from:
```
${REPO_ROOT}/../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json
```

The file lives at:
```
identity/config/realm-shopping-cart.json
```

`sed` exits non-zero → `make up` exits at step 10d.

---

## Root Cause

The realm JSON was moved from `identity/keycloak/` to `identity/config/` at some point but the path in `acg-up` was not updated.

---

## Fix

**Old (line 828):**
```bash
      "${REPO_ROOT}/../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json")
```

**New:**
```bash
      "${REPO_ROOT}/../shopping-carts/shopping-cart-infra/identity/config/realm-shopping-cart.json")
```

Applied directly (one-line path fix). Shellcheck clean.

**Commit message:**
```
fix(acg-up): correct realm JSON path — identity/config not identity/keycloak
```
