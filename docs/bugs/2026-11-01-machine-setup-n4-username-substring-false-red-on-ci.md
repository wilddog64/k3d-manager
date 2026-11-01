# Bug: machine-setup N4 fails on GitHub CI because the runner user `runner` is a substring of a hub Keychain service name

**Status:** VERIFIED — fixed on `k3d-manager-v1.43.13` (Claude, test-only)
**Priority:** P3
**Severity:** low — test-only; it turns CI red on every PR, and the code under test has no defect
**Approval:** operator, 2026-11-01 (session goal: finish v1.43.13 and create the PR; found on PR #155 CI)
**Filed:** 2026-11-01
**Detected by:** Claude, PR #155 CI run `41337526186` (`not ok 682 N4: report output has no username and no home path`)
**Affected:** `scripts/tests/bin/machine_setup_acceptance.bats` (N4, ~line 504)
**Branch:** `k3d-manager-v1.43.13`

## Observed failure

On GitHub Actions, `id -un` is `runner`. The hub report prints `secret:k3dm-webhook-token-cloud-runner:k3dm`, an entry
added in `fd25a55d`. N4's substring check `*"$(id -un)"*` matched `cloud-runner` and failed. The test passes on the M4,
whose user is not a substring of any manifest name. With `id -un` stubbed to `runner`, it fails locally too.

## Fix

N4 now matches the username only as a whole token: no letter, digit, `_`, `.` or `-` on either side. A real leak
(`/Users/runner/...`, `:runner`, a bare `runner`) still fails the test. The `/Users/`, `$HOME_FX` and `$UNAME_USER`
checks are unchanged.

## What NOT to do

- Do not rename the `k3dm-webhook-token-cloud-runner` Keychain service; it is real.
- Do not drop the username check.

## Acceptance

```yaml
must:
  M1: N4 passes with id -un reporting runner on a report that contains k3dm-webhook-token-cloud-runner
  M2: the username pattern still matches /Users/runner/x, secret:x:runner and a bare runner (paired positive control)
must_not:
  N1: N4 never passes on a report that contains the username as a path component or account field
evidence:
  E1:
    proves: [M1, M2, N1]
    kind: offline
    intent: You will see N4 fail with an id stub printing runner on the pre-fix test, pass on the fix, and the fixed pattern match the three leak forms.
    what: PATH=<id stub>:$PATH bats -f N4 scripts/tests/bin/machine_setup_acceptance.bats
interface:
  - scripts/tests/bin/machine_setup_acceptance.bats N4
```

## Verification (2026-11-01, Claude)

- Pre-fix, with an `id` stub printing `runner`: `not ok 1 N4` at line 511, the same failure as CI.
- Post-fix: N4 passes with the stub and without it. The pattern matches `/Users/runner/x`, `secret:x:runner missing`
  and `runner`, and does not match `secret:k3dm-webhook-token-cloud-runner:k3dm ok`.
- Errors seen: none beyond the CI failure above. The PR's first CI run on `90c18db9` was cancelled by the next push,
  so this failure was first seen on `cce1b7f2`.
