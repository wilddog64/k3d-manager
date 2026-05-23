# Plan: 1,000-Product Seed + Full-Text Search + MinIO Image URLs

**Date:** 2026-05-23
**Repos:**
- `shopping-cart-product-catalog` — branch `docs/next-improvements`
- `shopping-cart-frontend` — branch `docs/next-improvements-2`

**Depends on:** `2026-05-23-minio-data-layer.md` — MinIO must be running and
`product-images` bucket must contain images before this seed job runs.

## Before You Start

1. `git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog pull origin docs/next-improvements`
2. `git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend pull origin docs/next-improvements-2`
3. Read `shopping-cart-infra/docs/minio-image-pipeline.md` — understand the 20 image slugs and the `/minio/product-images/<slug>.jpg` URL pattern
4. Read `shopping-cart-product-catalog/src/product_catalog/routers/products.py` — understand the existing `list_products` function before adding FTS
5. Read `shopping-cart-frontend/nginx.conf` — understand the existing proxy locations before adding `/minio/`
6. Read `shopping-cart-frontend/src/services/productService.ts` — understand the existing `getProducts` call before adding `q` param

## Task

Three sub-tasks, all in one commit per repo:

1. **Product catalog** — replace 8-row seed job with 1,000-product Python generator; add FTS GIN index job; add `?q=` search to the API
2. **Frontend** — add nginx `/minio/` proxy; wire search input to `?q=` API param

---

## shopping-cart-product-catalog changes

### File A: `k8s/base/seed-job-configmap.yaml` (new)

ConfigMap with the Python seed script that generates 1,000 products with MinIO image URLs.

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: product-catalog-seed-script
  namespace: shopping-cart-apps
  labels:
    app.kubernetes.io/name: product-catalog
    app.kubernetes.io/component: seed
    app.kubernetes.io/part-of: shopping-cart
data:
  seed.py: |
    #!/usr/bin/env python3
    """Seed 1,000 products with MinIO image URLs.

    Products are distributed across 4 categories and 20 subcategories
    (50 products each). SKUs are zero-padded and unique. Prices are
    deterministic per subcategory range. Image URLs point to in-cluster
    MinIO via the frontend nginx proxy.
    """
    import os
    import uuid

    import psycopg2

    DB_HOST = os.environ["DB_HOST"]
    DB_PORT = os.environ.get("DB_PORT", "5432")
    DB_NAME = os.environ["DB_NAME"]
    DB_USERNAME = os.environ["DB_USERNAME"]
    DB_PASSWORD = os.environ["DB_PASSWORD"]

    MINIO_BASE = "/minio/product-images"

    SUBCATEGORIES = [
        # (slug, category, label, price_min, price_max, qty_min, qty_max)
        ("laptop",     "Electronics",  "Laptop",           799,  2499, 20,  80),
        ("phone",      "Electronics",  "Smartphone",       399,  1299, 50, 150),
        ("headphones", "Electronics",  "Headphones",        49,   499, 30, 120),
        ("tablet",     "Electronics",  "Tablet",           299,   999, 25,  75),
        ("speaker",    "Electronics",  "Speaker",           29,   399, 40, 100),
        ("keyboard",   "Peripherals",  "Keyboard",          39,   249, 60, 200),
        ("mouse",      "Peripherals",  "Mouse",             19,   129, 80, 250),
        ("webcam",     "Peripherals",  "Webcam",            39,   199, 40, 120),
        ("hub",        "Peripherals",  "USB Hub",           29,   149, 50, 150),
        ("monitor-24", "Monitors",     "24-inch Monitor",  199,   499, 15,  50),
        ("monitor-27", "Monitors",     "27-inch Monitor",  299,   799, 15,  50),
        ("ultrawide",  "Monitors",     "Ultrawide Monitor",399,  1299, 10,  30),
        ("curved",     "Monitors",     "Curved Monitor",   249,   699, 10,  40),
        ("deskpad",    "Accessories",  "Desk Mat",           9,    49,100, 400),
        ("stand",      "Accessories",  "Monitor Stand",     29,   149, 30, 100),
        ("bag",        "Accessories",  "Laptop Bag",        29,   129, 40, 120),
        ("charger",    "Accessories",  "GaN Charger",       19,    89, 60, 200),
        ("cable",      "Accessories",  "USB-C Cable",        5,    29,100, 500),
        ("light",      "Accessories",  "Key Light",         29,   129, 30,  80),
        ("hub-desk",   "Accessories",  "Desktop Hub",       39,   199, 40, 120),
    ]

    BRANDS = [
        "ProTech", "NovaByte", "SwiftEdge", "CorePeak", "ZenBridge",
        "PixelForge", "ArcLight", "PrimeWave", "SteelBase", "ClearVision",
    ]

    ADJECTIVES = [
        "Pro", "Elite", "Ultra", "Max", "Slim",
        "Plus", "Prime", "Edge", "Core", "Lite",
    ]


    def make_product(sub_idx: int, prod_idx: int) -> dict:
        slug, category, label, price_min, price_max, qty_min, qty_max = SUBCATEGORIES[sub_idx]
        n = sub_idx * 50 + prod_idx + 1
        sku = f"{slug.upper().replace('-', '_')}-{n:04d}"
        brand = BRANDS[prod_idx % len(BRANDS)]
        adj = ADJECTIVES[(prod_idx // len(BRANDS)) % len(ADJECTIVES)]
        version = (prod_idx % 5) + 1

        # Deterministic price within range (no random — stable across re-runs)
        price_range = price_max - price_min
        price = round(price_min + (price_range * (prod_idx % 10) / 10), 2)

        qty = qty_min + ((prod_idx * 7) % (qty_max - qty_min))

        return {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, sku)),
            "sku": sku,
            "name": f"{brand} {label} {adj} {version}.0",
            "description": (
                f"{brand} {label} featuring {adj.lower()} performance and modern design. "
                f"Model {version}.0 — ideal for home and office use."
            ),
            "price": price,
            "currency": "USD",
            "quantity": qty,
            "category": category,
            "is_active": True,
            "image_url": f"{MINIO_BASE}/{slug}.jpg",
        }


    def main() -> None:
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
            user=DB_USERNAME, password=DB_PASSWORD,
        )
        cur = conn.cursor()

        inserted = 0
        skipped = 0
        for sub_idx in range(len(SUBCATEGORIES)):
            for prod_idx in range(50):
                p = make_product(sub_idx, prod_idx)
                cur.execute(
                    """
                    INSERT INTO products
                      (id, sku, name, description, price, currency,
                       quantity, category, is_active, image_url,
                       created_at, updated_at)
                    VALUES
                      (%(id)s, %(sku)s, %(name)s, %(description)s,
                       %(price)s, %(currency)s, %(quantity)s, %(category)s,
                       %(is_active)s, %(image_url)s, NOW(), NOW())
                    ON CONFLICT (sku) DO NOTHING
                    """,
                    p,
                )
                if cur.rowcount:
                    inserted += 1
                else:
                    skipped += 1

        conn.commit()
        cur.close()
        conn.close()
        print(f"Seed complete: {inserted} inserted, {skipped} skipped (already existed).")


    if __name__ == "__main__":
        main()
