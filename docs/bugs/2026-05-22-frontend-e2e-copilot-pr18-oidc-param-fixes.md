# Bug: E2E OIDC auth mock uses misleading variable name and hardcodes realm/clientId

**Date:** 2026-05-22
**Repo:** shopping-cart-frontend
**Branch:** docs/next-improvements
**PR:** #18 — Copilot review findings (12 threads)

## Root Cause

1. `_keycloakUrl` — leading underscore convention means "unused"; this variable IS used.
2. `localStorage.setItem` key hardcodes `/realms/shopping-cart:frontend` — these should
   come from `VITE_KEYCLOAK_REALM` and `VITE_CLIENT_ID` env vars (already in `ci.yml`
   workflow-level env block), matching how `src/config/auth.ts` builds the key at runtime.
3. `products.spec.ts` comment claims `/products` is auth-gated, but `src/App.tsx` does
   NOT wrap `ProductsPage` in `<ProtectedRoute>`.
4. `docs/issues/2026-05-22-nodejs20-deprecation.md` has 3 inaccuracies Copilot flagged.

## Before You Start

1. Read this file in full.
2. `git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend pull origin docs/next-improvements`
3. Read each target file before editing.
4. Branch (work repo): `docs/next-improvements` in `shopping-cart-frontend`

## Fix Pattern — auth mock blocks

Replace every auth mock block across all 6 occurrences (2 in cart.spec.ts, 3 in
orders.spec.ts, 1 in products.spec.ts):

```typescript
// BEFORE
const _keycloakUrl = process.env.VITE_KEYCLOAK_URL || 'http://localhost:8080'
await page.addInitScript((_keycloakUrl) => {
  const mockUser = {
    access_token: 'mock-token',
    token_type: 'Bearer',
    profile: {
      sub: 'user-123',
      name: 'Test User',
      email: 'test@example.com',
    },
    expires_at: Math.floor(Date.now() / 1000) + 3600,
  }
  localStorage.setItem(
    `oidc.user:${_keycloakUrl}/realms/shopping-cart:frontend`,
    JSON.stringify(mockUser)
  )
}, _keycloakUrl)

// AFTER
const keycloakUrl = process.env.VITE_KEYCLOAK_URL || 'http://localhost:8080'
const keycloakRealm = process.env.VITE_KEYCLOAK_REALM || 'shopping-cart'
const clientId = process.env.VITE_CLIENT_ID || 'frontend'
await page.addInitScript(({ keycloakUrl, keycloakRealm, clientId }) => {
  const mockUser = {
    access_token: 'mock-token',
    token_type: 'Bearer',
    profile: {
      sub: 'user-123',
      name: 'Test User',
      email: 'test@example.com',
    },
    expires_at: Math.floor(Date.now() / 1000) + 3600,
  }
  localStorage.setItem(
    `oidc.user:${keycloakUrl}/realms/${keycloakRealm}:${clientId}`,
    JSON.stringify(mockUser)
  )
}, { keycloakUrl, keycloakRealm, clientId })
```

## Exact Changes

### `e2e/cart.spec.ts` — occurrence 1 (Cart Page (Authenticated) beforeEach, ~line 21)

```typescript
// OLD (lines 21–37)
    const _keycloakUrl = process.env.VITE_KEYCLOAK_URL || 'http://localhost:8080'
    await page.addInitScript((_keycloakUrl) => {
      const mockUser = {
        access_token: 'mock-token',
        token_type: 'Bearer',
        profile: {
          sub: 'user-123',
          name: 'Test User',
          email: 'test@example.com',
        },
        expires_at: Math.floor(Date.now() / 1000) + 3600,
      }
      localStorage.setItem(
        `oidc.user:${_keycloakUrl}/realms/shopping-cart:frontend`,
        JSON.stringify(mockUser)
      )
    }, _keycloakUrl)

// NEW
    const keycloakUrl = process.env.VITE_KEYCLOAK_URL || 'http://localhost:8080'
    const keycloakRealm = process.env.VITE_KEYCLOAK_REALM || 'shopping-cart'
    const clientId = process.env.VITE_CLIENT_ID || 'frontend'
    await page.addInitScript(({ keycloakUrl, keycloakRealm, clientId }) => {
      const mockUser = {
        access_token: 'mock-token',
        token_type: 'Bearer',
        profile: {
          sub: 'user-123',
          name: 'Test User',
          email: 'test@example.com',
        },
        expires_at: Math.floor(Date.now() / 1000) + 3600,
      }
      localStorage.setItem(
        `oidc.user:${keycloakUrl}/realms/${keycloakRealm}:${clientId}`,
        JSON.stringify(mockUser)
      )
    }, { keycloakUrl, keycloakRealm, clientId })
```

