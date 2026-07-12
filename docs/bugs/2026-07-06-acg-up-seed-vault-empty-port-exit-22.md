# Bugfix: v1.14.0 — acg-up Vault KV seed fails with exit 22 (empty-port freeze)

**Branch:** `k3d-manager-v1.14.0`
**Files:** `scripts/plugins/shopping_cart.sh`, `scripts/tests/plugins/shopping_cart_seed_idempotent.bats`

---

## Problem

`make up` (acg-up) aborts at the "Seeding Vault KV with sandbox static secrets" step:

```
INFO: [acg-up] Seeding Vault KV with sandbox static secrets...
WARN: [acg-up] failed (exit 22) — cleaning up local processes...
make: *** [up] Error 22
```

Exit 22 is `curl --fail` reporting an HTTP response ≥ 400.

**Root cause:** a load-order / `:=` freeze bug. `scripts/plugins/shopping_cart.sh`
defaulted the seed endpoint at *plugin-source time*:

```bash
: "${SEED_VAULT_ADDR:=http://localhost:${_vault_local_port}}"
```

But `bin/cluster-up` **sources the plugin at line 52**, while it does not assign
`_vault_local_port` until **line 325** (`_vault_local_port="${TUNNEL_VAULT_LOCAL_PORT:-18200}"`).
So at source time `_vault_local_port` is empty and `:=` freezes
`SEED_VAULT_ADDR="http://localhost:"` (no port). The in-function fallback
`${SEED_VAULT_ADDR:-…}` cannot correct it because the frozen value is set-and-non-empty.

At seed time the writer curls `http://localhost:/v1/secret/data/redis/cart`. curl treats
the empty port as **:80**, hits whatever is listening there, gets **HTTP 404**, and
`curl -sf` returns **exit 22**. The write helper `_vault_kv_put` is unguarded (no `if` /
no `|| true`), so under `set -euo pipefail` the whole run aborts.

Reproduced exactly:
```
FROZEN SEED_VAULT_ADDR=[http://localhost:]
curl "http://localhost:/v1/x"  →  http=404  curl_exit=22
```

The Vault token is **not** the problem — `SEED_VAULT_TOKEN` also freezes empty at
source time, but line 551's `${SEED_VAULT_TOKEN:-${_vault_root_token}}` correctly falls
back to the resolved root token. Only the ADDR freeze is fatal (non-empty frozen value).

Why it wasn't caught: `shopping_cart_seed_idempotent.bats` mocks `curl` and asserted only
the URL *suffix* (`.../redis/cart$`), never the host:port — so the broken endpoint passed.

---

## Reproduction

`CLUSTER_PROVIDER=k3s-aws make up` on a host with any listener on `localhost:80`
(k3d/Traefik serverlb, OrbStack, etc.) → seed step exits 22.

---

## Fix

### Change 1 — `scripts/plugins/shopping_cart.sh`: drop the source-time `:=` defaults

The in-function resolution (lines 550–553) already applies env overrides and the
port-forward default at *call time* with `:-` fallbacks. The top-level `:=` block was
redundant and the sole cause of the freeze.

**Old (lines 6–11):**
```bash
# --- Tier 3 P3: seed target / canonical source / backup targets ----------------------
# Defaults preserve pre-P3 behavior: target == source == laptop Vault via local port-forward.
: "${SEED_VAULT_ADDR:=http://localhost:${_vault_local_port}}"
: "${SEED_VAULT_TOKEN:=${_vault_root_token:-}}"
: "${SEED_VAULT_SOURCE_ADDR:=${SEED_VAULT_ADDR}}"
: "${SEED_VAULT_SOURCE_TOKEN:=${SEED_VAULT_TOKEN}}"
```

**New:**
```bash
# --- Tier 3 P3: seed target / canonical source / backup targets ----------------------
# SEED_VAULT_ADDR/TOKEN and SEED_VAULT_SOURCE_ADDR/TOKEN are resolved at call time inside
# shopping_cart_seed_sandbox_vault_kv, defaulting to the laptop Vault port-forward on
# ${_vault_local_port}. They are intentionally NOT given ':=' defaults here: this plugin is
# sourced before bin/cluster-up assigns _vault_local_port, so a source-time default would
# freeze an empty port into the URL (curl → :80 → HTTP 404 → exit 22). Any exported override
# is still honored by the ':-' fallbacks at the call site.
```

### Change 2 — `scripts/tests/plugins/shopping_cart_seed_idempotent.bats`: regression test

Added a test that sources the plugin (setup) *before* setting `_vault_local_port` — the
production order — and asserts the seed URL carries `localhost:8200` and never
`localhost:/`. Fails on the old frozen code, passes on the fix.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/shopping_cart.sh` | Remove source-time `:=` freeze of SEED_VAULT_ADDR/TOKEN/SOURCE_* |
| `scripts/tests/plugins/shopping_cart_seed_idempotent.bats` | Add empty-port-freeze regression test |

---

## Verification

- `shellcheck -S warning scripts/plugins/shopping_cart.sh` — clean
- `bash -n scripts/plugins/shopping_cart.sh` — OK
- `bats scripts/tests/plugins/shopping_cart_seed_idempotent.bats` — 6/6 pass
- Regression proof: new test is `not ok` on stashed (old) plugin, `ok` on the fix
- `./scripts/k3d-manager _agent_audit` — clean

## Follow-up (not fixed here)

`_vault_kv_put` uses `curl -sf … >/dev/null`, which swallows the HTTP status and hard-aborts
the whole cluster bring-up on any single KV write ≥ 400. Consider surfacing the HTTP code +
Vault error body on failure so future seed errors are diagnosable without a repro.
