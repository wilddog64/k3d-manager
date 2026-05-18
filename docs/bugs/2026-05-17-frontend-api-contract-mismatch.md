# Bug: Frontend–backend API contract mismatch — products blank, orders "Error loading"

**Branch:** `k3d-manager-v1.4.6`
**Work repo:** `shopping-cart-frontend` — branch `fix/frontend-api-contract`
**Files:**
- `src/services/productService.ts`
- `src/services/orderService.ts`
- `src/hooks/useOrders.ts`

---

## Before You Start

```
# In shopping-cart-frontend repo:
git checkout -b fix/frontend-api-contract origin/main
```

Read this spec in full before touching any file.

---

## Problem

Two API contract mismatches cause the UI to fail silently or show "Error loading":

### 1 — Products: response field names don't match the frontend type

The `product-catalog` FastAPI backend returns:
```json
{
  "items": [],
  "total": 0,
  "page": 1,
  "page_size": 20,
  "pages": 0
}
```

The frontend's `PaginatedResponse<Product>` type expects:
```typescript
{ data: Product[], totalItems: number, page: number, pageSize: number, totalPages: number }
```

`productService.getProducts()` returns `response.data` (the raw backend JSON) directly without
mapping. `ProductsPage` then calls `data?.data.map(...)` — `data.data` is `undefined` (backend
uses `items`). No error is thrown; the product grid renders nothing.

Per-product field mismatches (backend snake_case → frontend camelCase expectation):
- `image_url` → `imageUrl`
- `quantity` → `stock`
- `is_active` not in frontend type (safe to ignore)

### 2 — Orders: missing `customerId` param → 400 Bad Request

`orderService.getOrders()` calls `GET /api/orders?page=1&pageSize=10` without `customerId`.
The order-service controller requires `@RequestParam String customerId`. The backend returns
HTTP 400, and `OrdersPage` renders "Error loading orders".

`useOrders.ts` has `auth.isAuthenticated` guard and `const auth = useAuth()` but never
extracts `auth.user?.profile?.sub` to pass as `customerId`.

Additionally, the order-service returns a plain `List<OrderResponse>` (JSON array `[]`), but
`OrdersPage` expects `data.data` (i.e., a `PaginatedResponse<Order>` with `.data` field).
The `orderService` must wrap the array response into the `PaginatedResponse` shape to match
what the page component expects.

---

## Fix

### Change 1 — `src/services/productService.ts`: map backend response to frontend type

**Exact old `getProducts` function (lines 12–23):**
```typescript
async getProducts(params: GetProductsParams = {}): Promise<PaginatedResponse<Product>> {
    const { page = 1, pageSize = 12, category, search } = params
    const queryParams = new URLSearchParams({
      page: String(page),
      pageSize: String(pageSize),
    })

    if (category) queryParams.append('category', category)
    if (search) queryParams.append('search', search)

    const response = await api.get<PaginatedResponse<Product>>(
      `${ENDPOINTS.PRODUCTS}?${queryParams}`
    )
    return response.data
  },
```

**Exact new `getProducts` function:**
```typescript
async getProducts(params: GetProductsParams = {}): Promise<PaginatedResponse<Product>> {
    const { page = 1, pageSize = 12, category, search } = params
    const queryParams = new URLSearchParams({
      page: String(page),
      pageSize: String(pageSize),
    })

    if (category) queryParams.append('category', category)
    if (search) queryParams.append('search', search)

    const response = await api.get<Record<string, unknown>>(
      `${ENDPOINTS.PRODUCTS}?${queryParams}`
    )
    const raw = response.data as {
      items: Array<Record<string, unknown>>
      total: number
      page: number
      page_size: number
      pages: number
    }
    const mapped: PaginatedResponse<Product> = {
      data: raw.items.map((p) => ({
        id: String(p.id),
        name: String(p.name),
        description: String(p.description ?? ''),
        price: Number(p.price),
        currency: String(p.currency ?? 'USD'),
        category: String(p.category ?? ''),
        imageUrl: p.image_url ? String(p.image_url) : undefined,
        stock: Number(p.quantity ?? 0),
        createdAt: String(p.created_at ?? ''),
        updatedAt: String(p.updated_at ?? ''),
      })),
      page: raw.page,
      pageSize: raw.page_size,
      totalItems: raw.total,
      totalPages: raw.pages,
    }
    return mapped
  },
```

---

### Change 2 — `src/services/orderService.ts`: add `customerId` to params + wrap array response

