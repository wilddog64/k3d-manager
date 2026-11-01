# Bug: the LDAP rotator decodes the Slack URL with `base64 --decode`, which BusyBox rejects, so it never posts

**Status:** OPEN
**Priority:** P3
**Severity:** low — LDAP passwords rotate; the rotation notice is never sent
**Approval:** operator, 2026-10-31 ("got ahead to file rotator bugs and dispatch to Luna")
**Filed:** 2026-10-31
**Detected by:** Claude, reading `ldap-password-rotator-29891520` logs on the M5 hub
**Affected:** `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl`
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-09-22-ci-red-prometheus-reseed-and-rotator-base64.md` (fixed the same defect in `scripts/etc/argocd/platform-ops/` only, `945018ee`); `docs/bugs/2026-10-31-rotator-slack-notice-failure-is-silent.md` (edits the same notice block; land this one first)

## Observed failure

The 2026-11-01T00:00Z run rotated both users ("2 succeeded, 0 failed"), then printed BusyBox's `base64` usage text
(`Usage: base64 [-d] [-w COL] [FILE]`). `slack_url` came out empty, so the notice block was skipped.

## Root cause

Line ~197 runs `base64 --decode`. The rotator image ships BusyBox `base64`, which accepts only `-d`. The
September fix changed the rotators under `platform-ops/` and its guard test only scans that directory, so this
template, under `scripts/etc/ldap/`, was missed. The two other `base64 -d` calls in the same file are already right.

## Fix

1. Change `base64 --decode` to `base64 -d` in `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl`.
2. Widen the existing guard (`scripts/tests/plugins/platform_ops_rotators.bats` or `ldap_password_rotator.bats`) so
   it fails on any `base64 --decode` in a container script under `scripts/etc/` (all rotators and CronJobs), not only
   `platform-ops/`.

## Files

- `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl`
- `scripts/tests/plugins/ldap_password_rotator.bats`
- `scripts/tests/plugins/platform_ops_rotators.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  M1: the LDAP rotator decodes the Slack URL with a form BusyBox base64 accepts, and the notice block receives the decoded URL
must_not:
  N1: no container script under scripts/etc/ contains "base64 --decode"
  N2: the guard is not vacuous; it reports a planted "base64 --decode" in a scratch copy of an etc/ template (paired control for N1)
evidence:
  E1:
    proves: [M1, N1, N2]
    kind: offline
    intent: >-
      You will see the guard fail on the pre-fix tree (names ldap-password-rotator.yaml.tmpl) and pass on the fix,
      and fail again on a scratch copy with "base64 --decode" planted. The fixture asserts it scans a scratch copy,
      not the real tree, for the planted case.
    what: bats scripts/tests/plugins/ldap_password_rotator.bats scripts/tests/plugins/platform_ops_rotators.bats
  E2:
    proves: [M1]
    kind: live
    intent: You will see a manual LDAP rotator run on the hub log no BusyBox usage text and attempt the Slack post.
    what: operator or Claude, kubectl create job --from=cronjob/ldap-password-rotator -n identity, then kubectl logs
interface:
  - scripts/etc/ldap/ldap-password-rotator.yaml.tmpl (rendered CronJob container script)
```
