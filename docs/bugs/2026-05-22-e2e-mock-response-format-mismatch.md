# Bug: E2E route mock response format mismatches orderService and productService expectations

**Date:** 2026-05-22
**Repo:** shopping-cart-frontend
**Branch:** docs/next-improvements
**PR:** #18 — CI failure after OIDC auth mock fix

## Root Cause

The OIDC auth mock fix (PR #18 `1ee323f`) made auth work correctly in CI, which allowed
`/orders` and `/products` pages to actually load and call their APIs. This revealed two
pre-existing mock format mismatches:

1. **`Orders Page` route mock** (`orders.spec.ts` `Orders Page > beforeEach`) returns
   `{ data: [...], page, pageSize, totalItems, totalPages }` but `orderService.getOrders`
   (`src/services/orderService.ts`) does:
   ```ts
   const items = Array.isArray(response.data) ? response.data : []
   ```
   The mock wraps orders in a `data` key, so `response.data` is an object, not an array →
   `Array.isArray` = false → `items = []` → component shows "No orders yet" instead of
   "My Orders" heading with order list.

2. **`Products Page` route mock** (`products.spec.ts` `Products Page > beforeEach`) returns
   `{ data: [...], pageSize, totalItems, totalPages }` with camelCase fields (`stock`,
   `createdAt`, `updatedAt`) but `productService.getProducts`
   (`src/services/productService.ts`) does:
   ```ts
   const raw = response.data as { items: [...], total, page, page_size, pages }
   return { data: raw.items.map((p) => ({ ..., stock: Number(p.quantity ?? 0), ... })) }
   ```
   `raw.items` is `undefined` → `raw.items.map(...)` throws TypeError → component error
   state → products never render.

## Before You Start

1. Read this file in full.
2. `git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend pull origin docs/next-improvements`
3. Read each target file before editing.
4. Branch (work repo): `docs/next-improvements` in `shopping-cart-frontend`
5. Do NOT run Playwright tests (no local app server available in CI) — verify with
   `node --check` after edits.

## Fix 1: `e2e/orders.spec.ts` — Orders Page route mock else branch

The else branch at the end of the `page.route('**/api/orders**', ...)` handler in the
`Orders Page` `beforeEach` (~line 52) must return a plain JSON array, not a paginated
wrapper object.

### Exact change (lines 52–103)

```typescript
// OLD — else branch (lines 52–103, ending just before the closing })
        } else {
          await route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
              data: [
                {
                  id: 'order-1',
                  customerId: 'user-123',
                  items: [
                    {
                      id: 'item-1',
                      productId: 'prod-1',
                      name: 'Test Product',
                      quantity: 2,
                      unitPrice: 29.99,
                      subTotal: 59.98,
                    },
                  ],
                  totalAmount: 59.98,
                  currency: 'USD',
                  status: 'CONFIRMED',
                  createdAt: '2024-01-15T10:30:00Z',
                  updatedAt: '2024-01-15T10:30:00Z',
                },
                {
                  id: 'order-2',
                  customerId: 'user-123',
                  items: [
                    {
                      id: 'item-2',
                      productId: 'prod-2',
                      name: 'Another Product',
                      quantity: 1,
                      unitPrice: 49.99,
                      subTotal: 49.99,
                    },
                  ],
                  totalAmount: 49.99,
                  currency: 'USD',
                  status: 'DELIVERED',
                  createdAt: '2024-01-10T14:00:00Z',
                  updatedAt: '2024-01-12T09:00:00Z',
                },
              ],
              page: 1,
              pageSize: 10,
              totalItems: 2,
              totalPages: 1,
            }),
          })
        }

// NEW — same else branch, body is a plain array (no wrapper object)
        } else {
          await route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify([
              {
                id: 'order-1',
                customerId: 'user-123',
                items: [
                  {
                    id: 'item-1',
                    productId: 'prod-1',
                    name: 'Test Product',
                    quantity: 2,
                    unitPrice: 29.99,
                    subTotal: 59.98,
                  },
                ],
                totalAmount: 59.98,
                currency: 'USD',
                status: 'CONFIRMED',
                createdAt: '2024-01-15T10:30:00Z',
                updatedAt: '2024-01-15T10:30:00Z',
              },
              {
                id: 'order-2',
                customerId: 'user-123',
                items: [
                  {
                    id: 'item-2',
                    productId: 'prod-2',
                    name: 'Another Product',
                    quantity: 1,
                    unitPrice: 49.99,
                    subTotal: 49.99,
                  },
                ],
                totalAmount: 49.99,
                currency: 'USD',
                status: 'DELIVERED',
                createdAt: '2024-01-10T14:00:00Z',
                updatedAt: '2024-01-12T09:00:00Z',
              },
            ]),
          })
        }
```

## Fix 2: `e2e/products.spec.ts` — Products Page route mock

The `page.route('**/api/products**', ...)` handler in `Products Page > beforeEach`
(~lines 27–74) must use:
- Top-level key `items` (not `data`)
- Pagination keys `total`, `page_size`, `pages` (not `pageSize`, `totalItems`, `totalPages`)
- Per-item field names `quantity` (not `stock`), `image_url`, `created_at`, `updated_at`
  (not `createdAt`, `updatedAt`)

### Exact change (lines 26–74)

```typescript
// OLD
    // Mock the products API
    await page.route('**/api/products**', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: [
            {
              id: 'prod-1',
              name: 'Test Product 1',
              description: 'A great test product',
              price: 29.99,
              currency: 'USD',
              category: 'Electronics',
              stock: 10,
              createdAt: '2024-01-01',
              updatedAt: '2024-01-01',
            },
            {
              id: 'prod-2',
              name: 'Test Product 2',
              description: 'Another great product',
              price: 49.99,
              currency: 'USD',
              category: 'Clothing',
              stock: 5,
              createdAt: '2024-01-01',
              updatedAt: '2024-01-01',
            },
            {
              id: 'prod-3',
              name: 'Out of Stock Item',
              description: 'This item is unavailable',
              price: 99.99,
              currency: 'USD',
              category: 'Electronics',
              stock: 0,
              createdAt: '2024-01-01',
              updatedAt: '2024-01-01',
            },
          ],
          page: 1,
          pageSize: 12,
          totalItems: 3,
          totalPages: 1,
        }),
      })
    })

// NEW
    // Mock the products API
    await page.route('**/api/products**', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          items: [
            {
              id: 'prod-1',
              name: 'Test Product 1',
              description: 'A great test product',
              price: 29.99,
              currency: 'USD',
              category: 'Electronics',
              quantity: 10,
              image_url: null,
              created_at: '2024-01-01',
              updated_at: '2024-01-01',
            },
            {
              id: 'prod-2',
              name: 'Test Product 2',
              description: 'Another great product',
              price: 49.99,
              currency: 'USD',
              category: 'Clothing',
              quantity: 5,
              image_url: null,
              created_at: '2024-01-01',
              updated_at: '2024-01-01',
            },
            {
              id: 'prod-3',
              name: 'Out of Stock Item',
              description: 'This item is unavailable',
              price: 99.99,
              currency: 'USD',
              category: 'Electronics',
              quantity: 0,
              image_url: null,
              created_at: '2024-01-01',
              updated_at: '2024-01-01',
            },
          ],
          total: 3,
          page: 1,
          page_size: 12,
          pages: 1,
        }),
      })
    })
```

## Rules

- Do NOT run `npx playwright test` — no local app server available
- Do NOT modify any files outside the two listed files
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT commit to `main`
- Run `node --check e2e/orders.spec.ts e2e/products.spec.ts` after edits to verify TypeScript syntax

## Definition of Done

- [ ] `e2e/orders.spec.ts` `Orders Page` `beforeEach` else branch returns a plain JSON array
      (no `data` wrapper, no `page`/`pageSize`/`totalItems`/`totalPages` keys)
- [ ] `e2e/products.spec.ts` `Products Page` `beforeEach` route mock uses `items`, `total`,
      `page_size`, `pages` keys and `quantity`, `image_url`, `created_at`, `updated_at`
      per-item field names
- [ ] `node --check e2e/orders.spec.ts e2e/products.spec.ts` passes
- [ ] Committed to `docs/next-improvements` in `shopping-cart-frontend`
- [ ] Pushed: `git push origin docs/next-improvements`
- [ ] Commit message: `fix(e2e): correct route mock response formats for orders list and products list`
- [ ] Memory-bank NOT touched (no memory-bank in shopping-cart-frontend)
- [ ] Report: commit SHA only
