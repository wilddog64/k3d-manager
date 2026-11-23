# Bug: password-bundle M6 add-laptop test fails on Linux CI

**Status:** LANDED — test-only fix on `k3d-manager-v1.45.0` (this commit); CI green on it pending
**Priority:** P3 (test-only; it blocks the release PR while CI is red)
**Introduced by:** `39a24a59` (travel bundle rev 2, `password-bundle-add-laptop`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** scheduled run — since 2026-11-21 (the next CI run on the release head)
**Prior art:** exact slug: none; grep `_is_mac` in docs/bugs 2026-11: `2026-11-12-test-hygiene-batch-tripwire-host-writes-and-fresh-clone.md` — read, different root cause; `make find-similar-docs` not run (vector store unreachable from the M4, 2026-11-21)
**Approval:** operator, 2026-11-21: "go ahead to execute your plan" (plan step 3: find the cause of the Linux CI red)
**Branch:** `k3d-manager-v1.45.0`

## Symptom

CI `test (3)` red on `af2cc5d9` (run 44954623760) and `6c75d60b` (run 44968645013): `password_bundle.bats` "M6 add-laptop
forces publication for the new identity and installs the schedule", line 190, `[ "$status" -eq 0 ]`. It passes on the M4.

## Root cause

`password_bundle_add_laptop` ends in `password_bundle_install`, which starts with `_is_mac || return 1`
(`scripts/plugins/password_bundle.sh:178`). On `ubuntu` `uname -s` is `Linux`, so `make password-bundle-add-laptop` exits
1. The product is correct (the schedule is a LaunchAgent; the hub and laptops are macOS); the test assumed a Mac host.
N6 and N7 assert "does not install the schedule" and were vacuously green on Linux for the same reason.

## Fix

`scripts/tests/plugins/password_bundle.bats`: helper `as_mac_host` (asserts the test bin dir is first on PATH, writes a
`uname` stub answering `Darwin` and a `launchctl` stub that logs and exits 97), called by M6, N6 and N7. M6 also asserts
`launchctl` was never called (`K3DM_AGENT_LOAD=0`). Same `uname` idiom as `argocd_keychain_unreadable.bats:10`.

Evidence (Claude, m4-air, 2026-11-21): with a `uname` answering `Linux` first on PATH, pre-fix M6 fails at line 190 (the
CI failure, reproduced); with the fix M6, N6 and N7 pass. Full suite 15/15 on macOS.