```

### File B: `k8s/base/seed-job.yaml` (replace existing)

Replace the entire file with a Python-based Job that mounts the seed script ConfigMap.
The existing `postgres:15-alpine` approach (psql heredoc) is replaced with `python:3.12-alpine` + psycopg2.

**Old file:** 61 lines, `postgres:15-alpine`, psql heredoc with 8 hardcoded rows.
**New file:**

```yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: product-catalog-seed
  namespace: shopping-cart-apps
  labels:
    app.kubernetes.io/name: product-catalog
    app.kubernetes.io/component: seed
    app.kubernetes.io/part-of: shopping-cart
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 3
  template:
    metadata:
      labels:
        app.kubernetes.io/name: product-catalog
        app.kubernetes.io/component: seed
        app.kubernetes.io/part-of: shopping-cart
    spec:
      restartPolicy: OnFailure
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
      containers:
      - name: seed
        image: python:3.12-alpine
        command:
          - sh
          - -c
          - |
            pip install --quiet psycopg2-binary
            python3 /scripts/seed.py
        envFrom:
        - configMapRef:
            name: product-catalog-config
        - secretRef:
            name: product-catalog-secrets
        volumeMounts:
        - name: scripts
          mountPath: /scripts
        - name: tmp
          mountPath: /tmp
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
      volumes:
      - name: scripts
        configMap:
          name: product-catalog-seed-script
      - name: tmp
        emptyDir: {}
```

### File C: `k8s/base/fts-index-job.yaml` (new)

PostSync Job: creates the GIN index for full-text search. Idempotent (`IF NOT EXISTS`).

```yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: product-catalog-fts-index
  namespace: shopping-cart-apps
  labels:
    app.kubernetes.io/name: product-catalog
    app.kubernetes.io/component: fts-index
    app.kubernetes.io/part-of: shopping-cart
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 3
  template:
    metadata:
      labels:
        app.kubernetes.io/name: product-catalog
        app.kubernetes.io/component: fts-index
        app.kubernetes.io/part-of: shopping-cart
    spec:
      restartPolicy: OnFailure
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
      containers:
      - name: indexer
        image: postgres:15-alpine
        command:
          - sh
          - -c
          - |
            psql "postgresql://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}" <<'SQL'
            CREATE INDEX IF NOT EXISTS products_fts_idx
              ON products
              USING GIN(
                to_tsvector('english',
                  name || ' ' ||
                  COALESCE(description, '') || ' ' ||
                  COALESCE(category, '')
                )
              );
            SQL
        envFrom:
        - configMapRef:
            name: product-catalog-config
        - secretRef:
            name: product-catalog-secrets
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
      volumes:
      - name: tmp
        emptyDir: {}
