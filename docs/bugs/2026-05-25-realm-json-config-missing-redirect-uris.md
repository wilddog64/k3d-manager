# Bug: identity/keycloak/realm-shopping-cart.json missing Cloudflare redirect URIs and has stale PKCE attribute

**Date:** 2026-05-25
**File:** `shopping-cart-infra/identity/keycloak/realm-shopping-cart.json`
**Branch (work):** `fix/keycloak-reconcile-idempotency` (create from `origin/main`)

---

## Problem

`acg-up` step 10d reads `identity/keycloak/realm-shopping-cart.json` to bootstrap the Keycloak
argocd client on first import AND to reconcile the client on subsequent runs via
`_keycloak_reconcile_realm_client`. The argocd client's `redirectUris` only has the local URL
(`https://argocd.shopping-cart.local/*`) — the Cloudflare redirect URI
(`https://argocd.3ai-talk.org/auth/callback`) and the http variant for local access
(`http://argocd.shopping-cart.local/*`) are missing.

This causes Keycloak to reject the OIDC callback from Cloudflare with
"Invalid redirect URL: the protocol and host (including port) must match".

**Root cause:** `identity/keycloak/realm-shopping-cart.json` was never updated to match
`identity/keycloak/realm-shopping-cart.json` (the file used by the reconcile job ConfigMap,
which was fixed in PR #67).

---

## Reproduction

1. Run `make up` to completion
2. Open `https://argocd.3ai-talk.org` in a browser
3. Attempt SSO login — Keycloak shows "Invalid redirect URL"

Expected: Keycloak accepts `https://argocd.3ai-talk.org/auth/callback` and completes login.
Actual: Keycloak rejects the callback with invalid redirect URL error.

---

## Fix

### Change 1 — `identity/keycloak/realm-shopping-cart.json`: add missing redirect URIs

**Exact old block (lines 124–127):**

```json
      "redirectUris": [
        "https://argocd.shopping-cart.local/*",
        "http://localhost:8080/*"
      ],
```

**Exact new block:**

```json
      "redirectUris": [
        "https://argocd.3ai-talk.org/auth/callback",
        "https://argocd.shopping-cart.local/*",
        "http://argocd.shopping-cart.local/*",
        "http://localhost:8080/*"
      ],
```

### Change 2 — `identity/keycloak/realm-shopping-cart.json`: remove stale PKCE attribute from argocd client

**Exact old block (lines 137–139):**

```json
      "attributes": {
        "pkce.code.challenge.method": "S256"
      },
```

**Exact new block:**

```json
      "attributes": {},
```

---

## Files Changed

| File | Change |
|------|--------|
| `identity/keycloak/realm-shopping-cart.json` | Add 2 redirect URIs to argocd client; remove stale PKCE attribute |

---

## Before You Start

1. `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra fetch origin`
2. Create branch from main:
   `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra checkout -b fix/keycloak-reconcile-idempotency origin/main`
3. Read `identity/keycloak/realm-shopping-cart.json` lines 124–140 to confirm old text matches
4. Confirm you are on branch `fix/keycloak-reconcile-idempotency` — never commit to `main`

**Branch (work repo):** `fix/keycloak-reconcile-idempotency` in `shopping-cart-infra`

---

## Rules

- `python3 -c "import json; json.load(open('identity/keycloak/realm-shopping-cart.json'))"` — must pass (valid JSON)
- No other files touched

---

## Definition of Done

- [ ] Lines 124–127: `redirectUris` array now has 4 entries including `https://argocd.3ai-talk.org/auth/callback` and `http://argocd.shopping-cart.local/*`
- [ ] Lines 137–139: `attributes` is now `{}`
- [ ] `python3 -c "import json; json.load(open('identity/keycloak/realm-shopping-cart.json'))"` passes
- [ ] No other files modified
- [ ] Committed on branch `fix/keycloak-reconcile-idempotency`
- [ ] Pushed to `origin/fix/keycloak-reconcile-idempotency`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(keycloak): add Cloudflare redirect URI and remove PKCE from argocd client in realm config
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `identity/keycloak/realm-shopping-cart.json`
- Do NOT commit to `main`
- Do NOT edit `identity/keycloak/realm-shopping-cart.json` — it is already correct
