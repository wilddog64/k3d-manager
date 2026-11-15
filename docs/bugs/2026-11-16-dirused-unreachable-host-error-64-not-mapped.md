# dirused: an unreachable host can fail with error 64, shown as ERROR instead of UNREACHABLE

**Status:** OPEN — seen once on wilddog64/dirused#4 CI (run 43773975699, `windows`, 2026-11-16); the same commit passed in run 43773969722
**Priority:** P3 — wrong label only; the target is still incomplete and the run exits 3
**Introduced by:** pre-existing (test from phase 0 d86655b; mapping from M1b phase 1a ab27363)
**Should have been caught by:** none (depends on how the runner's name resolution fails)
**Introducing change reviewed:** yes (Claude)
**Waiting on:** operator decision
**Prior art:** none. Exact slug: no match; `make find-similar-docs` not run (vector store context missing earlier this session).
**Filed:** 2026-11-16

## What happened

`OutputCompatTests.VolumeProbeSupportsUncAndReportsErrors` asserts `VolumeProbe.Probe(@"\\nosuchhost-xyz\c$\")` fails with
53. One windows-latest run got 64 (ERROR_NETNAME_DELETED) for the same commit that passed minutes earlier. The error a
non-existent host returns depends on DNS/NetBIOS behaviour on the machine, so a fixed 53 is not guaranteed.

## Effect

`TargetResolver.ErrorMessage` maps only 53, 67 and 1231 to `UNREACHABLE: <target> (<code>)`. Error 64 (and likely 51,
ERROR_REM_NOT_LIST) prints `ERROR: <target> (64)`. The run still exits 3.

## Proposed fix (not specced)

Map 51 and 64 to UNREACHABLE in `TargetResolver.ErrorMessage`; have the phase-0 test accept any of 53, 51, 64, 67, 1231.
