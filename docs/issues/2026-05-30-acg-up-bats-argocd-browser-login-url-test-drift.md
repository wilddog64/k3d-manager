# 2026-05-30 — `scripts/tests/bin/acg_up.bats` assertion drift on ArgoCD browser login URL

## What was tested

- `bats scripts/tests/bin/acg_up.bats`

## Actual output

```text
1..2
not ok 1 acg-up sources the Argo CD plugin before readiness checks
# (in test file scripts/tests/bin/acg_up.bats, line 105)
#   `[ "$status" -eq 0 ]' failed
ok 2 acg-up preserves existing Vault identity secrets on rebuild
```

## Root cause

The failing assertion is a grep-based expectation in `scripts/tests/bin/acg_up.bats` for:

- `ArgoCD browser login URL: https://argocd.shopping-cart.local`

That string is not present in the current `bin/acg-up`, so the test appears to be stale test coverage rather than a regression from the Vault CA PTY or `redis-cart-secret` fixes in this task.

## Recommended follow-up

- Update `scripts/tests/bin/acg_up.bats` to match the current `bin/acg-up` text, or remove the stale assertion if the message was intentionally changed in a previous refactor.
