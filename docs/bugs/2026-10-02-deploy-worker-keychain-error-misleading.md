# `make deploy-worker` reports "k3dm-cloudflare-api-token missing" when the keychain is only locked

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. The operator is sent to `bin/k3dm-worker-setup` to re-create a token that exists.
**Status:** OPEN

## Symptom

On 2026-10-02, `make deploy-worker` run from the Claude Code `!` shell printed:

```
ERROR: k3dm-cloudflare-api-token missing from Keychain — run bin/k3dm-worker-setup
```

All three items were present: `security find-generic-password -s <item> -a k3dm` without `-w`
succeeded for each one. `security show-keychain-info` printed `User interaction is not allowed`,
because the login keychain was locked in that session. The same command succeeded from a GUI terminal.

## Cause

`Makefile` `deploy-worker` (lines 530–535):

- The three `security … -w 2>/dev/null` lookups and the first `[ -n "$_cf" ]` test are joined by `&&`.
  The first `|| { echo "…cloudflare-api-token missing…" }` therefore fires when **any** of the three
  lookups fails.
- `2>/dev/null` hides `User interaction is not allowed`, the one message that tells a locked keychain
  apart from a missing item.

## Fix

1. Look up each item separately, and keep `security`'s exit status.
2. When a lookup fails, print the item's name. If `security show-keychain-info` reports
   `User interaction is not allowed`, add: "login keychain is locked or not reachable from this session —
   run `security unlock-keychain` in a GUI terminal". Otherwise, keep the existing "run bin/…-setup" hint.
3. Never print a value. Keep `-w` output captured only in variables.
4. Apply the same split to the `restart-webhook` lookups at lines 587–588, if they share the pattern.

## Tests

Update `scripts/tests/bin/k3dm_worker_setup.bats`, which greps the Makefile for the message, so the
per-item messages and the locked-keychain hint are asserted.
