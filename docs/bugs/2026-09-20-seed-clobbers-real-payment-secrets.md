# Seeding unconditionally clobbers the real Stripe, PayPal and encryption secrets

**Filed:** 2026-09-20
**Branch:** `k3d-manager-v1.36.0`
**Severity:** High — blocks the hub rebuild. A rebuild today injects a placeholder Stripe key.

## Symptom

Found while planning the hub rebuild that clears the kine stall. Every other canonical secret in
the seeding path is carefully guarded; three are not.

`scripts/plugins/shopping_cart.sh:716-718`:

```bash
  _vault_kv_put '{"key":"dmF1bHQtZGV2LXNhbmRib3gtZW5jcnlwdGlvbg=="}'                             payment/encryption
  _vault_kv_put '{"api_key":"sk_test_placeholder","webhook_secret":"whsec_placeholder"}'           payment/stripe
  _vault_kv_put '{"client_id":"paypal_sandbox_client_id","client_secret":"paypal_sandbox_client_secret"}' payment/paypal
```

No `_vault_kv_exists` guard, no `_seed_source_data` fallback, no conditional of any kind.

**This is the unfinished third instalment of a deliberately staged parity effort, not a new
discovery.** The history:

1. `176ec5a6` wired `_seed_source_data` into the **six single-password** branches — `redis/cart`,
   `redis/orders-cache`, `postgres/{orders,products,payment}`, `rabbitmq/default`.
2. `docs/bugs/v1.12.0-bugfix-seed-source-parity-minio-ldap-keycloak.md` brought the **four
   multi-field** branches to parity — `minio/credentials`, `ldap/admin`, `keycloak/admin`,
   `keycloak/clients`. That spec states the multi-field branches "were deliberately left out of
   that change for reviewability."
3. **Never done:** `payment/encryption`, `payment/stripe`, `payment/paypal`. They were skipped in
   both passes because they are not generate-if-absent branches at all — they are unconditional
   literal writes, so neither pass's pattern matched them.

`github/pat` is out of scope: it is handled separately and conditionally in a different function
(`scripts/plugins/shopping_cart.sh:272, 313, 333`), not in the unconditional block.

Ten of the fourteen canonical keys are guarded. These three are the remainder — and they are the
worst three to have left, because they are the only ones that are **externally issued** and
therefore cannot be correctly regenerated.

Compare the immediately preceding block for `postgres/payment` (lines 702–715), which does it
correctly:

```bash
  if _vault_kv_exists "postgres/payment"; then
    _info "[acg-up] Reusing existing Vault secret postgres/payment"
    ...
  else
    _src_json=$(_seed_source_data "postgres/payment")
    if [[ -n "${_src_json}" ]]; then
      ...
    else
      ... generate fresh
    fi
  fi
```

## Why it matters

`bin/cluster-up:851` calls `deploy_shopping_cart_data`, so **every `make up` overwrites these
three keys.** For the regenerable infra passwords that is harmless — the services are redeployed
in the same run and ESO syncs the new values, so the system stays self-consistent. These three are
different:

- **`payment/stripe`** — the Stripe **test secret key** is issued by Stripe. It cannot be
  regenerated locally. Overwriting it with `sk_test_placeholder` breaks every Stripe call.
  There is a Keychain backup precisely because of this: service `k3dm-stripe-sk-test` (verified
  present 2026-09-20).
- **`payment/paypal`** — same shape; externally issued, replaced with sandbox literals.
- **`payment/encryption`** — a hardcoded base64 dev key, identical on every run. Anything
  encrypted with a previous key becomes unreadable. Lower impact on a full rebuild (the Postgres
  volumes are destroyed too) but it is still a hardcoded shared secret being written
  unconditionally.

**This is the rebuild blocker.** `make down && make up` destroys the hub Vault; on the way back up
this code writes a placeholder Stripe key rather than restoring the real one. The rebuild would
"succeed" and leave payments broken in a way that looks like an application bug.

## Not claimed

`payment-service` is currently `0/1 Running` with 13 restarts. It is **plausible** that a previous
seeding run already clobbered `payment/stripe` and that is the cause, but this was **not
verified** — `kubectl logs` against that pod fails with
`net/http: TLS handshake timeout` from the kubelet, because the apiserver is degraded by the kine
stall. Do not record the placeholder key as the cause of the payment-service restarts without
reading those logs once the cluster is healthy. There is also an open unrelated candidate: the
`fix/keycloak-role-authority-mapping` work in `shopping-cart-payment` (P3).

## Fix

Guard all three the same way the rest of the function does, and give `payment/stripe` a Keychain
fallback before the placeholder. Replace lines 716–718 with:

