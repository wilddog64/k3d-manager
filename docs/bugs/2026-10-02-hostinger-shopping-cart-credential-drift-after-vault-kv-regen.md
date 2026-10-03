# Bug: hostinger shopping-cart data stores keep their old passwords after the Vault KV was regenerated

**Filed:** 2026-10-02
**Status:** OPEN — spec ready, dispatched to Codex
**Branch:** `k3d-manager-v1.41.0`
**Found by:** Claude, 2026-10-02. A payment pod restart (image re-pin) went into CrashLoopBackOff with
`FATAL: password authentication failed for user "postgres"`.
**Related (same class, ACG only):** `docs/issues/2026-05-26-order-service-postgresql-password-reconcile-missing.md`,
`docs/bugs/archive/2026-08-20-pre-v1.26/2026-05-24-acg-up-postgres-password-regenerated-every-run.md`,
`docs/bugs/archive/2026-08-20-pre-v1.26/2026-05-24-acg-up-step-11b-stale-eso-password.md`,
`docs/plans/archive/2026-08-20-pre-v1.26/v1.4.10-resilient-db-password-reconciliation.md`

## Symptom

- 2026-10-02: `payment-service` on `ubuntu-hostinger` crash-looped after its pod was replaced. The image was fine.
- The operator ran `ALTER USER postgres PASSWORD` from the current `payment-db-credentials` value. Payment came up 1/1 Ready on
  `sha256:b722319e…`.

## Root cause

On 2026-09-29 at 22:37–22:45, ESO rewrote every hostinger shopping-cart Secret with new values from the hub Vault. The likely cause
is that the KV was regenerated, since `shopping_cart_seed_sandbox_vault_kv` generates passwords with `openssl rand` when a key is
missing. The stores read their password env only when they first initialize or start:

| Store | Pod (started) | Reads the password |
|---|---|---|
| `postgresql-orders/products/payment` | 2026-08-06 | `POSTGRES_PASSWORD` on first initdb only |
| `rabbitmq` | 2026-08-24 | `RABBITMQ_DEFAULT_PASS` on first boot only |
| `redis-cart`, `redis-orders-cache` | 2026-08-06 | `--requirepass $(REDIS_PASSWORD)` on every start |

The consumers read Secrets only at pod start:

| Consumer | Started |
|---|---|
| `basket-service` | 09-01 |
| `order-service` | 09-24 |
| `product-catalog` | 09-24 |
| `payment-service` | 10-02, now new values |

- **Today, order-service and product-catalog work** only because their env predates the change, so it still matches the
  stores. They crash on their next restart, for Postgres and possibly RabbitMQ.
- **The Redis hazard runs the other way.** A Redis restart loads the new password and breaks `basket-service`, which still
  holds the old one.

The only reconcile code, `shopping_cart_reconcile_order_service` / `_product_catalog`:
- is ACG-only (`--context ubuntu-k3s`);
- skips payment, RabbitMQ and Redis;
- puts the password in the `kubectl exec` arguments.

Hostinger has no way to detect or fix drift.

Open question, out of scope: `payment-encryption-secret` (`secret/data/payment/encryption:key`) was also rewritten on 09-29. If it
changed, data encrypted with the old key is unreadable.

## Fix

A check/apply tool for any context. It compares each store against the Secret its consumers read; only `--apply` fixes the
store and restarts the consumers of drifted stores. Secret values move only through pipes into `kubectl exec -i`. They never
appear in a `kubectl` argument, a log line or a shell variable on the host.

Verified live 2026-10-02 with a wrong password:
- Postgres scram via TCP to the pod IP rejects it (rc 2); loopback and socket are `trust`.
- `redis-cli` with `REDISCLI_AUTH` returns no `PONG` (rc 1).
- `rabbitmqctl authenticate_user` rejects it (rc 65).
- The ALTER USER form below printed `ALTER ROLE` on `postgresql-payment-0`.

### S1: `scripts/plugins/shopping_cart.sh`, append at the end of the file

