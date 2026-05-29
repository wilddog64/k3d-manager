# Bug: acg-up step 10d reads non-existent identity/keycloak/realm-shopping-cart.json

> **STALE — DO NOT USE AS A FIX REFERENCE.**
> The correct path is `identity/keycloak/realm-shopping-cart.json`. Any reference in this doc
> to `identity/config/` is wrong. Fix already applied in `c2c6227a` on `k3d-manager-v1.4.11`.

**Date:** 2026-05-25
**File:** `bin/acg-up`
**Branch (work):** `k3d-manager-v1.4.9`

---

## Problem

`acg-up` step 10d reads the Keycloak realm JSON from:

```
identity/keycloak/realm-shopping-cart.json
```

This path does not exist in shopping-cart-infra. The `identity/config/` directory was never
created; the realm JSON lives at `identity/keycloak/realm-shopping-cart.json`.

With `set -euo pipefail`, the `sed` command at line 822 aborts the entire script at this
point. Step 10d never completes — the argocd client redirect URIs are never reconciled
via `_keycloak_reconcile_realm_client`, and `frontendUrl` is never set on the realm.

**Root cause:** `bin/acg-up` line 828 has the wrong subdirectory (`config` instead of `keycloak`).

---

## Reproduction

1. Run `make up` — observe it aborts with a `sed: <path>: No such file or directory` error during step 10d.

---

## Fix

### Change 1 — `bin/acg-up` line 828: correct the realm JSON path

**Exact old line (line 828):**

```bash
      "${REPO_ROOT}/../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json")
```

**Exact new line:**

```bash
      "${REPO_ROOT}/../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json")
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Fix path: `identity/config/` → `identity/keycloak/` on line 828 |

---

## Definition of Done

- [x] Line 828 updated — path now points to `identity/keycloak/realm-shopping-cart.json`
- [x] `bash -n bin/acg-up` passes (no syntax errors)
- [x] Committed on `k3d-manager-v1.4.9`

**Commit message (exact):**
```
fix(acg-up): correct realm JSON path — identity/config/ does not exist, use identity/keycloak/
```
