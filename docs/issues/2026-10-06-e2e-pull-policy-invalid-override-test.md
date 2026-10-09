# E2E pull-policy invalid override test initially continued after error

**Date:** 2026-10-06
**Status:** Resolved in the v1.42.0 E2E pull-policy fix
**Related bug:** `docs/bugs/2026-10-06-e2e-runner-ifnotpresent-serves-stale-latest-image.md`

## What was attempted

The first implementation added `E2E_IMAGE_PULL_POLICY` validation and a BATS case requiring
an invalid value to fail manifest rendering.

## Actual output

```text
1..66
...
ok 25 explicit E2E image pull policy overrides tag-derived default
not ok 26 invalid E2E image pull policy is rejected
# (in test file scripts/tests/plugins/e2e.bats, line 416)
#   `[ "$status" -ne 0 ]' failed
...
```

## Root cause

The manifest functions assigned the helper through command substitution without checking the
assignment status. `_err` exited the command-substitution subshell, but the manifest function
continued to render the Job because the failed assignment was not explicitly handled.

## Resolution

Both manifest functions now check the pull-policy assignment and return nonzero when policy
validation fails. The full `scripts/tests/plugins/e2e.bats` suite subsequently passed 66/66.