```bash

_SHOPPING_CART_CRED_STORES=(
  "postgres-orders|postgres|shopping-cart-data/postgres-orders-admin|postgresql-orders-0|shopping-cart-apps/order-service"
  "postgres-products|postgres|shopping-cart-data/postgres-products-admin|postgresql-products-0|shopping-cart-apps/product-catalog"
  "postgres-payment|postgres|shopping-cart-data/postgres-payment-admin|postgresql-payment-0|shopping-cart-payment/payment-service"
  "rabbitmq|rabbitmq|shopping-cart-data/rabbitmq-credentials|rabbitmq-0|shopping-cart-apps/order-service shopping-cart-apps/product-catalog shopping-cart-payment/payment-service"
  "redis-cart|redis|shopping-cart-data/redis-cart-secret|redis-cart-0|shopping-cart-apps/basket-service"
  "redis-orders-cache|redis|shopping-cart-data/redis-orders-cache-secret|redis-orders-cache-0|"
)

function _shopping_cart_cred_secret_b64() {
  local ctx="$1" sref="$2" key="$3"
  kubectl --context "$ctx" -n "${sref%%/*}" get secret "${sref#*/}" -o "jsonpath={.data.${key}}"
}

function _shopping_cart_cred_check() {
  local ctx="$1" kind="$2" sref="$3" pod="$4" user
  case "$kind" in
    postgres)
      _shopping_cart_cred_secret_b64 "$ctx" "$sref" password \
        | kubectl --context "$ctx" -n shopping-cart-data exec -i "$pod" -- \
            sh -c 'p=$(base64 -d); PGPASSWORD="$p" psql -h "$(hostname -i)" -U postgres -tAc "select 1" >/dev/null 2>&1'
      ;;
    rabbitmq)
      user=$(_shopping_cart_cred_secret_b64 "$ctx" "$sref" username | base64 -d)
      _shopping_cart_cred_secret_b64 "$ctx" "$sref" password \
        | kubectl --context "$ctx" -n shopping-cart-data exec -i "$pod" -c rabbitmq -- \
            sh -c 'p=$(base64 -d); rabbitmqctl -q authenticate_user "$1" "$p" >/dev/null 2>&1' sh "$user"
      ;;
    redis)
      _shopping_cart_cred_secret_b64 "$ctx" "$sref" password \
        | kubectl --context "$ctx" -n shopping-cart-data exec -i "$pod" -- \
            sh -c 'REDISCLI_AUTH="$(base64 -d)" redis-cli --no-auth-warning ping 2>/dev/null | grep -qx PONG'
      ;;
  esac
}

function _shopping_cart_cred_apply() {
  local ctx="$1" kind="$2" sref="$3" pod="$4" user
  case "$kind" in
    postgres)
      _shopping_cart_cred_secret_b64 "$ctx" "$sref" password \
        | kubectl --context "$ctx" -n shopping-cart-data exec -i "$pod" -- \
            sh -c 'p=$(base64 -d); printf "%s\n" "ALTER USER postgres PASSWORD :'\''pw'\'';" | psql -U postgres -q -v ON_ERROR_STOP=1 -v pw="$p" >/dev/null'
      ;;
    rabbitmq)
      user=$(_shopping_cart_cred_secret_b64 "$ctx" "$sref" username | base64 -d)
      _shopping_cart_cred_secret_b64 "$ctx" "$sref" password \
        | kubectl --context "$ctx" -n shopping-cart-data exec -i "$pod" -c rabbitmq -- \
            sh -c 'p=$(base64 -d); rabbitmqctl -q change_password "$1" "$p" >/dev/null' sh "$user"
      ;;
    redis)
      kubectl --context "$ctx" -n shopping-cart-data rollout restart "statefulset/${pod%-0}" >/dev/null \
        && kubectl --context "$ctx" -n shopping-cart-data rollout status "statefulset/${pod%-0}" --timeout=180s >/dev/null
      ;;
  esac
}

function shopping_cart_credential_drift() {
  local ctx="" apply=0 entry name kind sref pod consumers c drift=0 failed=0
  local -a restart=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --context) ctx="${2:-}"; shift 2 ;;
      --apply) apply=1; shift ;;
      -h|--help)
        echo "Usage: shopping_cart_credential_drift --context <kube-context> [--apply]"
        echo "Checks each shopping-cart DB/broker/cache password against the Secret its apps read."
        echo "--apply resets drifted stores to the Secret value and restarts their consumers."
        return 0 ;;
      *) _err "[cred-drift] unknown argument: $1"; return 2 ;;
    esac
  done
  [[ -n "$ctx" ]] || { _err "[cred-drift] --context is required"; return 2; }

  for entry in "${_SHOPPING_CART_CRED_STORES[@]}"; do
    IFS='|' read -r name kind sref pod consumers <<<"$entry"
    if ! kubectl --context "$ctx" -n shopping-cart-data get pod "$pod" >/dev/null 2>&1; then
      _info "[cred-drift] ${name}: SKIP (pod ${pod} not found)"
      continue
    fi
    if _shopping_cart_cred_check "$ctx" "$kind" "$sref" "$pod"; then
      _info "[cred-drift] ${name}: MATCH"
      continue
    fi
    drift=1
    if [[ "$apply" -eq 0 ]]; then
      _info "[cred-drift] ${name}: DRIFT (consumers to restart on --apply: ${consumers:-none})"
      continue
    fi
    if _shopping_cart_cred_apply "$ctx" "$kind" "$sref" "$pod" \
        && _shopping_cart_cred_check "$ctx" "$kind" "$sref" "$pod"; then
      _info "[cred-drift] ${name}: FIXED"
      for c in $consumers; do
        [[ " ${restart[*]} " == *" ${c} "* ]] || restart+=("$c")
      done
    else
      _err "[cred-drift] ${name}: FAILED to reconcile"
      failed=1
    fi
  done

  for c in "${restart[@]}"; do
    _info "[cred-drift] restarting ${c}"
    kubectl --context "$ctx" -n "${c%%/*}" rollout restart "deployment/${c#*/}" >/dev/null \
      && kubectl --context "$ctx" -n "${c%%/*}" rollout status "deployment/${c#*/}" --timeout=300s >/dev/null \
      || { _err "[cred-drift] ${c} did not become ready"; failed=1; }
  done

  [[ "$failed" -eq 0 ]] || return 1
  if [[ "$apply" -eq 0 && "$drift" -eq 1 ]]; then
    return 1
  fi
  return 0
}
```

