# Bug: Product Catalog Seed Job Race Condition

**Date:** 2026-05-27
**Severity:** Medium — prevents initial product catalog seeding on fresh clusters
**Status:** Investigated / Fix Proposed
**Assignee:** Gemini CLI

## Symptom
The `product-catalog-seed` job fails during initial bootstrap with:
`Job has reached the specified backoff limit`

The underlying error in PostgreSQL logs is:
`ERROR: relation "products" does not exist at character 30`
`STATEMENT: INSERT INTO products ...`

## Root Cause Analysis
There is a race condition between the `product-catalog` service and the `product-catalog-seed` job:

1.  **Table Management:** The `products` table is managed by the `product-catalog` FastAPI application using SQLAlchemy `create_all()` during its startup lifespan handler.
2.  **Trigger Logic:** The `scripts/plugins/shopping_cart.sh` script checks for an empty database and triggers the seed job as soon as the `product-catalog` **Deployment** exists.
3.  **Race Condition:** The Deployment object existence does not guarantee that the pod has started or finished its table creation logic.
4.  **Failure:** The seed job starts, connects to the database, and attempts to insert data before the table exists. Each retry fails instantly, quickly reaching the `backoffLimit` of 3.

## Resolution
Modify `scripts/plugins/shopping_cart.sh` to explicitly wait for the `product-catalog` deployment to be ready (via `kubectl rollout status`) before checking the product count or triggering the seed job.

## Manual Workaround
If the cluster is already up, the tables should now exist. Re-run the seed job:
```bash
_pc_kustomize_dir="/Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog"
kubectl delete job product-catalog-seed -n shopping-cart-apps --context ubuntu-k3s --ignore-not-found --wait=true
kubectl kustomize "${_pc_kustomize_dir}/k8s/base" | kubectl apply --context ubuntu-k3s --selector app.kubernetes.io/component=seed -f -
```
