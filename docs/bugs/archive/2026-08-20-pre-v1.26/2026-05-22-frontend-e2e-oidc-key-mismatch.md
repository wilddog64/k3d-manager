# Bug: Frontend E2E authenticated tests fail in CI due to OIDC localStorage key mismatch

**Date:** 2026-05-22
**Repo:** shopping-cart-frontend
**Branch:** docs/next-improvements
**Symptom:** All "Authenticated" Playwright tests fail in CI — app redirects to
`keycloak.3ai-talk.org` instead of rendering the authenticated page.

## Root Cause

E2E tests mock auth by setting a localStorage key with a hardcoded Keycloak URL:
```
oidc.user:http://localhost:8080/realms/shopping-cart:frontend
```

The OIDC library derives this key from the actual issuer URL. In CI, the app is
configured with `VITE_KEYCLOAK_URL=https://keycloak.3ai-talk.org`, so it looks up:
```
oidc.user:https://keycloak.3ai-talk.org/realms/shopping-cart:frontend
```

Key mismatch → app sees no auth → redirects to real Keycloak → tests time out.

## Files to Change

- `e2e/cart.spec.ts` — 2 occurrences (lines 21–35 and 114–132)
- `e2e/orders.spec.ts` — 3 occurrences (lines 6–21, 139–154, 225–240)
- `e2e/products.spec.ts` — 0 occurrences; `Products Page` beforeEach has no auth
  mock at all; `/products` is auth-gated so those tests also fail — add one

## Before You Start

1. Read this file in full.
2. `git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend pull origin docs/next-improvements`
3. Read each target file before editing.
4. Branch (work repo): `docs/next-improvements` in `shopping-cart-frontend`

## Fix Pattern

Replace every `page.addInitScript(() => { ... localStorage.setItem('oidc.user:http://localhost:8080/...', ...) })` block with the parameterized form that reads `VITE_KEYCLOAK_URL` from the Node.js environment:

```typescript
// BEFORE
await page.addInitScript(() => {
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
    'oidc.user:http://localhost:8080/realms/shopping-cart:frontend',
    JSON.stringify(mockUser)
  )
})

// AFTER
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
```

## Exact Changes

### `e2e/cart.spec.ts` — occurrence 1 (Cart Page (Authenticated) beforeEach)

```typescript
// OLD (lines 21–36)
    await page.addInitScript(() => {
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
        'oidc.user:http://localhost:8080/realms/shopping-cart:frontend',
        JSON.stringify(mockUser)
      )
    })

// NEW
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
```

### `e2e/cart.spec.ts` — occurrence 2 (Empty Cart beforeEach)

Same replacement — the block at lines 114–132 is identical in structure.

### `e2e/orders.spec.ts` — occurrence 1 (Orders Page beforeEach, lines 6–21)

```typescript
// OLD
    await page.addInitScript(() => {
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
        'oidc.user:http://localhost:8080/realms/shopping-cart:frontend',
        JSON.stringify(mockUser)
      )
    })

// NEW (same pattern as cart.spec.ts)
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
```

### `e2e/orders.spec.ts` — occurrences 2 and 3

Occurrence 2 is in `Order Detail Page` beforeEach (lines ~139–154). Occurrence 3 is in
`Empty Orders` beforeEach (lines ~225–240). Both are identical in structure — apply the
same replacement.

### `e2e/products.spec.ts` — add auth mock to `Products Page` beforeEach

The `Products Page` `test.describe` block starts with a `beforeEach` that only mocks
the products API. Add the auth mock BEFORE the `page.route` call:

```typescript
// OLD (lines 4–5, start of beforeEach)
  test.beforeEach(async ({ page }) => {
    // Mock the products API

// NEW
  test.beforeEach(async ({ page }) => {
    // Mock authentication — /products is auth-gated
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

    // Mock the products API
```

## Rules

- Do NOT run `npm test` or `npx playwright test` — no local cluster available in CI
- Do NOT modify any files outside the three listed spec files
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT commit to `main`

## Definition of Done

- [ ] All 5 `localStorage.setItem` call sites updated (2 in cart.spec.ts, 3 in orders.spec.ts)
- [ ] Auth mock added to `products.spec.ts` `Products Page` beforeEach
- [ ] `node --check` passes on all three files (TypeScript syntax valid)
- [ ] Committed to `docs/next-improvements` in `shopping-cart-frontend`
- [ ] Pushed: `git push origin docs/next-improvements`
- [ ] Commit message: `fix(e2e): resolve OIDC localStorage key to match VITE_KEYCLOAK_URL`
- [ ] Memory-bank NOT touched (no memory-bank in shopping-cart-frontend)
- [ ] Report: commit SHA only