`_info` and `_err` already exist in the sourced libs, so use them as they are. If shellcheck flags SC2016 on the
single-quoted `sh -c` scripts, add `# shellcheck disable=SC2016` directly above each flagged line. Do not change the scripts.

### S2: `Makefile`

Add `shopping-cart-credential-drift` to the `.PHONY` line, after `show-service-passwords`. Add this target directly after the
`show-service-passwords` recipe (before the next `##` comment):

```make
## Check shopping-cart DB/broker/cache passwords against their Secrets (APPLY=1 fixes + restarts consumers)
shopping-cart-credential-drift:
	@./scripts/k3d-manager shopping_cart_credential_drift --context "$(or $(CONTEXT),ubuntu-hostinger)" $(if $(filter 1,$(APPLY)),--apply,)
```

### S3: `scripts/tests/plugins/shopping_cart_credential_drift.bats` (new)

Source the libs the way `scripts/tests/plugins/shopping_cart.bats` does, then stub `kubectl` as a bash function. Every call
appends `$*` to `${BATS_TEST_TMPDIR}/calls`. The stub behaves as follows:
- `get pod`: rc 0.
- `get secret`: prints `c2VjcmV0LXZhbHVl` for the `password` key (base64 of `secret-value`) and `cm1x` for the `username`
  key. Read the key from the `jsonpath={.data.<key>}` argument.
- `exec -i <pod> ...`: drains stdin. If the arguments contain `ALTER USER` or `change_password`, it touches
  `${BATS_TEST_TMPDIR}/fixed-<pod>` and returns 0. Otherwise it returns 1 when `<pod>` is listed in `TEST_DRIFT_PODS` and
  `fixed-<pod>` does not exist, and 0 in every other case.
- `rollout restart statefulset/<sts>`: touches `fixed-<sts>-0` and returns 0.
- Every other `rollout` call returns 0.

