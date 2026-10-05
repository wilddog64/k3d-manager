# `make deploy-worker` reports "k3dm-cloudflare-api-token missing" when the keychain is only locked

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. The operator is sent to `bin/k3dm-worker-setup` to re-create a token that exists.
**Status:** SPEC — dispatched to Codex 2026-10-04 (see "Fix spec")

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

## Fix spec (Claude, 2026-10-04)

Re-checked against the current `Makefile`: `deploy-worker` is now at :579–585, and
`restart-webhook` (:328) no longer reads the Keychain, so fix item 4 does not apply. Three Hermes
targets read the Cloudflare token the same way: `hermes-approvals-kv` (:947), `hermes-drain-token`
(:967) and `hermes-approvers` (:988). They test only that one item, so their message names the
right item, but it is equally wrong for a locked keychain.

### File 1 — `Makefile`

1. Add this variable directly above the `deploy-worker:` target's `##` help comment:

```make
# Defines _kc_read: print one k3dm Keychain item, or name the item and say whether
# the keychain is locked (a non-GUI session) or the item is missing. Never prints a value on error.
KEYCHAIN_READ = _kc_read() { _v=$$(security find-generic-password -s "$$1" -a k3dm -w 2>/dev/null) && [ -n "$$_v" ] && { printf '%s' "$$_v"; return 0; }; _info=$$(security show-keychain-info 2>&1 || true); case "$$_info" in *"User interaction is not allowed"*) echo "ERROR: $$1 unreadable — the login keychain is locked or not reachable from this session; run security unlock-keychain in a GUI terminal" >&2 ;; *) echo "ERROR: $$1 missing from Keychain — run $$2" >&2 ;; esac; return 1; }
```

2. Replace the first six recipe lines of `deploy-worker`:

```make
	@_cf=$$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -w 2>/dev/null) && \
	_tok=$$(security find-generic-password -s k3dm-webhook-token -a k3dm -w 2>/dev/null) && \
	_sig=$$(security find-generic-password -s k3dm-slack-signing-secret -a k3dm -w 2>/dev/null) && \
	[ -n "$$_cf" ] || { echo "ERROR: k3dm-cloudflare-api-token missing from Keychain — run bin/k3dm-worker-setup"; exit 1; } && \
	[ -n "$$_tok" ] || { echo "ERROR: k3dm-webhook-token missing from Keychain — run bin/k3dm-webhook-setup"; exit 1; } && \
	[ -n "$$_sig" ] || { echo "ERROR: k3dm-slack-signing-secret missing from Keychain — run bin/k3dm-worker-setup"; exit 1; } && \
```

   with

```make
	@$(KEYCHAIN_READ); \
	_cf=$$(_kc_read k3dm-cloudflare-api-token bin/k3dm-worker-setup) || exit 1; \
	_tok=$$(_kc_read k3dm-webhook-token bin/k3dm-webhook-setup) || exit 1; \
	_sig=$$(_kc_read k3dm-slack-signing-secret bin/k3dm-worker-setup) || exit 1; \
```

   The rest of the recipe, from `cd workers/slack-relay && \` on, is unchanged.

3. In each of `hermes-approvals-kv`, `hermes-drain-token` and `hermes-approvers`, replace the two
   lines

```make
	_cf=$$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -w 2>/dev/null || true); \
	[ -n "$$_cf" ] || { echo "ERROR: k3dm-cloudflare-api-token missing from Keychain — run bin/k3dm-worker-setup" >&2; exit 1; }; \
```

   with

```make
	$(KEYCHAIN_READ); \
	_cf=$$(_kc_read k3dm-cloudflare-api-token bin/k3dm-worker-setup) || exit 1; \
```

   Do not change the drain-token lookup in `hermes-drain-token`: an empty drain token is a valid
   "create one" path there.

### File 2 — new `scripts/tests/bin/makefile_keychain_read.bats`

Run `make -f "$MAKEFILE" deploy-worker` with a `security` stub and an `npx` stub first on `PATH`
(both under `$BATS_TEST_TMPDIR`). The `npx` stub appends to a calls file and exits 0.

1. Only `k3dm-slack-signing-secret` is missing: the stub exits 44 for that item, prints `x` for
   the others, and `show-keychain-info` exits 0. Expect status 1, output containing
   `k3dm-slack-signing-secret missing from Keychain — run bin/k3dm-worker-setup`, output **not**
   containing `k3dm-cloudflare-api-token` (assert with `[[ "$output" != *…* ]]`), and no `npx` call.
   This is the regression test for the old `&&` chain.
2. Locked keychain: every `find-generic-password` exits 36, and `show-keychain-info` prints
   `security: SecKeychainCopySettings: User interaction is not allowed.` to stderr and exits 36.
   Expect status 1, `k3dm-cloudflare-api-token unreadable`, `security unlock-keychain`, and no
   `missing from Keychain`.
3. No value leaks: in case 1, the output does not contain the stub's value `x` on a line of its
   own (assert no line equals `x`).
4. Static: each of `deploy-worker`, `hermes-approvals-kv`, `hermes-drain-token` and
   `hermes-approvers` contains `_kc_read k3dm-cloudflare-api-token`, and the `Makefile` no longer
   contains `find-generic-password -s k3dm-cloudflare-api-token`.

### File 3 — existing tests

- `scripts/tests/bin/k3dm_worker_setup.bats:34` greps the Makefile for
  `k3dm-cloudflare-api-token missing from Keychain`. Change it to grep
  `_kc_read k3dm-cloudflare-api-token bin/k3dm-worker-setup`.
- `scripts/tests/bin/makefile_hermes_approvals.bats`: its `security` stub must answer
  `show-keychain-info` with exit 0, so the missing-token test (:127) still sees
  `k3dm-cloudflare-api-token missing`. Change nothing else in it.

## Rules

- Modify only the files named above. Do not touch `bin/k3dm-worker-setup` or `workers/`.
- Never read the real Keychain: every test stubs `security` on `PATH`. Do not run
  `make deploy-worker` outside bats.
- Do not commit or push; leave changes unstaged.
- Run and paste: `bats scripts/tests/bin/makefile_keychain_read.bats scripts/tests/bin/k3dm_worker_setup.bats scripts/tests/bin/makefile_hermes_approvals.bats`,
  `bats scripts/tests/lib/bats_negation_lint.bats`, `make -n deploy-worker >/dev/null` (must parse).
- Mutation (snapshot `Makefile` to `$TMPDIR`, restore, `cmp`): put the old `&&` chain back in
  `deploy-worker` → test 1 red.
- Do not run `make test`.
