# Bug: two `hermes-approvals-kv` tests fail because their fixture copies the bound `wrangler.toml`

**Filed:** 2026-10-04, Claude (found while verifying the deploy-worker keychain fix)
**Branch:** `k3d-manager-v1.41.0`
**Status:** FIXED — Codex, verified by Claude 2026-10-04: 12/12 green; commenting out the `sed` turns 3 tests red. Codex also appends the commented `<namespace-id>` template to the copy, which this spec missed: the target rewrites that template in place and fails without it.
**Severity:** low, test-only. Two tests are red at HEAD, and the code paths they cover
(first-time KV binding, a failed `wrangler kv namespace create`) are untested until fixed.

## Observed

`bats scripts/tests/bin/makefile_hermes_approvals.bats` at HEAD fails 2 of 11 tests, before and after
`097a5134`:

- `hermes-approvals-kv binds the returned namespace id only once`
- `hermes-approvals-kv shows wrangler's output when namespace create fails`

## Cause

`setup()` (:9) copies the real `workers/slack-relay/wrangler.toml` into `$BATS_TEST_TMPDIR/relay`.
`42c51bf8` (2026-10-04) bound the live namespace in that file:

```toml
[[kv_namespaces]]
binding = "APPROVALS_KV"
id = "ee9eb140ea624a09802fef9e16396caf"
```

`hermes-approvals-kv` exits 0 with "already bound — nothing to do" when it sees that `binding` line.
So both tests stop before `npx` runs: the first never gets the stub's id, and the second never sees
the create failure.

## Fix spec

### File 1 — `scripts/tests/bin/makefile_hermes_approvals.bats`

Directly after the `cp` at :9, add one line that removes the `[[kv_namespaces]]` block for
`APPROVALS_KV` from the **copy** (the header line, the `binding` line and the `id` line):

```bash
  sed -i.bak '/^\[\[kv_namespaces\]\]$/,/^id = /d' "${RELAY_DIR}/wrangler.toml"
```

Then add one test, right after `hermes-approvals-kv binds the returned namespace id only once`:

- `the test fixture starts unbound`: assert that no line of the copy matches
  `^binding = "APPROVALS_KV"$` (`run grep -q ...` then `[ "${status}" -ne 0 ]`). Also assert that
  the real file still has it:
  `grep -q '^binding = "APPROVALS_KV"$' "${BATS_TEST_DIRNAME}/../../../workers/slack-relay/wrangler.toml"`.

Do not edit `workers/slack-relay/wrangler.toml` or the `Makefile`.

## Rules

- Modify only File 1. Do not commit or push; leave changes unstaged.
- Run and paste: `bats scripts/tests/bin/makefile_hermes_approvals.bats` (all green),
  `bats scripts/tests/lib/bats_negation_lint.bats`, and `git status --short` (the real
  `wrangler.toml` must not show as modified).
- Mutation: comment out the new `sed` line, show that the two tests named above and the new test go
  red, restore, and prove it with `cmp` against a snapshot in `$TMPDIR`.
- Do not run `make test`.

## Done when

The suite is 12/12 green, the real `wrangler.toml` is unchanged, and the mutation turns 3 tests red.
