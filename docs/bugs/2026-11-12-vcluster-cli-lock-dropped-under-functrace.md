# vCluster CLI lock is dropped early under functrace; concurrent callers collide on `.vcluster.$$`

**Status:** VERIFIED — merged in PR #83 (`5d301c1`, 2026-11-12); main CI run 43279250425 green with the new functrace test, 2026-11-12
**Priority:** P3 (proposed: today it only makes a CI test flaky; production callers rarely run with `set -T`)
**Introduced by:** `0a3e404` v0.4.13 (foundation-managed vCluster CLI, #44)
**Should have been caught by:** review
**Prior art:** not run

## Symptom

PR #83 CI run 43245849788 (head `b3a9351d`), job `bats`:

    not ok 214 foundation_ensure_vcluster_cli: concurrent callers leave one binary and no lock
    # (in test file scripts/tests/lib/system.bats, line 693)
    # cp: cannot create regular file '.../vcluster/0.20.0/.vcluster.10122': File exists
    # mv: cannot stat '.../vcluster/0.20.0/.vcluster.10122': No such file or directory
    # ERROR: unable to stage vCluster CLI

The same suite passed on the previous run (`5670513e`), which failed a different test instead (see Related).

## Cause (reproduced 2026-11-12, bash 5.3.20, macOS)

1. `foundation_ensure_vcluster_cli` (`scripts/lib/system.sh` ~2216) takes the `mkdir` lock, then sets
   `trap _foundation_vcluster_release RETURN`. The release function removes the lock directory.
2. bats runs tests under `set -eET` (`bats-core/test_functions.bash:184`). With `-T` (functrace), called functions
   inherit the RETURN trap, so it fires when `_foundation_vcluster_matches_version` returns, the line right after the
   trap. The lock is gone while the caller is still in the critical section.
   Reproduction: `bash -c 'set -T; inner(){ :; }; outer(){ rel(){ echo released; trap - RETURN; }; trap rel RETURN; inner; echo "still inside"; }; outer'`
   prints `released` before `still inside`.
3. The test starts both callers as background subshells of one shell. Subshells keep the parent's `$$`, so both stage
   to the same `${managed_dir}/.vcluster.$$`, and one caller's `mv` takes the other's file.

## Fix (2026-11-12)

The RETURN trap now releases only when `FUNCNAME[0]` is `foundation_ensure_vcluster_cli`, and staging uses
`mktemp "${managed_dir}/.vcluster.XXXXXX"`. New test `holds the lock through the download under functrace` calls the
function directly (bats `run` turns `-eET` off, which hides the bug) and checks the lock exists when curl runs: red on
the pre-fix code (macOS, bats 1.14.0), green after; with the fix the vCluster tests passed 10 of 10 on ubuntu:24.04 with bats 1.13.0.

## Fix direction (original)

Stage with `mktemp "${managed_dir}/.vcluster.XXXXXX"` instead of `$$`, and make the release run only when
`foundation_ensure_vcluster_cli` itself returns (for example by checking `FUNCNAME[1]` in the handler, or releasing
explicitly instead of with a RETURN trap). Add a test that runs the concurrent case under `set -T`, and show it fails
on today's code.

## Related

PR #83 CI run 43233015904 (`5670513e`) failed `run_parallel.bats` test 157 (`a_b-2.rc` missing, sanitized-key
collision case). It did not reproduce in 16 Linux runs (bats 1.13.0, `env -i`, ubuntu:24.04) or 6 macOS runs, and it
passed on the next CI run. Not explained yet.
