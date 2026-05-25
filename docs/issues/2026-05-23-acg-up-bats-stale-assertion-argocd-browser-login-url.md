# acg-up BATS assertion still expects old ArgoCD login URL text

**Date:** 2026-05-23
**Area:** `scripts/tests/bin/acg_up.bats`
**Attempted validation:** `bats scripts/tests/bin/acg_up.bats`

## What was tested

Ran the targeted `acg-up` contract suite after adding LaunchDaemon plist idempotency guards in `bin/acg-up`.

## Actual output

```text
1..2
not ok 1 acg-up sources the Argo CD plugin before readiness checks
# (in test file scripts/tests/bin/acg_up.bats, line 105)
#   `[ "$status" -eq 0 ]' failed
ok 2 acg-up preserves existing Vault identity secrets on rebuild
```

## What happened

The failing assertion expects an older `ArgoCD browser login URL: https://argocd.shopping-cart.local` string, but `bin/acg-up` now emits `ArgoCD reachable at https://${ARGOCD_BROWSER_HOST:-argocd.shopping-cart.local} (launchd: ...)`.

## Follow-up

Update the BATS expectation to match the current script wording, or replace the brittle grep with a more stable assertion that checks the readiness flow rather than the exact log phrasing.