```bash
  if _vault_kv_exists "payment/encryption"; then
    _info "[acg-up] Reusing existing Vault secret payment/encryption"
  else
    _src_json=$(_seed_source_data "payment/encryption")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying payment/encryption from canonical source Vault"
      _vault_kv_put "${_src_json}" payment/encryption
    else
      _vault_kv_put '{"key":"dmF1bHQtZGV2LXNhbmRib3gtZW5jcnlwdGlvbg=="}' payment/encryption
    fi
  fi

  if _vault_kv_exists "payment/stripe"; then
    _info "[acg-up] Reusing existing Vault secret payment/stripe"
  else
    _src_json=$(_seed_source_data "payment/stripe")
    if [[ -z "${_src_json}" ]]; then
      _stripe_sk="$(_no_trace security find-generic-password -s k3dm-stripe-sk-test -w 2>/dev/null || true)"
      if [[ -n "${_stripe_sk}" ]]; then
        _info "[acg-up] Restoring payment/stripe api_key from Keychain backup"
        _src_json=$(jq -cn --arg k "${_stripe_sk}" '{api_key:$k,webhook_secret:"whsec_placeholder"}')
      fi
    fi
    if [[ -n "${_src_json}" ]]; then
      _vault_kv_put "${_src_json}" payment/stripe
    else
      _warn "[acg-up] no Stripe key available — writing placeholder; Stripe calls will fail"
      _vault_kv_put '{"api_key":"sk_test_placeholder","webhook_secret":"whsec_placeholder"}' payment/stripe
    fi
  fi

  if _vault_kv_exists "payment/paypal"; then
    _info "[acg-up] Reusing existing Vault secret payment/paypal"
  else
    _src_json=$(_seed_source_data "payment/paypal")
    if [[ -n "${_src_json}" ]]; then
      _info "[acg-up] Copying payment/paypal from canonical source Vault"
      _vault_kv_put "${_src_json}" payment/paypal
    else
      _vault_kv_put '{"client_id":"paypal_sandbox_client_id","client_secret":"paypal_sandbox_client_secret"}' payment/paypal
    fi
  fi
```

**The Keychain accessor is the one already proven in this repo** — `scripts/plugins/e2e.sh:271`:

```bash
stripe_secret_key="$(_no_trace security find-generic-password -s k3dm-stripe-sk-test -w 2>/dev/null || true)"
```

Service `k3dm-stripe-sk-test`, **no `-a`** (there is exactly one item for that service; its account
is the local username, so do not hardcode an account name), wrapped in `_no_trace` so the value
never reaches a trace or log. Reuse that form exactly. Do not invent a different helper — an
earlier draft of this spec used `_secret_load_data ... "sk_test"`, which is wrong on both the helper
and the account. Never echo, log or commit the key.

## Tests

`scripts/tests/plugins/shopping_cart_seed_idempotent.bats` already exists and is the right home.
Add cases asserting:

1. When `payment/stripe` already exists in the target Vault, no `_vault_kv_put` for that path is
   issued (reuse branch).
2. When it does not exist and the source Vault returns data, the source JSON is written and the
   placeholder literal `sk_test_placeholder` is **not** written.
3. Same two cases for `payment/paypal` and `payment/encryption`.

Follow the stubbing style already used in that file. No bare `!` and no whole-line `grep -F` in
assertions — assert on meaningful tokens.

## Definition of Done

- [ ] All three keys guarded; the placeholder is reachable only as a last resort
- [ ] `payment/stripe` falls back to the Keychain backup before the placeholder
- [ ] Keychain account name verified with a no-`-w` existence check; report what it is
- [ ] BATS cases above pass
- [ ] `shellcheck scripts/plugins/shopping_cart.sh` — zero new warnings
- [ ] `make test` green, or failures shown to be pre-existing
- [ ] CHANGELOG `[Unreleased] → ### Fixed`
- [ ] Commit message exactly:
      `fix(seed): stop clobbering real Stripe, PayPal and encryption secrets on every up`
- [ ] Pushed to `origin/k3d-manager-v1.36.0`, SHA reported
- [ ] `memory-bank/activeContext.md` + `progress.md` updated

## What NOT to Do

- Do NOT create a PR. Do NOT merge. Do NOT commit to `main`.
- Do NOT use `--no-verify`.
- Do NOT print, echo, log or commit any real secret value. No `security -w`.
- Do NOT modify files outside `scripts/plugins/shopping_cart.sh`,
  `scripts/tests/plugins/shopping_cart_seed_idempotent.bats`, `CHANGELOG.md`, `memory-bank/`.
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/` (subtrees).
- Do NOT run `make up`, `make down`, `deploy_shopping_cart_data`, or any other live cluster
  mutation. The hub is mid-incident. This task is code and offline tests only.