### `e2e/cart.spec.ts` — occurrence 2 (Empty Cart beforeEach, ~line 118)

Same replacement — the block at ~lines 118–134 is identical in structure.

### `e2e/orders.spec.ts` — occurrence 1 (Orders Page beforeEach, ~line 6)

Same replacement pattern.

### `e2e/orders.spec.ts` — occurrence 2 (Order Detail Page beforeEach, ~line 140)

Same replacement pattern.

### `e2e/orders.spec.ts` — occurrence 3 (Empty Orders beforeEach, ~line 226)

Same replacement pattern.

### `e2e/products.spec.ts` — occurrence 1 (Products Page beforeEach, ~line 5)

Same replacement pattern, PLUS: change the comment on the line before `const keycloakUrl`:

```typescript
// OLD comment
    // Mock authentication — /products is auth-gated

// NEW comment
    // Mock authentication — ProductsPage makes authenticated API calls
```

(`/products` is NOT wrapped in ProtectedRoute per src/App.tsx; the auth mock is needed
because ProductsPage sends a Bearer token in API requests.)

## Exact Change — `docs/issues/2026-05-22-nodejs20-deprecation.md`

### Fix 1: Wrong attribution (line 25)

```
// OLD
The warning is about the **app's Node.js version** (`node-version: '20'`), not the action
versions. Node.js 22 is the current LTS (since April 2025).

// NEW
The deprecation warning is produced by `actions/checkout@v4` and `actions/setup-node@v4`
which use a Node.js 20 internal runtime. Changing `node-version: '20'` → `'22'` upgrades
the app build runtime. To also silence the action warning, upgrade to `checkout@v5` /
`setup-node@v5`. Node.js 22 is the current LTS (since April 2025).
```

### Fix 2: Wrong job count (line 30)

```
// OLD
- `shopping-cart-frontend` — `ci.yml` has 5 jobs each with `node-version: '20'`

// NEW
- `shopping-cart-frontend` — `ci.yml` has 6 jobs each with `node-version: '20'`
```

### Fix 3: False centralization claim (line 38)

```
// OLD
Since `node-version` is now centralized as a workflow-level env var in `shopping-cart-frontend`
(added in PR #17), the fix there is a single-line change:

// NEW
The workflow already centralizes `VITE_KEYCLOAK_URL`, `VITE_KEYCLOAK_REALM`, and
`VITE_CLIENT_ID` as top-level env vars. Add `NODE_VERSION` to the same block to
centralize the node version:
```

## Rules

- Do NOT run `npm test` or `npx playwright test` — no local cluster available
- Do NOT modify any files outside the four listed files
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT commit to `main`
- Run `node --check e2e/cart.spec.ts e2e/orders.spec.ts e2e/products.spec.ts` after edits to verify TypeScript syntax

## Definition of Done

- [ ] All 6 `_keycloakUrl` → `keycloakUrl` renames done (2 cart, 3 orders, 1 products)
- [ ] All 6 auth mock blocks updated to pass `{ keycloakUrl, keycloakRealm, clientId }` object
- [ ] All 6 localStorage keys use `${keycloakUrl}/realms/${keycloakRealm}:${clientId}`
- [ ] `products.spec.ts` comment changed to "ProductsPage makes authenticated API calls"
- [ ] `docs/issues/2026-05-22-nodejs20-deprecation.md` 3 accuracy fixes applied
- [ ] `node --check` passes on all three spec files
- [ ] Committed to `docs/next-improvements` in `shopping-cart-frontend`
- [ ] Pushed: `git push origin docs/next-improvements`
- [ ] Commit message: `fix(e2e): rename keycloakUrl var, add realm/clientId env params, fix deprecation doc`
- [ ] Memory-bank NOT touched (no memory-bank in shopping-cart-frontend)
- [ ] Report: commit SHA only
