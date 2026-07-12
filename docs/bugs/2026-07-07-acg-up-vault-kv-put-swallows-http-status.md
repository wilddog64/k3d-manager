# Bugfix: v1.14.0 — Vault KV seed write swallows HTTP status (undiagnosable seed failures)

**Branch:** `k3d-manager-v1.14.0`
**Files:** `scripts/plugins/shopping_cart.sh`, `scripts/tests/plugins/shopping_cart_seed_idempotent.bats`

---

## Problem

When the "Seeding Vault KV with sandbox static secrets" step fails on a **write**, the
operator gets only a bare exit code and no cause:

```
INFO: [acg-up] Seeding Vault KV with sandbox static secrets...
WARN: [acg-up] failed (exit 22) — cleaning up local processes...
make: *** [up] Error 22
```

There is no indication of **which** KV path failed, **what HTTP status** Vault returned,
or **what Vault said** in the response body. Every seed-write failure — wrong port, sealed
Vault, bad token, policy denial, KV engine not mounted — collapses to the same opaque
`exit 22`, forcing a manual `curl` repro to diagnose (as happened with the empty-port
freeze — see [`2026-07-06-acg-up-seed-vault-empty-port-exit-22.md`](2026-07-06-acg-up-seed-vault-empty-port-exit-22.md)).

**Root cause:** `_vault_kv_put` (in `shopping_cart_seed_sandbox_vault_kv`) uses
`curl -sf … >/dev/null`. `-s` silences curl's own error text, `-f` turns any HTTP ≥ 400
into a bare non-zero exit (22), and `>/dev/null` discards the response body. Because the
helper is unguarded, `set -euo pipefail` aborts the entire cluster bring-up on the first
failed write with none of that context preserved.

**Scope note — only the WRITE path changes.** The read helpers below it
(`_vault_kv_exists`, `_vault_kv_get_field`, `_seed_source_data`) intentionally keep
`-sf`: for those, a `404`/non-2xx is *normal control flow* (the reuse-vs-create and
copy-from-source decisions depend on "key absent" not being an error). Making them noisy
would spam the log on every fresh cluster. A failed **write**, by contrast, is always a
real error worth surfacing.

---

## Reproduction

Point the seed at a reachable Vault that will reject the write (e.g. a sealed Vault, or a
token lacking `secret/data/*` write policy):

```bash
SEED_VAULT_ADDR="http://localhost:18200" SEED_VAULT_TOKEN="bad-token" \
  bash -c 'source scripts/plugins/shopping_cart.sh; shopping_cart_seed_sandbox_vault_kv'
```

**Current:** aborts with `exit 22`, no path / status / body.
**Desired:** `_err` line naming the failed KV path, the HTTP status, and the Vault error body, then a non-zero return.

---

## Fix

### Change 1 — `scripts/plugins/shopping_cart.sh`: surface status + body on write failure

Harden **only** `_vault_kv_put`. Capture the HTTP status via `-w` and the body, keep the
token in the `--config` file (never argv), and on a non-2xx status emit a diagnostic
before returning non-zero. Keep the abort behavior — the goal is a *diagnosable* abort,
not a silent one.

**Exact old block (lines 563–569):**

```bash
  _vault_kv_put() {
    curl -sf -X POST \
      --config "${_seed_hdr}" \
      -H "Content-Type: application/json" \
      -d "{\"data\":$1}" \
      "${_seed_addr}/v1/secret/data/$2" >/dev/null
  }
```

**Exact new block:**

```bash
  _vault_kv_put() {
    local _kv_path="$2" _kv_out _kv_code _kv_body
    _kv_out=$(curl -s -w $'\n%{http_code}' -X POST \
      --config "${_seed_hdr}" \
      -H "Content-Type: application/json" \
      -d "{\"data\":$1}" \
      "${_seed_addr}/v1/secret/data/${_kv_path}") || _kv_out=$'\n000'
    _kv_code="${_kv_out##*$'\n'}"
    _kv_body="${_kv_out%$'\n'*}"
    if [[ "${_kv_code}" != 2* ]]; then
      _err "[acg-up] Vault KV write to ${_kv_path} failed: HTTP ${_kv_code} (addr ${_seed_addr}) — ${_kv_body:-<empty response>}"
      return 1
    fi
  }
```

