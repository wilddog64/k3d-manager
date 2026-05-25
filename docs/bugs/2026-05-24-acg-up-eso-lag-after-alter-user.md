# Bug: acg-up rollout restart fires before ESO re-syncs — new pod gets stale DB_PASSWORD

**Date:** 2026-05-24
**File:** `bin/acg-up`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

Step 11b reconciles the postgres products password by running `ALTER USER postgres PASSWORD`
and then checking for a DB_PASSWORD mismatch on the running pod. If a mismatch is found it
triggers `kubectl rollout restart deployment/product-catalog`.

The rollout restart fires immediately — before ESO has re-synced `product-catalog-secrets`
from Vault. The new pod starts, mounts the **stale** k8s secret, connects with the old
password, and crashes:

```
FATAL: password authentication failed for user "postgres"
```

The pod self-heals once ESO's next sync cycle fires (up to 24h, but typically within
1–2 minutes on cluster startup due to initial sync), but this causes unnecessary restarts
on every `make up` run where postgres credentials changed.

---

## Root Cause

There is no ESO force-sync between the `ALTER USER` call (line 1419) and the
`kubectl rollout restart` call (line 1430). ESO has `refreshInterval: 24h` and does not
re-pull from Vault until forced or until the interval elapses.

---

## Fix

### Change 1 — `bin/acg-up`: add ESO force-sync after ALTER USER, before rollout restart

**Exact old block (lines 1418–1422):**

```bash
kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
  psql -U postgres -c "ALTER USER postgres PASSWORD '${_pg_pass_products}';" >/dev/null 2>&1 \
  && _info "[acg-up] PostgreSQL products password reconciled with Vault" \
  || _info "[acg-up] WARN: could not reconcile PostgreSQL products password"

if kubectl get deployment product-catalog \
```

**Exact new block:**

```bash
kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
  psql -U postgres -c "ALTER USER postgres PASSWORD '${_pg_pass_products}';" >/dev/null 2>&1 \
  && _info "[acg-up] PostgreSQL products password reconciled with Vault" \
  || _info "[acg-up] WARN: could not reconcile PostgreSQL products password"

kubectl annotate externalsecret product-catalog-secrets \
  -n shopping-cart-apps --context ubuntu-k3s \
  force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 \
  && _info "[acg-up] ESO force-sync triggered for product-catalog-secrets" \
  || _info "[acg-up] WARN: could not trigger ESO force-sync for product-catalog-secrets"

if kubectl get deployment product-catalog \
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add `kubectl annotate externalsecret` force-sync after ALTER USER and before rollout restart check |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `bin/acg-up` updated — force-sync annotation inserted between ALTER USER block and the `if kubectl get deployment product-catalog` mismatch check
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-up): force ESO re-sync after ALTER USER — prevent stale DB_PASSWORD on rollout restart
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
- Do NOT remove or move the existing mismatch check block (lines 1423–1438) — only insert between ALTER USER and that block
- Do NOT add force-sync for orders or payment ExternalSecrets in this fix — scope is products only