**Exact old `GetOrdersParams` interface (lines 5–9):**
```typescript
export interface GetOrdersParams {
  page?: number
  pageSize?: number
  status?: string
}
```

**Exact new `GetOrdersParams` interface:**
```typescript
export interface GetOrdersParams {
  page?: number
  pageSize?: number
  status?: string
  customerId?: string
}
```

**Exact old `getOrders` function (lines 12–23):**
```typescript
async getOrders(params: GetOrdersParams = {}): Promise<PaginatedResponse<Order>> {
    const { page = 1, pageSize = 10, status } = params
    const queryParams = new URLSearchParams({
      page: String(page),
      pageSize: String(pageSize),
    })

    if (status) queryParams.append('status', status)

    const response = await api.get<PaginatedResponse<Order>>(`${ENDPOINTS.ORDERS}?${queryParams}`)
    return response.data
  },
```

**Exact new `getOrders` function:**
```typescript
async getOrders(params: GetOrdersParams = {}): Promise<PaginatedResponse<Order>> {
    const { page = 1, pageSize = 10, status, customerId } = params
    const queryParams = new URLSearchParams({
      page: String(page),
      pageSize: String(pageSize),
    })

    if (status) queryParams.append('status', status)
    if (customerId) queryParams.append('customerId', customerId)

    const response = await api.get<Order[]>(`${ENDPOINTS.ORDERS}?${queryParams}`)
    const items = Array.isArray(response.data) ? response.data : []
    return {
      data: items,
      page,
      pageSize,
      totalItems: items.length,
      totalPages: 1,
    }
  },
```

---

### Change 3 — `src/hooks/useOrders.ts`: pass Keycloak sub as `customerId`

**Exact old `useOrders` function (lines 5–13):**
```typescript
export function useOrders(params: GetOrdersParams = {}) {
  const auth = useAuth()

  return useQuery({
    queryKey: ['orders', params],
    queryFn: () => orderService.getOrders(params),
    enabled: auth.isAuthenticated,
  })
}
```

**Exact new `useOrders` function:**
```typescript
export function useOrders(params: GetOrdersParams = {}) {
  const auth = useAuth()
  const customerId = auth.user?.profile?.sub

  return useQuery({
    queryKey: ['orders', params, customerId],
    queryFn: () => orderService.getOrders({ ...params, customerId }),
    enabled: auth.isAuthenticated && !!customerId,
  })
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `src/services/productService.ts` | Map backend `{items, total, page_size, pages}` to `PaginatedResponse`; map `image_url` → `imageUrl`, `quantity` → `stock` |
| `src/services/orderService.ts` | Add `customerId` to `GetOrdersParams`; pass in query string; wrap `Order[]` array response in `PaginatedResponse` shape |
| `src/hooks/useOrders.ts` | Extract `auth.user?.profile?.sub` as `customerId`; pass to `getOrders`; gate on `!!customerId` |

---

## Rules

- No other files modified
- Do NOT modify backend services — all fixes are frontend-only adapters
- TypeScript must compile without errors: `npm run type-check` or `npx tsc --noEmit`
- `customerId` must only be appended to the query string when it is truthy (non-empty)
- The product mapper must handle `null`/`undefined` fields safely (use `??` defaults)

---

## Definition of Done

- [ ] `src/services/productService.ts` — `getProducts` maps backend fields to frontend types
- [ ] `src/services/orderService.ts` — `GetOrdersParams` has `customerId`; `getOrders` passes it; wraps array in paginated shape
- [ ] `src/hooks/useOrders.ts` — passes `customerId = auth.user?.profile?.sub`; gates on `!!customerId`
- [ ] `npx tsc --noEmit` (or equivalent) passes with zero type errors in the changed files
- [ ] Committed to branch `fix/frontend-api-contract` with message:
      `fix(frontend): map backend API response fields and pass customerId from Keycloak profile`
- [ ] `git push origin fix/frontend-api-contract` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed
- Do NOT commit to `main` — work on `fix/frontend-api-contract`
- Do NOT modify the backend (product-catalog, order-service) — this is a frontend adapter only
- Do NOT modify `useProduct`, `useCategories`, `getProductById`, or any other hook/service

---

## Expected Result After Fix

- **Products page**: shows products grid (or "No products found." if DB empty)
- **Orders page**: shows "No orders yet" with a "Start Shopping" link (since no orders exist for new users)
- No "Error loading" messages for either page
