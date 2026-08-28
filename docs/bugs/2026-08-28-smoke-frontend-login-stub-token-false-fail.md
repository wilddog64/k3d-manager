# make status: Frontend login false-FAILs when the smoke user is absent

**Date:** 2026-08-28
**Status:** SPEC → FIX
**Area:** `bin/k3dm-webhook` (`_smoke_test_logins`, ~lines 1771–1839)
**Severity:** Low (cosmetic) — a healthy hub reports a hard FAIL on `make status`.

## Symptom

With the hub fully healthy, `make status` reports:

- `Keycloak login: PASS — token minted (realm=master)`
- `Frontend login: FAIL — HTTP 401 on /api/cart`

The 401 is **correct** and expected, yet it surfaces as a hard failure,
turning an otherwise-green status red.

## Root cause

When the `k3dm-smoke-user` Secret is absent (the common dev state), the login
harness falls back to the Helm-deployed `keycloak-admin-secret` — a
**master-realm `admin-cli`** credential (lines 1785–1790). It mints a valid
admin token, so `Keycloak login` passes. The harness then calls the app
frontend's `/api/cart` with that admin token. The shopping-cart frontend
correctly rejects a master-realm admin token → **HTTP 401**.

The graceful-skip guard that converts an expected auth rejection into a
*skip* (rather than a FAIL) only fires for the smoke-client path:

```python
if kc_via_smoke_client and exc.code in (401, 403):   # line 1829
    _frontend_skipped = True
```

The admin-cli fallback token is **also** a stand-in (not a real shopping-cart
end-user), but `kc_via_smoke_client` is False on that path, so its correct 401
is reported as a hard FAIL.

## Fix (extend the skip to any stub token)

Introduce a single "the token is a stand-in, not a real cart-realm end-user"
flag and set it True on **both** stub paths (smoke-client and admin-cli
fallback). Gate the skip on that flag instead of `kc_via_smoke_client`.

- Add `kc_token_is_stub = False` alongside `kc_via_smoke_client` (line ~1773).
- In the smoke-client branch: `kc_token_is_stub = True`.
- In the admin-cli fallback branch (after line 1790): `kc_token_is_stub = True`.
- Line 1829 guard: `if kc_token_is_stub and exc.code in (401, 403):`
- Generalize the skip detail wording: `stand-in token rejected` instead of
  `smoke-client token rejected`.

`kc_via_smoke_client` may be retained for the client-id selection it already
drives, or folded into the new flag — the minimal change keeps both.

## Why this is safe (does not mask a real outage)

The skip is scoped to **401/403 only**. A genuinely-down frontend returns a
connection error or a 5xx, neither of which matches the guard, so a real
outage still surfaces as FAIL. Only the *expected auth rejection of a known
stand-in token* is downgraded to a skip. When a real
`K3DM_SMOKE_KC_USER/PASS` (or a seeded `k3dm-smoke-user` in the shopping-cart
realm) is supplied, `kc_token_is_stub` stays False and a 401 is again a
genuine FAIL.

## Durable follow-up — DONE (skip → true green)

**Status:** DONE 2026-08-28. The frontend-login line now asserts a real 200:

```
✓ Keycloak login: token minted (realm=shopping-cart)
✓ Frontend login: HTTP 200 on /api/cart
```

### What was actually wrong (three factors, all live-fixed)

1. **No `shopping-cart` realm** on the hub Keycloak. basket-service
   (`shopping-cart-apps` on `ubuntu-hostinger`) validates
   `OAUTH2_ISSUER_URI=https://keycloak.3ai-talk.org/realms/shopping-cart`, but
   the hub only had the LDAP-backed `home` realm. Created `shopping-cart`
   mirroring `home` (LDAP federation), plus a public direct-grant client
   `k3dm-smoke`.

2. **Issuer mismatch.** A token minted through any local host
   (`localhost:8880`, `keycloak.shopping-cart.local`) carried an `iss` of that
   host — never the public URL basket-service trusts. Keycloak derives `iss`
   from the request host **unless** the realm's `frontendUrl` is pinned. Set
   the `shopping-cart` realm `attributes.frontendUrl =
   https://keycloak.3ai-talk.org`. Now **every** token for that realm — minted
   locally, no Cloudflare round-trip — carries
   `iss=https://keycloak.3ai-talk.org/realms/shopping-cart`. Verified via
   `.well-known/openid-configuration`.

