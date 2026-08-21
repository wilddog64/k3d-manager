# Bugfix: Frontend — product display only laptops, "Out of stock" wrong, add-to-cart 404

**Branch (shopping-cart-frontend):** `fix/product-display-cart-bugs` (create from `main`)
**Repo:** `~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend/`
**Files:**
- `src/services/productService.ts`
- `nginx.conf`

---

## Problem

Three runtime bugs observed after fresh login:

### Bug 1 — Product list shows only laptops (pageSize param typo)

`productService.ts` sends `pageSize=12` but the product catalog API expects `page_size`.
The API ignores the unknown param and returns products with its default page size, ordered
by insertion order. Since all 50 laptop products were inserted first during seeding, only
laptops appear on every page.

**Root cause:** Line 18 uses `pageSize` (camelCase) instead of `page_size` (snake_case).

### Bug 2 — Product detail shows "Out of stock" for every product

`getProductById` returns raw API response data without field mapping. The API returns
`quantity` but the `Product` interface expects `stock`. So `product.stock` is `undefined`,
and `product.stock > 0` evaluates to `false` → always shows "Out of stock".

`getProducts` correctly maps `quantity → stock` on line 42, but `getProductById` (lines
53–55) returns `response.data` raw with no mapping.

**Root cause:** Missing field mapping in `getProductById`.

### Bug 3 — "Failed to add to cart" (404)

nginx proxies `POST /api/cart/items` to basket-service, but basket service routes are
registered under `/api/v1/cart/items` (versioned). The request arrives at basket service
as `POST /api/cart/items` which matches no route → 404.

**Root cause:** nginx `location /api/cart` passes path unchanged; basket service expects
`/api/v1/cart`.

Fix: change `proxy_pass` URI to include `/api/v1/cart` so nginx rewrites the path prefix.

---

## Fix

### Change 1 — `src/services/productService.ts`: fix `pageSize` → `page_size`

**Exact old block (lines 16–19):**

```typescript
    const queryParams = new URLSearchParams({
      page: String(page),
      pageSize: String(pageSize),
    })
```

**Exact new block:**

```typescript
    const queryParams = new URLSearchParams({
      page: String(page),
      page_size: String(pageSize),
    })
```

### Change 2 — `src/services/productService.ts`: map fields in `getProductById`

**Exact old block (lines 53–56):**

```typescript
  async getProductById(id: string): Promise<Product> {
    const response = await api.get<Product>(ENDPOINTS.PRODUCT_BY_ID(id))
    return response.data
  },
```

**Exact new block:**

```typescript
  async getProductById(id: string): Promise<Product> {
    const response = await api.get<Record<string, unknown>>(ENDPOINTS.PRODUCT_BY_ID(id))
    const p = response.data
    return {
      id: String(p.id),
      name: String(p.name),
      description: String(p.description ?? ''),
      price: Number(p.price ?? 0),
      currency: String(p.currency ?? 'USD'),
      category: String(p.category ?? ''),
      imageUrl: p.image_url ? String(p.image_url) : undefined,
      stock: Number(p.quantity ?? 0),
      createdAt: String(p.created_at ?? ''),
      updatedAt: String(p.updated_at ?? ''),
    }
  },
```

### Change 3 — `nginx.conf`: fix basket service path prefix

**Exact old block (lines 54–61):**

```nginx
    location /api/cart {
        proxy_pass http://basket-service.shopping-cart-apps.svc.cluster.local:8083;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

**Exact new block:**

```nginx
    location /api/cart {
        proxy_pass http://basket-service.shopping-cart-apps.svc.cluster.local:8083/api/v1/cart;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

---

## Files Changed

| File | Change |
|------|--------|
| `src/services/productService.ts` | Fix `pageSize` → `page_size`; add field mapping in `getProductById` |
| `nginx.conf` | Fix proxy_pass to include `/api/v1/cart` path prefix |

---

## Rules

- Do NOT modify any file other than the two listed targets
- `npm run build` must succeed with zero type errors after the change
- `npm run lint` must pass (or match pre-existing lint state)

---

## Definition of Done

- [ ] `src/services/productService.ts` — `page_size` param name used in `getProducts`
- [ ] `src/services/productService.ts` — `getProductById` maps `quantity → stock` and all other fields
- [ ] `nginx.conf` — proxy_pass for `/api/cart` includes `/api/v1/cart` path
- [ ] `npm run build` passes (zero type errors)
- [ ] Committed and pushed to `fix/product-display-cart-bugs` on `shopping-cart-frontend`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(frontend): page_size param, getProductById field mapping, cart proxy v1 path
```

---

## What NOT to Do

- Do NOT create a PR (Claude will handle that)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the two listed targets
- Do NOT commit to `main` — work on `fix/product-display-cart-bugs`
- Do NOT change the basket service Go code — nginx fix is sufficient
