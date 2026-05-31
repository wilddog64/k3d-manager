# Bugfix: shopping-cart-frontend cartService response wrapper not unwrapped — "Failed to add to cart"

**Branch (k3d-manager spec):** `k3d-manager-v1.4.10`
**Branch (work):** `fix/cart-response-unwrap` in `shopping-cart-frontend`
**Files:** `src/services/cartService.ts`

---

## Before You Start

```bash
# Step 1 — get the spec
git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.10

# Step 2 — read this spec in full before touching anything

# Step 3 — create the work branch in shopping-cart-frontend
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend \
  checkout -b fix/cart-response-unwrap origin/main

# Step 4 — read the target file before editing:
# src/services/cartService.ts
```

---

## Problem

Clicking "Add to Cart" shows "Failed to add to cart" even though the basket-service returns HTTP 201.

The basket-service wraps every response body in `{ success: boolean; data: T }`:

```json
{
  "success": true,
  "data": {
    "id": "...",
    "customerId": "...",
    "items": [...],
    "totalAmount": 9.99,
    ...
  }
}
```

But `cartService.addItem()` returns `response.data` (the full Axios response body) directly as a `Cart`. So the `useAddToCart` mutation's `onSuccess(cart)` receives `{ success: true, data: {...} }` instead of the `Cart`. When `setCart(cart)` calls `updateItemCount()`, it runs `cart?.items.reduce(...)` — `cart.items` is `undefined`, throwing a `TypeError`. The mutation transitions to error state and "Failed to add to cart" is displayed.

**Root cause:** `cartService.ts` — all methods that return `Cart` or `{ orderId: string }` use `response.data` without unwrapping the `data` field from the wrapper envelope.

---

## Reproduction

1. Log in and open any product detail page.
2. Click "Add to Cart".
3. Observe "Failed to add to cart" despite basket-service logs showing status 201.

---

## Fix

### Change 1 — `src/services/cartService.ts`: unwrap `response.data.data` for all cart methods

**Exact old file contents:**

```typescript
import api from './api'
import { ENDPOINTS } from '@/config/api'
import type { Cart, AddToCartRequest, UpdateCartItemRequest } from '@/types'

export const cartService = {
  async getCart(): Promise<Cart> {
    const response = await api.get<Cart>(ENDPOINTS.CART)
    return response.data
  },

  async addItem(item: AddToCartRequest): Promise<Cart> {
    const response = await api.post<Cart>(ENDPOINTS.CART_ITEMS, item)
    return response.data
  },

  async updateItem(itemId: string, data: UpdateCartItemRequest): Promise<Cart> {
    const response = await api.put<Cart>(ENDPOINTS.CART_ITEM_BY_ID(itemId), data)
    return response.data
  },

  async removeItem(itemId: string): Promise<Cart> {
    const response = await api.delete<Cart>(ENDPOINTS.CART_ITEM_BY_ID(itemId))
    return response.data
  },

  async clearCart(): Promise<void> {
    await api.delete(ENDPOINTS.CART)
  },

  async checkout(): Promise<{ orderId: string }> {
    const response = await api.post<{ orderId: string }>(ENDPOINTS.CART_CHECKOUT)
    return response.data
  },
}
```

**Exact new file contents:**

```typescript
import api from './api'
import { ENDPOINTS } from '@/config/api'
import type { Cart, AddToCartRequest, UpdateCartItemRequest } from '@/types'

type Wrapped<T> = { success: boolean; data: T }

export const cartService = {
  async getCart(): Promise<Cart> {
    const response = await api.get<Wrapped<Cart>>(ENDPOINTS.CART)
    return response.data.data
  },

  async addItem(item: AddToCartRequest): Promise<Cart> {
    const response = await api.post<Wrapped<Cart>>(ENDPOINTS.CART_ITEMS, item)
    return response.data.data
  },

  async updateItem(itemId: string, data: UpdateCartItemRequest): Promise<Cart> {
    const response = await api.put<Wrapped<Cart>>(ENDPOINTS.CART_ITEM_BY_ID(itemId), data)
    return response.data.data
  },

  async removeItem(itemId: string): Promise<Cart> {
    const response = await api.delete<Wrapped<Cart>>(ENDPOINTS.CART_ITEM_BY_ID(itemId))
    return response.data.data
  },

  async clearCart(): Promise<void> {
    await api.delete(ENDPOINTS.CART)
  },

  async checkout(): Promise<{ orderId: string }> {
    const response = await api.post<Wrapped<{ orderId: string }>>(ENDPOINTS.CART_CHECKOUT)
    return response.data.data
  },
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `src/services/cartService.ts` | Add `Wrapped<T>` type alias; change `response.data` → `response.data.data` for all methods except `clearCart` (204 No Content, no body) |

---

## Rules

- Code change limited to `src/services/cartService.ts` only
- No other files touched
- `npm run type-check` must pass with zero errors after the change

---

## Definition of Done

- [ ] `src/services/cartService.ts` updated — all cart/checkout methods return `response.data.data`
- [ ] `clearCart()` unchanged (204 No Content, no response body)
- [ ] `npm run type-check` passes with zero errors
- [ ] Copilot tagged on the PR: `gh api repos/wilddog64/shopping-cart-frontend/pulls/<n>/requested_reviewers -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'`
- [ ] Committed and pushed to `fix/cart-response-unwrap` in `shopping-cart-frontend`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(cart): unwrap basket-service response envelope in cartService — response.data.data not response.data
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `src/services/cartService.ts`
- Do NOT commit to `main` — work on `fix/cart-response-unwrap` in `shopping-cart-frontend`
- Do NOT run `npm install` or change any dependencies