3. **LDAP bind broken on the cloned component.** The realm's LDAP
   `UserStorageProvider` was cloned from `home` via the admin API, which
   **masks** `bindCredential` as `**********`. The clone therefore bound with a
   literal `**********` → `LDAP error code 49 (Invalid Credentials)` →
   `unknown_error` on every federated-user token mint. Fixed by PUTting the
   real `LDAP_ADMIN_PASSWORD` (from Secret `openldap-admin`, key
   `LDAP_ADMIN_PASSWORD`; bindDn `cn=ldap-admin,dc=home,dc=org`) onto the
   component's `bindCredential`.

The smoke **user** is an LDAP entry (`cn=k3dm-smoke,ou=users,dc=home,dc=org`,
`inetOrgPerson`), because the READ_ONLY LDAP federation refuses local Keycloak
user creation (400 `Could not create user`).

### Webhook change (stub semantics)

With a real seeded smoke user, the `k3dm-smoke` path is **no longer a stub** —
it must green on 200 and *red* on a genuine 401 (a real regression), while only
the admin-cli/master fallback stays a graceful skip. Removed
`kc_token_is_stub = True` from the smoke-client branch (kept it on the
admin-cli fallback). Also made the seeded Secret authoritative for the realm:
the branch now reads an optional `realm` key from `k3dm-smoke-user`.
Graceful degradation on a fresh hub is preserved: with no `k3dm-smoke-user`
Secret the harness still falls to the admin-cli stub → skip, never a false red.

### Live state seeded (ephemeral — see codification below)

- Secret `identity/k3dm-smoke-user` (keys `username`, `password`, `realm`,
  `client`). Password supplied to `kubectl` via **stdin**, never argv.
- `shopping-cart` realm + `frontendUrl` + LDAP component (real bind cred) +
  `k3dm-smoke` client + `k3dm-smoke` LDAP user.

### Codification (durable — DONE 2026-08-28)

Implemented as **`keycloak_provision_shopping_cart_realm`** in
`scripts/plugins/keycloak.sh`. Idempotent; warns + returns 0 on any missing
prerequisite (never a hard failure). It:
- creates the `shopping-cart` realm and pins `attributes.frontendUrl` to
  `KEYCLOAK_SMOKE_ISSUER_BASE_URL` (default `https://keycloak.3ai-talk.org`,
  overridable to match the deployed app's `OAUTH2_ISSUER_URI` base) so every
  locally-minted token carries the public `iss` — no Cloudflare round-trip;
- clones the LDAP `UserStorageProvider` from `KEYCLOAK_SMOKE_SRC_REALM` (`home`)
  and **repairs the masked `bindCredential`** with the real LDAP admin password
  read from Secret `openldap-admin` (`_keycloak_smoke_ensure_ldap_component`);
- creates the `k3dm-smoke` public direct-grant client;
- adds the `k3dm-smoke` **LDAP entry** (`cn=k3dm-smoke,ou=users,dc=home,dc=org`)
  via `ldapadd`/`ldapmodify` in `openldap-0` — the READ_ONLY federation refuses
  local Keycloak users — with a **generated** password (reused from the existing
  Secret if present); bind password staged to a 0600 pod file over stdin, never
  on argv (`_keycloak_smoke_ensure_ldap_user`);
- writes Secret `identity/k3dm-smoke-user` (keys `username`, `password`, `realm`,
  `client`) for the webhook smoke harness.

Admin API is reached via `_keycloak_smoke_base_url`; set
`KEYCLOAK_BASE_URL=http://localhost:8880` (keycloak port-forward up) for a
reliable path. Verified live-idempotent: re-run over the hand-seeded state →
token `iss=https://keycloak.3ai-talk.org/realms/shopping-cart` → `/api/cart` 200.

The older `keycloak_seed_smoke_user` (`scripts/plugins/keycloak.sh`) remains but
is **not** the right entrypoint for this deployment: it targets Secret
`keycloak-secrets` (actual: `keycloak-admin-secret`), base URL
`keycloak.shopping-cart.local` (actual admin PF: `localhost:8880`), creates a
**local** Keycloak user (refused under READ_ONLY LDAP), and does not create the
realm or pin `frontendUrl`. Prefer `keycloak_provision_shopping_cart_realm`.

## Verification

1. Edit `bin/k3dm-webhook`; `make restart-webhook`.
2. `make status` → `✓ Frontend login: HTTP 200 on /api/cart` (was the false-red).
