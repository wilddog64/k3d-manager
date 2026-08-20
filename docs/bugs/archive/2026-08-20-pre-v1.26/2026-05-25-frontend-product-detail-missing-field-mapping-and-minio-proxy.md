# Bugfix: product detail page — missing field mapping in getProductById + no /minio/ nginx proxy

**Branch (k3d-manager spec):** `k3d-manager-v1.4.10`
**Branch (work):** `fix/product-detail-field-mapping` in `shopping-cart-frontend`
**Files:** `src/services/productService.ts`, `nginx.conf`

---

## Before You Start

```bash
# Step 1 — get the spec
git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.10

# Step 2 — read this spec in full before touching anything

# Step 3 — create the work branch in shopping-cart-frontend
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend \
  checkout -b fix/product-detail-field-mapping origin/main

# Step 4 — read both target files before editing:
# src/services/productService.ts
# nginx.conf
```

---

## Problem

Two bugs on the product detail page (`/products/:id`):

**Bug 1 — "Out of stock" on all products:**
`getProductById()` returns the raw API response without field mapping, so
`product.stock` is `undefined` (the API field is `quantity`). The detail page
checks `product.stock > 0`, which is always false — every product shows "Out of stock".

**Bug 2 — "No image available" on all products:**
`getProductById()` also skips `imageUrl` mapping, so `product.imageUrl` is
`undefined`. Even if it were set, `nginx.conf` has no `/minio/` location block,
so the image URL `/minio/product-images/<name>.jpg` would 404.

**Root cause (Bug 1 + 2):** `getProductById()` at `src/services/productService.ts:51-54`
passes `response.data` directly as `Product` instead of applying the same
`image_url → imageUrl` / `quantity → stock` mapping that `getProducts()` uses.

**Root cause (Bug 2 nginx):** `nginx.conf` has no `location /minio/` block, so
image requests pass through to the SPA fallback and return `index.html` (not the image).

---

## Reproduction

1. Browse to any product detail page while the cluster is running.
2. Page shows "No image available" (gray box) and "Out of stock" for every product,
   regardless of actual `quantity` in the DB.

---

## Fix

### Change 1 — `src/services/productService.ts`: apply field mapping in getProductById

**Exact old block (lines 51–54):**

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
    const p = response.data as Record<string, unknown>
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

### Change 2 — `nginx.conf`: add /minio/ proxy block before the SPA fallback

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
        proxy_pass http://basket-service.shopping-cart-apps.svc.cluster.local:8083;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /minio/ {
        proxy_pass http://minio.shopping-cart-data.svc.cluster.local:9000/;
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
| `src/services/productService.ts` | `getProductById()` — apply `image_url → imageUrl`, `quantity → stock` mapping |
| `nginx.conf` | Add `/minio/` proxy block → `minio.shopping-cart-data.svc.cluster.local:9000` |

---

## Rules

- `npm run build` must pass with zero new TypeScript errors
- `npm run lint` must pass with zero new errors
- Code change limited to `src/services/productService.ts` and `nginx.conf`; docs/memory-bank updates may also be required

---

## Definition of Done

- [ ] `getProductById()` applies identical field mapping to `getProducts()`
- [ ] `nginx.conf` has `/minio/` location block pointing to MinIO service
- [ ] `npm run build` passes
- [ ] `npm run lint` passes
- [ ] Copilot tagged on the PR: `gh api repos/wilddog64/shopping-cart-frontend/pulls/<n>/requested_reviewers -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'`
- [ ] Committed and pushed to `fix/product-detail-field-mapping` in `shopping-cart-frontend`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(product-detail): map quantity→stock and image_url→imageUrl in getProductById; add /minio/ nginx proxy
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `src/services/productService.ts` and `nginx.conf`
- Do NOT commit to `main` — work on `fix/product-detail-field-mapping` in `shopping-cart-frontend`
- Do NOT run `npm install` or change any dependencies
