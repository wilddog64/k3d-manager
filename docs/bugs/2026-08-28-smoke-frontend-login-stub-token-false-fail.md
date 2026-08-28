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

## Durable follow-up (not required for this fix)

Seed a real `k3dm-smoke-user` in the shopping-cart realm so the frontend login
exercises a true end-user path and actually asserts a 200 — turning this from
a skip into a real positive check. Tracked separately; the guard fix above
stops the false-red today.

## Verification

1. Edit `bin/k3dm-webhook`; `make restart-webhook`.
2. `make status` → `Frontend login: SKIP — stand-in token rejected (HTTP 401 on /api/cart)`; overall no longer red on this line.