Required tests, at least these 7:
1. No drift, check mode: rc 0, 6 `: MATCH` lines, and no `rollout` in calls.
2. `TEST_DRIFT_PODS=postgresql-orders-0`, check mode:
   - rc 1, and `postgres-orders: DRIFT` is in the output;
   - calls contain no `ALTER USER` and no `rollout`.
3. Same drift with `--apply`:
   - rc 0, and `postgres-orders: FIXED` is in the output;
   - calls contain `exec -i postgresql-orders-0` with `ALTER USER`, and `rollout restart deployment/order-service`;
   - calls do NOT contain `deployment/basket-service` or `deployment/payment-service`.
4. `TEST_DRIFT_PODS="rabbitmq-0"` with `--apply`:
   - `change_password` appears with the `rmq` username argument;
   - each of order-service, product-catalog and payment-service is restarted exactly once (`grep -c` = 1 each).
5. `TEST_DRIFT_PODS="redis-cart-0"` with `--apply`: `rollout restart statefulset/redis-cart` and
   `rollout restart deployment/basket-service`.
6. Secret hygiene, for the `--apply` run with all six pods drifted: calls contain neither `c2VjcmV0LXZhbHVl` nor
   `secret-value` (`run grep -c` prints `0`).
7. Missing `--context`: rc 2.

Use `run`/`[ ]` assertions only. No bare `!` negations (lint `bats_negation_lint` rejects them).

## Gate (paste output)

1. `bats scripts/tests/plugins/shopping_cart_credential_drift.bats scripts/tests/plugins/shopping_cart.bats` reports 0 failures.
2. Mutation A: in `shopping_cart_credential_drift`, delete the line `restart+=("$c")` (keep the `[[ … ]] ||` guard by replacing it
   with `:`). Tests 3–5 must FAIL. Restore it.
3. Mutation B: in the `postgres)` branch of `_shopping_cart_cred_check`, replace the whole `sh -c '…'` script with
   `sh -c 'cat >/dev/null; exit 0'`. Test 2 must FAIL. Restore it.
4. `shellcheck -x scripts/plugins/shopping_cart.sh`: the new-warning count is 0. Compare
   `git show HEAD:scripts/plugins/shopping_cart.sh | shellcheck -f gcc - | wc -l` (before) against the same command on the
   file (after).
5. `./scripts/k3d-manager shopping_cart_credential_drift --help` prints the usage line. `make -n shopping-cart-credential-drift APPLY=1`
   shows `--context "ubuntu-hostinger" --apply`.
6. `grep -rnE '^[[:space:]]*! ' scripts/tests --include='*.bats'` prints nothing.
7. `git diff --stat` shows only `scripts/plugins/shopping_cart.sh`, `Makefile` and the new bats file.

## Definition of Done

- [ ] S1–S3 applied; only these 3 files changed
- [ ] Gates 1–7 output pasted
- [ ] Commit message: `feat(shopping-cart): detect and reconcile data-store credential drift against ESO Secrets`
- [ ] Pushed to `origin/k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than the 3 listed (do not touch the existing ACG `shopping_cart_reconcile_*` functions)
- Do NOT commit to `main`
- Do NOT edit memory-bank
- Do NOT touch any live cluster or run the new target without a stubbed `kubectl`
- Do NOT read, print or assign a Secret value to a host-side variable (the username is the only exception)

## Rollout (operator, then Claude)

1. `make shopping-cart-credential-drift`: check only. Paste the MATCH/DRIFT lines; they contain no values.
2. If anything shows DRIFT: `make shopping-cart-credential-drift APPLY=1`. Expect a brief restart of the listed consumers.
3. Claude verifies:
   - a rerun of step 1 is all MATCH;
   - every shopping-cart pod is Ready;
   - frontend and checkout still respond.

## Follow-ups (not in this spec)

- Port the ACG `shopping_cart_reconcile_*` functions onto this tool. They still pass the password in the `exec` arguments.
- Find out why the hub Vault KV was regenerated on 2026-09-29. Answer the `payment-encryption-secret` question.