```

### File D: `k8s/base/kustomization.yaml` (update resources list)

**Old resources:**
```yaml
resources:
- serviceaccount.yaml
- secret.yaml
- deployment.yaml
- service.yaml
- seed-job.yaml
```

**New resources:**
```yaml
resources:
- serviceaccount.yaml
- secret.yaml
- deployment.yaml
- service.yaml
- seed-job-configmap.yaml
- seed-job.yaml
- fts-index-job.yaml
```

### File E: `src/product_catalog/routers/products.py` (update `list_products`)

Add `q: str | None = None` parameter to `list_products` with a PostgreSQL FTS filter.

**Old function signature and query block:**
```python
@router.get("", response_model=PaginatedResponse)
def list_products(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    category: str | None = None,
    active_only: bool = True,
    db: Session = Depends(get_db),
) -> PaginatedResponse:
    """List products with pagination."""
    query = db.query(Product)

    if active_only:
        query = query.filter(Product.is_active.is_(True))

    if category:
        query = query.filter(Product.category == category)
```

**New function signature and query block:**
```python
from sqlalchemy import func

@router.get("", response_model=PaginatedResponse)
def list_products(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    category: str | None = None,
    active_only: bool = True,
    q: str | None = Query(default=None, description="Full-text search across name, description, and category"),
    db: Session = Depends(get_db),
) -> PaginatedResponse:
    """List products with pagination and optional full-text search."""
    query = db.query(Product)

    if active_only:
        query = query.filter(Product.is_active.is_(True))

    if category:
        query = query.filter(Product.category == category)

    if q:
        search_vector = func.to_tsvector(
            "english",
            func.concat_ws(" ", Product.name, Product.description, Product.category),
        )
        query = query.filter(search_vector.op("@@")(func.plainto_tsquery("english", q)))
```

Add `from sqlalchemy import func` to the existing imports at the top of the file.
All other code in the file remains unchanged.

---

## shopping-cart-frontend changes

### File F: `nginx.conf` (add `/minio/` proxy block)

Add a `location ^~ /minio/` block **before** the existing static asset cache regex.
The `^~` modifier prevents the `.jpg` static cache regex from intercepting MinIO image URLs.

**Add this block immediately before the `location ~* \.(js|css|...)` block:**

```nginx
    # Proxy MinIO product images — ^~ prevents static cache regex from matching
    location ^~ /minio/ {
        proxy_pass http://minio.shopping-cart-data.svc.cluster.local:9000/;
        proxy_http_version 1.1;
        proxy_set_header Host minio.shopping-cart-data.svc.cluster.local;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
```

### File G: `src/services/productService.ts` (add `q` param)

Find the `getProducts` function (or equivalent). Add `q?: string` to its params and
include it in the queryParams string sent to `ENDPOINTS.PRODUCTS`.

Read the file first to identify the exact function signature, then add `q` following
the existing pattern for `category` or other optional string params.

---

## Definition of Done

### shopping-cart-product-catalog (branch: `docs/next-improvements`)
- [ ] `k8s/base/seed-job-configmap.yaml` created with the Python seed script above
- [ ] `k8s/base/seed-job.yaml` replaced — now Python-based, mounts ConfigMap
- [ ] `k8s/base/fts-index-job.yaml` created
- [ ] `k8s/base/kustomization.yaml` updated with 3 new entries
- [ ] `src/product_catalog/routers/products.py` — `q` param added, `from sqlalchemy import func` added
- [ ] `kubectl apply --dry-run=client -k k8s/base/` passes
- [ ] Committed with message: `feat: 1000-product seed with MinIO images and full-text search`
- [ ] Pushed to `origin docs/next-improvements`

### shopping-cart-frontend (branch: `docs/next-improvements-2`)
- [ ] `nginx.conf` — `/minio/` proxy block added with `^~` modifier before static cache regex
- [ ] `src/services/productService.ts` — `q` param added
- [ ] Committed with message: `feat: proxy MinIO images and wire full-text search param`
- [ ] Pushed to `origin docs/next-improvements-2`

### Both
- [ ] Tag Copilot on PRs after creation
- [ ] Report commit SHAs for all repos

## What NOT to Do

- Do NOT commit to `main` — use the specified branches
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT use `location /minio/` without `^~` — the static cache regex silently intercepts `.jpg`
- Do NOT use `random` in the seed script — prices and quantities must be deterministic
  (use modulo arithmetic as shown)
- Do NOT add `ON CONFLICT DO UPDATE` — skip conflicts silently with `DO NOTHING`
- Do NOT install psycopg2 (C extension); install `psycopg2-binary` (pre-built wheel, works in alpine)
- Do NOT modify files outside the listed targets
