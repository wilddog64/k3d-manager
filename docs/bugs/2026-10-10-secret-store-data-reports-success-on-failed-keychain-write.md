# Bug: `_secret_store_data` returns 0 when the Keychain write fails

**Branch:** `k3d-manager-v1.43.0`
**Filed:** 2026-10-10
**Status:** OPEN — fix upstream in lib-foundation, then subtree-pull
**Priority:** P2
**Severity:** Medium — a failed Keychain write reports success, so callers carry on as if the secret were stored
**Files:** `scripts/lib/foundation/scripts/lib/system.sh` (upstream: lib-foundation `scripts/lib/system.sh`)

## Symptom

`make vault-dr-shards-save` run from a session without a GUI login printed
`security: SecKeychainItemCreateFromContent (<default>): User interaction is not allowed.` twice and
exited 0. Nothing was stored.

## Cause

The macOS branch of `_secret_store_data`:

```bash
if ! _no_trace bash -c 'security add-generic-password ...' _ ...; then
   rc=$?
fi
return "$rc"
```

`$?` after a negated command is the status of the negation, which is 0 inside the `then` branch. So
`rc` stays 0 and every failed write returns success.

## Fix

Capture the status without negation, e.g. `_no_trace bash -c '...' _ ... || rc=$?`. Fix it together
with `docs/bugs/2026-10-09-secret-store-data-puts-value-in-security-argv.md`, which rewrites the same
call.

## Tests (lib-foundation BATS)

- A stub `security` that exits 36 on `add-generic-password`: `_secret_store_data` returns non-zero.
- Mutation: restore `if ! ...; then rc=$?`; the test goes red.
