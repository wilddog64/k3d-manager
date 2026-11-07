# Bug: lib-foundation `foundation_ensure_vcluster_cli` concurrency test fails intermittently (two callers stage the same `.vcluster.$$`)

**Status:** OPEN
**Priority:** P3 — test-only so far; it flakes CI on unrelated PRs. Separate processes stage different files and end with the same binary
**Approval:** pending (filed by Claude 2026-11-01 while gating lib-foundation PR #74)
**Waiting on:** dispatch — since 2026-11-07
**Affected:** lib-foundation `scripts/lib/system.sh` `foundation_ensure_vcluster_cli` (staging at ~line 2025, `staged_binary="${managed_dir}/.vcluster.$$"`); `_foundation_vcluster_lock` (~line 1965); test `scripts/tests/lib/system.bats` "concurrent callers leave one binary and no lock" (~line 566)

## Symptom

lib-foundation CI run 41367069530 (PR #74, `feat/install-macmon` at `ecbfbf2`, 2026-11-02T00:26Z, ubuntu runner)
failed one test. PR #74 does not touch this code:

```
not ok 191 foundation_ensure_vcluster_cli: concurrent callers leave one binary and no lock
# (in test file scripts/tests/lib/system.bats, line 572)
#   `wait "${first}"; first_status=$?' failed
# cp: cannot create regular file '/tmp/bats-run-l542Y0/test/191/data/lib-foundation/vcluster/0.20.0/.vcluster.8027': File exists
# mv: cannot stat '/tmp/bats-run-l542Y0/test/191/data/lib-foundation/vcluster/0.20.0/.vcluster.8027': No such file or directory
# ERROR: unable to stage vCluster CLI
# ERROR: unable to activate vCluster CLI
```

The same test passed on PR #73 (run 41333720417) and on `main` (39712005489).

## Analysis

- The test starts both callers as background subshells of one bats process. `$$` is the parent PID in a subshell,
  so both callers use the same staging name `.vcluster.8027`.
- The `cp: File exists` from one caller and the `mv: cannot stat` from the other mean both were inside the critical
  section at the same time. `_foundation_vcluster_lock` (`mkdir` lock, 120 × 0.25 s) should prevent that, so the
  lock or its release is also suspect. Something released or skipped it while the other caller held it. Not yet
  explained. Checked on bash 5.3 (m4-air, 2026-11-01): a `RETURN` trap set in a function does not fire when a nested
  function returns, so the early-release theory does not reproduce locally. The CI runner's bash version is unchecked.
  (Superseded 2026-11-07: that check ran plain bash. bats runs tests under `set -eET`, and with `-T` the theory
  reproduces. See Root cause.)
- In production each caller is a separate process with its own `$$`. Two concurrent callers would stage different
  files and both `mv` the same verified binary into place, so the outcome is benign even if the lock fails.

## Root cause (confirmed 2026-11-07)

- bats-core runs every test with `set -eET` (`libexec/bats-core/bats-exec-test` line 2, bats 1.14.0). `-T` (functrace)
  makes functions inherit `RETURN` traps.
- `foundation_ensure_vcluster_cli` sets `trap _foundation_vcluster_release RETURN` and then calls
  `_foundation_vcluster_matches_version`. Under `-T` the trap fires when that inner call returns. The lock dir is
  removed and the trap is cleared (`trap - RETURN`) before the download, copy and `mv`. The second caller then takes
  the lock and runs the critical section at the same time.
- Both callers stage `.vcluster.$$` with the same `$$`, so one caller's release `rm -f` deletes the other's staged file:
  `mv: cannot stat`.
- Minimal reproduction (m4-air, bash 5.3, 2026-11-07):
  `bash -T -c 'inner(){ :; }; outer(){ trap "echo fired; trap - RETURN" RETURN; inner; echo after-inner; }; outer'`
  prints `fired` before `after-inner`; without `-T` the order is reversed.
- Production impact: none found. No k3d-manager caller sets `functrace`; a caller that did would lose the lock.

## Recurrence

- 2026-11-07: lib-foundation PR #77 (`fix/acg-brace-expansion-1.1.21`, lockfile and `dependabot.yml` only), run
  42387319424, ubuntu runner: `not ok 200 … concurrent callers leave one binary and no lock`,
  `mv: cannot stat '…/vcluster/0.20.0/.vcluster.8252'`, `ERROR: unable to activate vCluster CLI`.

## Fix

1. Release the lock without a `RETURN` trap (see Root cause): call `_foundation_vcluster_release` explicitly on each
   return path and in `_foundation_vcluster_abort`, so the lock holds whatever `set -T` the caller has. Add a test that
   runs the function under `set -T`. Reproduce by looping the test, e.g. 200 runs
   with `bats -f 'concurrent callers'`, on Linux (Docker `ubuntu` image with the CI bash) and macOS.
2. Stage under a per-caller unique name: `mktemp "${managed_dir}/.vcluster.XXXXXX"`, not `.vcluster.$$`. Keep the
   cleanup on release. Update the test's `[ ! -e "${managed%/*}/.vcluster.$$" ]` check to a `find -name '.vcluster.*'`
   emptiness check.

## Files

| File | Change |
|---|---|
| lib-foundation `scripts/lib/system.sh` | lock fix, unique staging name |
| lib-foundation `scripts/tests/lib/system.bats` | staging assertion; regression test below |
| lib-foundation `CHANGE.md` | entry |

## Acceptance

```yaml
must:
  M1: two concurrent foundation_ensure_vcluster_cli 0.20.0 callers (background subshells of one shell, stub curl) both exit 0, leave one executable managed binary, no lock dir and no .vcluster.* or foundation-vcluster.* files (paired positive control for N1)
  M2: the concurrency test passes 200 consecutive runs on Linux and on macOS
must_not:
  N1: two callers never hold the lock at the same time; a test that makes the first caller's stub curl sleep while it holds the lock shows the second caller enters the critical section only after the first releases (red if the lock is bypassed)
  N2: the staging path never depends on $$ alone (two subshells of one shell get different staging names)
evidence:
  E1:
    proves: [M1, N1, N2]
    kind: offline
    intent: You will see bats in scripts/tests/lib/system.bats with a scratch XDG_DATA_HOME (asserted not the real one) and stub curl, show the serialized critical section and distinct staging names, red on the pre-fix library.
    what: bats scripts/tests/lib/system.bats
  E2:
    proves: [M2]
    kind: offline
    intent: You will see a 200-iteration loop of the concurrency test pass on the ubuntu CI image and on macOS.
    what: for i in $(seq 200); do bats -f 'concurrent callers' scripts/tests/lib/system.bats || break; done
interface:
  - foundation_ensure_vcluster_cli VERSION (sourced from scripts/lib/system.sh)
  - commands it may call: curl (stubbed), sha256sum/shasum, mkdir/rmdir lock
```
