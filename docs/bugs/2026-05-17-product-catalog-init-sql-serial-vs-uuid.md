# Bug: product-catalog PostgreSQL init SQL creates products table with SERIAL PK — conflicts with SQLAlchemy UUID model

**Branch:** `k3d-manager-v1.4.6`
**Work repo:** `shopping-cart-infra` — branch `fix/product-catalog-uuid-pk`
**File:** `data-layer/postgresql/products/init-db.sql`

---

## Before You Start

```
git pull origin main   # in shopping-cart-infra repo
git checkout -b fix/product-catalog-uuid-pk
```

Read this spec in full before touching any file.

---

## Problem

`shopping-cart-infra/data-layer/postgresql/products/init-db.sql` creates the `products`
table with `id SERIAL PRIMARY KEY` (integer, auto-increment sequence).

The product-catalog FastAPI application uses SQLAlchemy with:
```python
id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
```

When PostgreSQL starts fresh (new cluster), `init-db.sql` runs first and creates the
`products` table with an integer `id`. SQLAlchemy's `Base.metadata.create_all()` on
app startup finds the table already exists (via `CREATE TABLE IF NOT EXISTS`) and
**skips recreation**. The integer `id` column stays, and every API response that tries
to serialize a product fails with:

```
pydantic_core._pydantic_core.ValidationError: 1 validation error for Product
id
  Input should be a valid UUID [type=uuid_type, ...]
```

The index and `INSERT INTO products` lines also fail because they reference column names
that don't exist in the original init SQL (e.g., `currency`, `quantity`, `is_active`).

**Workaround applied (2026-05-17):** The products table was manually dropped and the
app was restarted, allowing SQLAlchemy to recreate it with the correct UUID schema.
This workaround is lost on the next fresh cluster provisioning.

---

## Root Cause

The `init-db.sql` owns the products table DDL but is out of sync with the SQLAlchemy
model. The `CREATE TABLE IF NOT EXISTS` guard prevents SQLAlchemy from correcting
the schema. The init SQL must not compete with the ORM for schema ownership.

---

## Fix

### Change 1 — `shopping-cart-infra/data-layer/postgresql/products/init-db.sql`

Remove the `CREATE TABLE IF NOT EXISTS products` block and its associated indexes
and sample inserts that depend on columns not present in the init schema. Let
SQLAlchemy own the products table schema entirely. Keep the `categories` table
(which the init SQL owns and the app does not create via ORM).

**Exact old block (lines 1–69, from top through the INSERT INTO products block):**

```sql
-- Products Database Schema
-- Shopping Cart Application - Product Catalog Service

-- Create products table
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    category VARCHAR(100),
    inventory_count INTEGER NOT NULL DEFAULT 0 CHECK (inventory_count >= 0),
    image_url VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index on SKU for fast lookups
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);

-- Create index on category for filtering
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);

-- Create index on created_at for sorting
CREATE INDEX IF NOT EXISTS idx_products_created_at ON products(created_at DESC);
```

**Exact new block (replace with):**

```sql
-- Products Database Schema
-- Shopping Cart Application - Product Catalog Service
--
-- NOTE: The products table is managed exclusively by the product-catalog FastAPI
-- application via SQLAlchemy create_all(). Do NOT add a CREATE TABLE for products
-- here — it will conflict with the SQLAlchemy UUID PK schema and break the app.
```

Also remove the `INSERT INTO products` block (lines 52 onward) — those inserts
reference the old SERIAL schema and will fail anyway (wrong columns, wrong id type).
Keep everything from `-- Create categories table` through the end of the file.

**Full replacement file content:**

```sql
-- Products Database Schema
-- Shopping Cart Application - Product Catalog Service
--
-- NOTE: The products table is managed exclusively by the product-catalog FastAPI
-- application via SQLAlchemy create_all(). Do NOT add a CREATE TABLE for products
-- here — it will conflict with the SQLAlchemy UUID PK schema and break the app.

-- Create categories table for better organization
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    parent_id INTEGER REFERENCES categories(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index on category parent_id for hierarchical queries
CREATE INDEX IF NOT EXISTS idx_categories_parent_id ON categories(parent_id);

-- Insert sample categories
INSERT INTO categories (name, description, parent_id) VALUES
    ('Electronics', 'Electronic devices and accessories', NULL),
    ('Computers', 'Desktop and laptop computers', 1),
    ('Smartphones', 'Mobile phones and accessories', 1),
    ('Clothing', 'Apparel and fashion items', NULL),
    ('Men''s Clothing', 'Clothing for men', 4),
    ('Women''s Clothing', 'Clothing for women', 4),
    ('Books', 'Physical and digital books', NULL),
    ('Fiction', 'Fiction books', 7),
    ('Non-Fiction', 'Non-fiction books', 7)
ON CONFLICT (name) DO NOTHING;
```

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| `shopping-cart-infra` | `data-layer/postgresql/products/init-db.sql` | Remove products table DDL + sample inserts; let SQLAlchemy own the schema |

---

## Rules

- No other files modified
- The `categories` table and its inserts must be preserved — the app does not create this table
- Do NOT add a `CREATE TABLE products` back — the SQLAlchemy model must own the schema
- Do NOT modify `shopping-cart-product-catalog` — the app code is correct

---

## Definition of Done

- [ ] `init-db.sql` contains no `CREATE TABLE` for `products` and no `INSERT INTO products`
- [ ] `categories` table DDL and sample inserts are preserved unchanged
- [ ] Committed to branch `fix/product-catalog-uuid-pk` with message:
      `fix(products-db): remove SERIAL products table DDL — let SQLAlchemy own the schema`
- [ ] `git push origin fix/product-catalog-uuid-pk` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `data-layer/postgresql/products/init-db.sql`
- Do NOT commit to `main` — work on `fix/product-catalog-uuid-pk`
- Do NOT add a new `CREATE TABLE products` with UUID type — that is SQLAlchemy's job
- Do NOT modify the `configmap.yaml` that wraps this SQL — the ConfigMap content is
  derived from `init-db.sql` by the kustomize build, not manually maintained

---

## Verification

After the fix is applied and a fresh cluster is provisioned:

```bash
# Check products table uses UUID PK
kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
  psql -U postgres -d products -c "\d products" 2>/dev/null | grep "id"
# Expected: id | uuid | not null |
```
