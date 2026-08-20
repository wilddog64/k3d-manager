# Bug: Node.js 20 deprecation — upgrade to 22 in CI and Dockerfile

**Date:** 2026-05-22
**Repos:** `shopping-cart-frontend`, `shopping-cart-e2e-tests`

## Problem

Node.js 20 reaches end-of-life October 2026. GitHub Actions emits deprecation warnings.
Two repos pin to Node.js 20 in CI workflows; `shopping-cart-frontend` also pins it in
its Dockerfile build stage.

## Before You Start

1. Read this file in full.
2. In `shopping-cart-frontend`: `git pull origin docs/next-improvements`
3. In `shopping-cart-e2e-tests`: `git checkout -b docs/next-improvements origin/main`
4. Read each target file before editing.

**Branches:**
- `shopping-cart-frontend`: `docs/next-improvements` (already exists)
- `shopping-cart-e2e-tests`: `docs/next-improvements` (create from main)

---

## Fix 1 — `shopping-cart-frontend/.github/workflows/ci.yml`

Replace all six occurrences of `node-version: '20'` with `node-version: '22'`.
They appear at lines 24, 45, 63, 88, 118, 144 — every `Setup Node.js` step in the file.

```yaml
# OLD (repeated 6 times)
          node-version: '20'

# NEW (repeated 6 times)
          node-version: '22'
```

---

## Fix 2 — `shopping-cart-frontend/Dockerfile`

```dockerfile
# OLD
FROM node:20-alpine AS builder

# NEW
FROM node:22-alpine AS builder
```

---

## Fix 3 — `shopping-cart-e2e-tests/.github/workflows/e2e-tests.yml`

```yaml
# OLD
  NODE_VERSION: '20'

# NEW
  NODE_VERSION: '22'
```

---

## Definition of Done

- [ ] `shopping-cart-frontend/.github/workflows/ci.yml` — all 6 `node-version: '20'` changed to `'22'`
- [ ] `shopping-cart-frontend/Dockerfile` — `FROM node:20-alpine` changed to `FROM node:22-alpine`
- [ ] `shopping-cart-e2e-tests/.github/workflows/e2e-tests.yml` — `NODE_VERSION: '20'` changed to `'22'`
- [ ] Commit in `shopping-cart-frontend` with message: `chore(ci): upgrade Node.js 20 → 22 in CI workflow and Dockerfile`
- [ ] Commit in `shopping-cart-e2e-tests` with message: `chore(ci): upgrade Node.js 20 → 22`
- [ ] Both commits pushed to `docs/next-improvements` on origin in each repo
- [ ] Report back: one SHA per repo + confirm push succeeded

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the three listed targets
- Do NOT commit to `main`
- Do NOT change any other version numbers (nginx, Playwright, etc.)
