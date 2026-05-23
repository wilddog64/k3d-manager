# Plan: Add Product Seed Job to shopping-cart-product-catalog

**Date:** 2026-05-23
**Repo:** `shopping-cart-product-catalog`
**Branch:** `docs/next-improvements`
**Target files:**
- `k8s/base/seed-job.yaml` (new)
- `k8s/base/kustomization.yaml` (add resource entry)

## Problem

The products PostgreSQL database is empty after every fresh cluster deploy. ArgoCD syncs
the Deployment and Service but no seed data exists. The frontend shows "No products found."

## Before You Start

1. `git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog pull origin docs/next-improvements`
2. Read `k8s/base/kustomization.yaml`, `k8s/base/secret.yaml`, `k8s/base/configmap.env`
3. Confirm the `products` table schema matches: id (UUID), sku (VARCHAR 50 unique), name
   (VARCHAR 200), description (TEXT nullable), price (NUMERIC 10,2), currency (VARCHAR 3
   default 'USD'), quantity (NUMERIC 10,0 default 0), category (VARCHAR 100 nullable),
   is_active (BOOLEAN default true), image_url (VARCHAR 500 nullable), created_at
   (TIMESTAMP), updated_at (TIMESTAMP)

## Task

Add a Kubernetes Job that seeds 8 sample products into the products PostgreSQL database.
The Job must be idempotent — re-running it must not fail or duplicate records.

### File 1: `k8s/base/seed-job.yaml` (new file)

Write this file exactly as shown:

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
        image: postgres:15-alpine
        command:
        - sh
        - -c
        - |
          psql "postgresql://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}" <<'SQL'
          INSERT INTO products (id, sku, name, description, price, currency, quantity, category, is_active, image_url, created_at, updated_at)
          VALUES
            (gen_random_uuid(), 'LAPTOP-001', 'ProBook 15 Laptop', 'High-performance 15-inch laptop with 16GB RAM and 512GB SSD', 1299.99, 'USD', 50, 'Electronics', true, NULL, NOW(), NOW()),
            (gen_random_uuid(), 'PHONE-001', 'SmartPhone X12', 'Latest flagship smartphone with 6.7-inch AMOLED display', 899.99, 'USD', 100, 'Electronics', true, NULL, NOW(), NOW()),
            (gen_random_uuid(), 'HEADPHONES-001', 'ANC Pro Headphones', 'Wireless noise-cancelling headphones with 30-hour battery', 349.99, 'USD', 75, 'Electronics', true, NULL, NOW(), NOW()),
            (gen_random_uuid(), 'KEYBOARD-001', 'Mechanical Keyboard TKL', 'Tenkeyless mechanical keyboard with Cherry MX switches', 129.99, 'USD', 200, 'Peripherals', true, NULL, NOW(), NOW()),
            (gen_random_uuid(), 'MOUSE-001', 'Ergonomic Wireless Mouse', 'Ergonomic wireless mouse with 6-month battery life', 59.99, 'USD', 150, 'Peripherals', true, NULL, NOW(), NOW()),
            (gen_random_uuid(), 'MONITOR-001', '27-inch 4K Monitor', 'IPS 4K monitor with 144Hz refresh rate and USB-C', 599.99, 'USD', 30, 'Monitors', true, NULL, NOW(), NOW()),
            (gen_random_uuid(), 'WEBCAM-001', 'HD Webcam 1080p', '1080p webcam with built-in noise-cancelling microphone', 89.99, 'USD', 120, 'Peripherals', true, NULL, NOW(), NOW()),
            (gen_random_uuid(), 'DESKPAD-001', 'XL Desk Mat', 'Extra-large 90x40cm desk mat with non-slip base', 29.99, 'USD', 300, 'Accessories', true, NULL, NOW(), NOW())
          ON CONFLICT (sku) DO NOTHING;
          SQL
        envFrom:
        - configMapRef:
            name: product-catalog-config
        - secretRef:
            name: product-catalog-secrets
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
```

### File 2: `k8s/base/kustomization.yaml` (add one line)

Add `- seed-job.yaml` to the `resources:` list.

**Old:**
```yaml
resources:
- serviceaccount.yaml
- secret.yaml
- deployment.yaml
- service.yaml
```

**New:**
```yaml
resources:
- serviceaccount.yaml
- secret.yaml
- deployment.yaml
- service.yaml
- seed-job.yaml
```

## Definition of Done

- [ ] `k8s/base/seed-job.yaml` exists with the exact content above
- [ ] `k8s/base/kustomization.yaml` has `- seed-job.yaml` in the `resources:` list
- [ ] `kubectl apply --dry-run=client -k k8s/base/` passes with no errors (run from repo root)
- [ ] Committed on branch `docs/next-improvements` with message:
  `feat(k8s): add product-catalog seed job with 8 sample products`
- [ ] Pushed to `origin docs/next-improvements` before reporting done
- [ ] Tag Copilot for review: `gh api repos/wilddog64/shopping-cart-product-catalog/pulls/<n>/requested_reviewers -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'`

## What NOT to Do

- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `k8s/base/seed-job.yaml` and `k8s/base/kustomization.yaml`
- Do NOT change seed product data from what is specified above
- Do NOT add imagePullSecrets to the Job — the ghcr-pull-secret patch in k3d-manager's kustomization handles Deployments only; the postgres image is public
