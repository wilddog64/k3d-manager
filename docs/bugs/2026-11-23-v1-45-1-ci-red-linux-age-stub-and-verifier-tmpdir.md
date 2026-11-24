# Bug: v1.45.1 CI red on Linux: dr_drill secret-tool stub lacks the age identity; verifier test needs TMPDIR

**Status:** LIVE-VERIFIED — CI run 45294470789 on 5162281e green on all 7 checks (test 1-4, test-python, lint, alertmanager-behaviour), checked 2026-11-23 by Claude; LANDED — test-only fixes `7a84f90d` and `037a7ab8` on `k3d-manager-v1.45.1` (Claude)
**Priority:** P1 (proposed: CI red on the release branch blocks `make hub-deploy`, which requires green checks; also blocks the release PR)
**Introduced by:** `77d5a836` (age-identity fix, dr_drill.bats) and `4b831c81` (cve-scan private kubeconfig, cve_remediation_verify.bats)
**Should have been caught by:** review (both lands were verified on macOS only, where `uname -s` is Darwin and `TMPDIR` is always set)
**Introducing change reviewed:** yes (Claude land review plus a Sonnet acceptance verifier, both macOS)
**Prior art:** `docs/bugs/2026-11-12-dev-hub-bats-tmpdir-unset-on-linux-ci.md` (name grep, read) — same escape class and same TMPDIR fix; `make find-similar-docs` not run
**Detected by:** operator, 2026-11-23: `make hub-deploy REF=7b690cd3` refused, "GitHub check runs are pending or failed"; CI run 45288874536 had test (2) and test (3) red
**Fix commit:** 7a84f90d, 037a7ab8
**Live evidence:** 2026-11-23 · run 45294470789 · env github-actions/ubuntu · scenario ci-green · commit 5162281e · proves fix

## What is wrong

1. `scripts/tests/bin/dr_drill.bats`: `_secret_load_data` reads from `security` on macOS and from `secret-tool` on
   Linux (`scripts/lib/foundation/scripts/lib/system.sh:612-618`). The age-identity check added in `77d5a836` reads
   `k3dm-hub-data-age`. The test's `security` stub answers it, but the `secret-tool` stub has no case for it and prints
   the shard sentinel. On Linux the drill therefore sees a non-`AGE-SECRET-KEY-1` identity and refuses with exit 2:
   25 of 35 tests red on test (3).
2. `scripts/tests/plugins/cve_remediation_verify.bats:135` passes `TMPDIR="$TMPDIR"` under `set -u`. The ubuntu runner
   does not set `TMPDIR`, so tests 4–9 abort with `TMPDIR: unbound variable` on test (2). Test 8 skips on macOS
   (BSD sed), so only 5 reproduce locally.

## Fix (landed)

- `secret-tool` stub: add `*'service k3dm-hub-data-age'*) printf '%s' "${DR_TEST_AGE_IDENTITY-AGE-SECRET-KEY-1FAKE}"`,
  mirroring the `security` stub.
- Line 135: `TMPDIR="${TMPDIR:-/tmp}"`, as in `6202cc45`.

Evidence on m4, 2026-11-23, Linux simulation (a `uname` shim printing `Linux` for `-s`, `TMPDIR` unset):

| Suite | Pre-fix | Fixed |
|---|---|---|
| dr_drill.bats (Linux sim) | 25/35 red (matches CI) | 0/35 |
| cve_remediation_verify.bats (Linux sim) | 5/9 red (test 8 skipped: BSD sed) | 0/9 |
| dr_drill.bats (macOS) | — | 0/35 |

## Recurrence — 2026-11-23 (CI run 45291816630 on 53b23fab)

test (3) went green; test (2) still had test 8 red: `grep: .../k3dm-kc.XXXX/config: No such file or directory`. A
third defect from `4b831c81`, hidden by the TMPDIR abort: test 8 greps the loader's live kubeconfig after the loader
has exited and removed its directory (test 4 asserts that removal). It skips under BSD sed, so it had never run
anywhere before. Fix `037a7ab8`: assert the live file is gone and read the kubectl stub's capture (`$probe/config`),
as test 9 does. Alpine 3.20 container with GNU sed, m4, 2026-11-23: pre-fix test 8 red with CI's exact error, fixed
cve_remediation_verify.bats 9/9. (dr_drill does not run on Alpine; ubuntu CI test (3) is green for it.)

## Acceptance

```yaml
must:
  - id: M1
    text: dr_drill.bats passes on the ubuntu CI runner (secret-tool path) and on macOS
  - id: M2
    text: cve_remediation_verify.bats passes on the ubuntu CI runner with TMPDIR unset
must_not:
  - id: N1
    text: no CI shard on the release head may be red from these two suites
    red_on_current: run 45288874536 on 7b690cd3, test (2) and test (3) red
evidence:
  - {id: E1, proves: [M1, M2], kind: offline, intent: "Both suites pass under a Linux simulation and fail as CI did before the fix (table above)."}
  - {id: E2, proves: [M1, M2, N1], kind: live, intent: "The CI run on the pushed head is green on all four BATS shards, so make hub-deploy accepts it."}
```

## Process note

Third Linux-only escape from a macOS-verified land (after `2026-11-12-dev-hub-bats-tmpdir-unset-on-linux-ci.md` and
`2026-11-11-makefile-agent-load-tests-call-macos-plutil-on-linux-ci.md`). Candidate for grooming: land verification
runs touched bats suites a second time under the uname/TMPDIR Linux simulation used here.
