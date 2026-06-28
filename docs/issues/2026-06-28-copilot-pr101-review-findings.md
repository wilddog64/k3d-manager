# Copilot PR #101 Review Findings — v1.11.0 release

**PR:** [#101](https://github.com/wilddog64/k3d-manager/pull/101) — `feat: v1.11.0 — Tier 3 hub-Vault seeding + assisted-failover watchdog`
**Date:** 2026-06-28
**Reviewer:** Copilot (7 inline findings)

---

## Disposition summary

| # | File:line | Finding | Disposition |
|---|-----------|---------|-------------|
| 1 | `shopping_cart.sh:589` | `redis/cart` generated, never copied from canonical source | **Deferred** → `docs/bugs/v1.11.0-bugfix-seed-source-data-unused.md` |
| 2 | `shopping_cart.sh:597` | `redis/orders-cache` generated, never copied from source | **Deferred** (same spec) |
| 3 | `shopping_cart.sh:631` | `rabbitmq/default` generated, never copied from source | **Deferred** (same spec) |
| 4 | `vault.sh:1063` | source Vault token in `curl -H` argv (process listing exposure) | **Fixed** `b2ed5b80` |
| 5 | `vault.sh:1075` | target Vault token in `curl -H` argv | **Fixed** `b2ed5b80` |
| 6 | `vault.sh:1177` | `_vault_ns` assigned but never used in `vault_failover_hub_into_context` | **Fixed** `b2ed5b80` |
| 7 | `docs/api/functions.md:46` | new v1.11.0 Vault operators missing from the function index | **Fixed** (docs commit) |

---

## Fixed in this PR

### Findings 4 & 5 — Vault tokens in `curl` argv (security)

Directly violated the repo rule *"Vault tokens must never appear in script arguments visible in
shell history or CI logs."* `vault_seed_hub_into_context` passed both root tokens via
`-H "X-Vault-Token: ${_src_token}"` / `${_dst_token}`, which are visible to any `ps` during the
seeding loop.

**Fix:** write each token to a `mktemp` header file (`chmod 600`) holding a curl
`header = "X-Vault-Token: …"` directive, and invoke `curl --config "${_hdr}"`. The token now lives
only in a 0600 file (removed in the existing `RETURN` trap alongside the port-forward kills) and
never appears in argv. Verified the header is still transmitted (`curl --config` → listener captured
`X-Vault-Token`).

Before:
```bash
_json=$(curl -sf -H "X-Vault-Token: ${_src_token}" \
  "http://localhost:${_src_port}/v1/secret/data/${_key}" | jq -c '.data.data // empty' ...)
```
After:
```bash
_json=$(curl -sf --config "${_src_hdr}" \
  "http://localhost:${_src_port}/v1/secret/data/${_key}" | jq -c '.data.data // empty' ...)
```

### Finding 6 — unused `_vault_ns`

`vault_failover_hub_into_context` declared `local _vault_ns="${VAULT_NS:-secrets}"` but never used
it (the probe helper resolves its own namespace). Removed.

### Finding 7 — API docs

Added `vault_seed_hub_into_context`, `vault_failover_hub_into_context`, and
`vault_install_failover_watchdog` to `docs/api/functions.md`.

---

## Deferred (with follow-up spec)

### Findings 1–3 — canonical-source reader defined but never called

`shopping_cart.sh` defines `_seed_source_data()` (the canonical-source reader backing
`SEED_VAULT_SOURCE_ADDR` / `SEED_VAULT_SOURCE_TOKEN`), but the `redis/cart`, `redis/orders-cache`,
and `rabbitmq/default` (and the `postgres/*`) generate-if-absent branches never call it — so
`SEED_VAULT_SOURCE_*` is effectively dead in this file.

**Why deferred, not fixed inline:** this is a behavioral change to the laptop-side seeding path
(switching generate-if-absent to copy-from-source-then-generate), which needs its own spec + tests
under the spec-before-implement rule — not a same-PR quick fix during a release. It is **not a
regression**: the active canonical-copy path for the in-cluster cutover is the *other* operator,
`vault.sh:vault_seed_hub_into_context`, which already reads from the source Vault; and in the default
configuration `SEED_VAULT_SOURCE_*` resolves to the same Vault, so a fresh-target seed produces the
same result either way.

**Follow-up:** `docs/bugs/v1.11.0-bugfix-seed-source-data-unused.md`.

---

## Process note

The token-in-argv pattern (findings 4/5) recurs across the codebase (e.g. the `_vault_kv_*` helpers
in `shopping_cart.sh`). The new-code path was fixed here; the spec template for any function that
calls a Vault HTTP API should mandate the `curl --config` (mode-600 header file) idiom rather than
`-H "X-Vault-Token: …"`, so this class of finding is caught at spec time.
