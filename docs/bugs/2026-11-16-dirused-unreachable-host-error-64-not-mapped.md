# dirused: an unreachable host can fail with error 64, shown as ERROR instead of UNREACHABLE

**Status:** VERIFIED — fix 91d89ae on wilddog64/dirused#5, CI green 2026-11-16; red at tests-only ebce3e1 (run 43775009024, codes 51 and 64 only); awaiting merge
**Priority:** P3 — wrong label only; the target is still incomplete and the run exits 3
**Introduced by:** pre-existing (test from phase 0 d86655b; mapping from M1b phase 1a ab27363)
**Should have been caught by:** none (depends on how the runner's name resolution fails)
**Introducing change reviewed:** yes (Claude)
**Waiting on:** operator decision — since 2026-11-16 (merge PR #5)
**Prior art:** none. Exact slug: no match; `make find-similar-docs` not run (vector store context missing earlier this session).
**Filed:** 2026-11-16
**Triage:** operator approved 2026-11-16 ("approve P3 and you can dispatch to Luna")
**Intent approved:** operator, 2026-11-16
**Repo / branch:** wilddog64/dirused, `m1b1a-unreachable-codes` (cut from `m1b1a-remote-targets` at 505e3ab; PR to `main` after #4 merges)
**Implementer:** Luna (Codex). **Verifier:** Claude, from the Acceptance block only.

## What happened

`OutputCompatTests.VolumeProbeSupportsUncAndReportsErrors` asserts `VolumeProbe.Probe(@"\\nosuchhost-xyz\c$\")` fails with
53. One windows-latest run got 64 (ERROR_NETNAME_DELETED) for the same commit that passed minutes earlier. The error a
non-existent host returns depends on DNS/NetBIOS behaviour on the machine, so a fixed 53 is not guaranteed.

## Effect

`TargetResolver.ErrorMessage` maps only 53, 67 and 1231 to `UNREACHABLE: <target> (<code>)`. Error 64 (and likely 51,
ERROR_REM_NOT_LIST) prints `ERROR: <target> (64)`. The run still exits 3.

## Fix

Map 51 and 64 to UNREACHABLE in `TargetResolver.ErrorMessage`; have the phase-0 test accept any of 53, 51, 64, 67, 1231.

Make two commits: first the test changes only (they must fail on the current code), then the mapping fix.

## Files

- `src/Dirused.Core/Targets/TargetResolver.cs` (`ErrorMessage` only)
- `tests/Dirused.Tests/RemoteTargetTests.cs`
- `tests/Dirused.Tests/OutputCompatTests.cs` (the `\\nosuchhost-xyz` assertion only)

## Acceptance

```yaml
interface:
  - "TargetResolver.ErrorMessage(target, code) -> UNREACHABLE: <target> (<code>) for 51, 53, 64, 67, 1231"
must:
  - "an unreachable host labelled with error 51 or 64 prints UNREACHABLE: <target> (<code>)"
  - "53, 67, 1231 stay UNREACHABLE; 5 stays ACCESS DENIED; any other code stays ERROR"
  - "the nosuchhost probe test passes whichever unreachable code the runner returns"
must_not:
  - "error 51 or 64 for a target prints ERROR instead of UNREACHABLE"
  - "the nosuchhost probe test fails only because the runner returned 64 instead of 53"
evidence:
  - id: E1
    proves: [ "an unreachable host labelled with error 51 or 64 prints UNREACHABLE: <target> (<code>)", "error 51 or 64 for a target prints ERROR instead of UNREACHABLE" ]
    kind: offline
    how: "Windows xUnit in RemoteTargetTests: ErrorMessage(t, 51) and (t, 64) start with UNREACHABLE; red on the test-only commit (CI windows job), green on the fix commit"
    intent: "A machine that cannot be reached is always called unreachable, whatever error Windows happens to give."
  - id: E2
    proves: [ "53, 67, 1231 stay UNREACHABLE; 5 stays ACCESS DENIED; any other code stays ERROR" ]
    kind: offline
    how: "positive control in the same test: 53, 67, 1231 UNREACHABLE; 5 ACCESS DENIED; 2 ERROR"
    intent: "Locked-out machines and other errors keep their own labels."
  - id: E3
    proves: [ "the nosuchhost probe test passes whichever unreachable code the runner returns", "the nosuchhost probe test fails only because the runner returned 64 instead of 53" ]
    kind: offline
    how: "Claude review: OutputCompatTests asserts the code is one of 51, 53, 64, 67, 1231 (not == 53); CI windows job green"
    intent: "The test suite stops failing at random on CI's network."
```