Notes for the implementer:
- `-f` is dropped so the body survives; the explicit `!= 2*` check replaces it and covers
  every non-2xx (including `000` = curl transport failure, e.g. connection refused).
- `|| _kv_out=$'\n000'` guards the command-substitution failure so `set -e` does not abort
  before the `_err` line runs.
- The token stays in `${_seed_hdr}` (mode-600 `--config` file) — no token on argv. Do NOT
  echo `_seed_hdr` contents. The body may contain a Vault error message but never the token.
- Do NOT touch `_vault_kv_exists`, `_vault_kv_get_field`, or `_seed_source_data` — their
  `-sf` / silent behavior is correct (absence = control flow).

### Change 2 — `scripts/tests/plugins/shopping_cart_seed_idempotent.bats`: mock must emit a status

The `curl` mock currently `return 0` on POST with no stdout. The new writer reads
`$'\n%{http_code}'` from stdout, so the mock must emit a trailing status line for POSTs, and
add a regression test proving a non-2xx write surfaces the path + code and fails.

**Exact old block (lines 18–20):**

```bash
    if [[ "$*" == *"-X POST"* ]]; then
      return 0
    fi
```

**Exact new block:**

```bash
    if [[ "$*" == *"-X POST"* ]]; then
      # Emulate curl -w '\n%{http_code}': body then newline then status.
      # TEST_PUT_HTTP_CODE lets a test force a failure status for one run.
      printf '\n%s' "${TEST_PUT_HTTP_CODE:-200}"
      return 0
    fi
```

**Add regression test at end of file:**

```bash
@test "put surfaces HTTP status and path on a non-2xx write, then fails" {
  export _vault_local_port="8200"
  export _vault_root_token="root-token"
  export TEST_REDIS_CART_EXISTS="0"
  export TEST_PUT_HTTP_CODE="403"

  run shopping_cart_seed_sandbox_vault_kv
  [ "$status" -ne 0 ]
  [[ "$output" == *"Vault KV write to redis/cart failed"* ]]
  [[ "$output" == *"HTTP 403"* ]]
}
```

The existing six tests must still pass unchanged — the mock's default `200` keeps every
successful-write assertion green.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/shopping_cart.sh` | Harden `_vault_kv_put` to report HTTP status + body + path on failure |
| `scripts/tests/plugins/shopping_cart_seed_idempotent.bats` | Mock emits `%{http_code}` for POST; add non-2xx regression test |

---

## Rules

- `shellcheck -S warning scripts/plugins/shopping_cart.sh` — zero new warnings
- Vault token stays in the mode-600 `--config` file — never on argv, never echoed
- Only `_vault_kv_put` changes in the plugin — read helpers untouched
- No other files touched

---

## Definition of Done

- [ ] `_vault_kv_put` emits `_err` with path + HTTP status + body on non-2xx, returns 1
- [ ] `bats scripts/tests/plugins/shopping_cart_seed_idempotent.bats` — all pass (6 existing + 1 new)
- [ ] Regression proof: new test fails on the old `curl -sf … >/dev/null` writer, passes on the fix
- [ ] `shellcheck -S warning scripts/plugins/shopping_cart.sh` clean
- [ ] `bash -n scripts/plugins/shopping_cart.sh` OK
- [ ] `./scripts/k3d-manager _agent_audit` clean
- [ ] Committed and pushed to `k3d-manager-v1.14.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(shopping-cart): surface Vault KV write HTTP status on seed failure
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT change `_vault_kv_exists`, `_vault_kv_get_field`, or `_seed_source_data`
- Do NOT commit to `main` — work on `k3d-manager-v1.14.0`
