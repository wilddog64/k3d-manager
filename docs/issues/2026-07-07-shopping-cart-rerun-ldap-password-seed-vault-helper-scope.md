# Issue: second-run LDAP password seeding aborts on leaked Vault helper scope

**Date:** 2026-07-07
**Branch:** `k3d-manager-v1.14.0`
**Fix commit:** `df74e957` (`fix(shopping-cart): resolve rerun vault helper scope for LDAP password seeding`)

## User-reported failure

```text
INFO: [acg-up] data-layer StatefulSets already ready on ubuntu-k3s — writing checkpoint and skipping sync wait
INFO: [acg-up] Step 10c/14 — Deploying identity stack (Keycloak + LDAP) via ArgoCD...
application.argoproj.io/shopping-cart-identity configured
INFO: [acg-up] Waiting for Keycloak deployment to be Available (up to 900s)...
INFO: [acg-up] Step 10d/14 — Importing Keycloak realm shopping-cart...
INFO: [acg-up] Keycloak realm 'shopping-cart' already exists — reconciling client config
INFO: [keycloak] Reconciled client 'argocd' in realm 'shopping-cart'
INFO: [acg-up] Keycloak client 'argocd' reconciled from realm JSON
INFO: [keycloak] Removed client attribute 'pkce.code.challenge.method' from 'argocd' in realm 'shopping-cart' if present
INFO: [acg-up] Keycloak client 'argocd' PKCE attribute removed
WARN: [acg-up] Keycloak frontendUrl update failed — external SSO may not work
INFO: [acg-up] Step 10d.5/14 — Seeding Keycloak LDAP user passwords in LDAP + Vault...
/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/plugins/shopping_cart.sh: line 579: _seed_hdr: unbound variable
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

## Root cause

`shopping_cart_seed_sandbox_vault_kv()` defined `_vault_kv_put`, `_vault_kv_exists`, and
`_vault_kv_get_field` as nested functions that closed over temp header files local to that
function (`_seed_hdr`, `_src_hdr`).

On the first run, those helpers worked during Step 9. On a second run:

1. Step 9 could be skipped or already complete.
2. The leaked helper names were still callable later from `bin/cluster-up` Step `10d.5`.
3. Their closed-over locals no longer existed, so `set -u` aborted on `_seed_hdr`.

Concretely, `bin/cluster-up:958-962` uses `_vault_kv_exists`, `_vault_kv_get_field`, and
`_vault_kv_put` during LDAP user password seeding, outside the original seed function scope.

## Fix

- Moved the target-Vault helpers to top-level functions in `scripts/plugins/shopping_cart.sh`
  so they resolve the seed Vault addr/token and create a temp header file **at call time**.
- Kept source-Vault reads local to `shopping_cart_seed_sandbox_vault_kv()` because only the
  initial seed path needs the canonical-source copy behavior.
- Added a regression test proving `_vault_kv_exists` and `_vault_kv_get_field` work without
  prior seed-local temp state.

## Validation output

```text
$ shellcheck -S warning scripts/plugins/shopping_cart.sh scripts/tests/plugins/shopping_cart_seed_idempotent.bats

$ bash -n scripts/plugins/shopping_cart.sh

$ bats scripts/tests/plugins/shopping_cart_seed_idempotent.bats
1..8
ok 1 reuses existing redis and rabbitmq secrets without PUT for those paths
ok 2 puts redis and rabbitmq secrets when absent
ok 3 seed helpers honor SEED_VAULT_ADDR instead of localhost port
ok 4 copies redis/cart from canonical source Vault when absent in target
ok 5 copies minio/credentials (multi-field) from canonical source Vault when absent in target
ok 6 seed URL carries _vault_local_port set after the plugin was sourced (no empty-port freeze)
ok 7 vault helpers work without prior seed-local temp state
ok 8 put surfaces HTTP status and path on a non-2xx write, then fails

$ ./scripts/k3d-manager _agent_audit
running under bash version 5.3.15(1)-release
```

## Recommended follow-up

Re-run the second-pass `make up` flow that previously failed at Step `10d.5` and confirm the
LDAP password seed completes instead of aborting on `_seed_hdr`.
