# Bug: keycloak-reconcile-hook-job partialImport not idempotent — LDAP setup never runs on re-runs

**Date:** 2026-05-25
**File:** `shopping-cart-infra/identity/keycloak/keycloak-reconcile-hook-job.yaml`
**Branch (work):** `fix/keycloak-reconcile-idempotency` (same branch as realm-json redirect URI fix)

---

## Problem

The `keycloak-realm-reconcile` ArgoCD PostSync hook job runs `kcadm.sh create partialImport`
with `ifResourceExists=OVERWRITE`. On a fresh Keycloak install this succeeds. On any subsequent
ArgoCD sync (when realm, clients, roles, and the LDAP component already exist), `partialImport`
exits non-zero (HTTP 500 — PostgreSQL constraint `uk_orvsdmla56612eaefiq6wl5oi` duplicate key).

Because the job uses `set -euo pipefail`, the non-zero exit aborts the script at line 91.
The LDAP mapper setup and full sync (`triggerFullSync`) on lines 96–153 never run.
Result: LDAP users are not synced into Keycloak on re-deploys, and login fails with `user_not_found`.

**Root cause:** `kcadm.sh create partialImport` is not idempotent when the Keycloak PostgreSQL
store already contains entities with the same primary keys; `ifResourceExists=OVERWRITE` does not
cover all Keycloak entity types and the DB constraint fires before the in-process overwrite.

---

## Reproduction

1. Run `make up` once (Keycloak realm, clients, and LDAP provider are created by partialImport)
2. Force an ArgoCD sync of `shopping-cart-identity`: `argocd app sync shopping-cart-identity --force`
3. Observe `keycloak-realm-reconcile` job in `Error` state after ~10 seconds
4. Check logs: `kubectl logs -n identity <reconcile-pod>` — shows only "Realm shopping-cart exists; applying partial import"
5. No `user_not_found`-style login success; LDAP sync never runs

---

## Fix

### Change 1 — `identity/keycloak/keycloak-reconcile-hook-job.yaml`: wrap partialImport to tolerate failure

**Exact old block (lines 91–95):**

```bash
          /opt/keycloak/bin/kcadm.sh create partialImport \
            -r "${KC_REALM}" \
            -s ifResourceExists=OVERWRITE \
            -f /tmp/realm-shopping-cart.rendered.json
```

**Exact new block:**

```bash
          if ! /opt/keycloak/bin/kcadm.sh create partialImport \
            -r "${KC_REALM}" \
            -s ifResourceExists=OVERWRITE \
            -f /tmp/realm-shopping-cart.rendered.json; then
            echo "Warning: partialImport returned non-zero (duplicate key on re-run); continuing with LDAP setup"
          fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `identity/keycloak/keycloak-reconcile-hook-job.yaml` | Wrap partialImport in `if !` block so LDAP setup continues on failure |

---

## Before You Start

1. `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra fetch origin`
2. Checkout the branch created for the realm-json fix:
   `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra checkout fix/keycloak-reconcile-idempotency`
3. If the branch does not exist yet, create it from main:
   `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra checkout -b fix/keycloak-reconcile-idempotency origin/main`
4. Read `identity/keycloak/keycloak-reconcile-hook-job.yaml` lines 88–98 to locate the block
5. Confirm you are on branch `fix/keycloak-reconcile-idempotency` — never commit to `main`

**Branch (work repo):** `fix/keycloak-reconcile-idempotency` in `shopping-cart-infra`

---

## Rules

- `kubectl apply --dry-run=client -f identity/keycloak/keycloak-reconcile-hook-job.yaml` — must pass
- No other files touched

---

## Definition of Done

- [ ] Lines 91–95 replaced: `partialImport` now wrapped in `if ! ...; then echo warning; fi`
- [ ] `kubectl apply --dry-run=client -f identity/keycloak/keycloak-reconcile-hook-job.yaml` passes
- [ ] No other files modified (only `identity/keycloak/keycloak-reconcile-hook-job.yaml`)
- [ ] Committed on branch `fix/keycloak-reconcile-idempotency`
- [ ] Pushed to `origin/fix/keycloak-reconcile-idempotency`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(keycloak): make reconcile job idempotent — wrap partialImport to continue LDAP setup on duplicate key
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `identity/keycloak/keycloak-reconcile-hook-job.yaml`
- Do NOT commit to `main`
- Do NOT change the LDAP setup logic below the partialImport call
