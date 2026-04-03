# Issue: Missing scripts/tests/lib/system.bats in k3d-manager

**Date:** 2026-03-22
**Owner:** Codex

## Summary

`docs/plans/v0.9.7-system-sh-sync-from-foundation.md` requires running `bats scripts/tests/lib/system.bats`
after syncing `scripts/lib/system.sh`. The canonical tests exist inside the lib-foundation subtree at
`scripts/lib/foundation/scripts/tests/lib/system.bats`, but the local mirror under `scripts/tests/lib/`
was removed sometime after v0.9.5. As a result the documented command fails with:

```
ERROR: Test file ".../scripts/tests/lib/system.bats" does not exist.
```

This blocks the required proof-of-work gate when updating `system.sh`.

## Impact

- Specs referencing `scripts/tests/lib/system.bats` cannot be satisfied; contributors must rerun the
  subtree version manually.
- Automation (including `_agent_audit` or CI jobs) cannot add `system.sh` coverage without reintroducing
  the mirrored test file.

## Proposed Fix

- Restore `scripts/tests/lib/system.bats` from lib-foundation (keeping it in sync with the upstream copy),
  or update the spec + helper scripts to invoke the subtree path directly.
- Add a guard in `_agent_audit` or the spec template to fail fast with a clearer message when a referenced
  test suite is missing.
