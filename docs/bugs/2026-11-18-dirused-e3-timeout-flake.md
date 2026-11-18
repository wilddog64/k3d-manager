# dirused: FleetRunnerTests E3 loses the partial result on a slow Windows runner

**Status:** OPEN
**Priority:** P3
**Introduced by:** pre-existing
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-18
**Prior art:** none above threshold (find-similar-docs unavailable: vector store down; exact-slug glob empty)
**Tracked:** dirused (OOB repo), not a k3d-manager release.

## Symptom

wilddog64/dirused Actions run 44402076535 (push, dbec6a7, PR #30), job `windows`, 2026-11-18T21:31Z:
`FleetRunnerTests.E3_TimeoutKeepsPartialAndFailureDoesNotStopOthers` failed at `FleetRunnerTests.cs:70`
(`Assert.Contains(partialEntry, results[0].Result.Directories)`). The pull_request run 44402088455 on the same SHA passed.
PR #30 does not touch `ScanRunner.cs` or `FleetRunnerTests.cs`. First E3 failure in the last 40 runs.

## Likely cause

`ScanRunner.cs:63-81`: after the 1 s timeout cancels the token, the runner waits one more `duration` (1 s) for the scan thread
to return its partial result, then marks it abandoned with an empty `TIMED OUT` result. The test's slow scan wakes from
`ct.WaitHandle.WaitOne` and returns a partial; on a loaded Windows runner the wake-up can miss the 1 s grace, so the partial
is dropped. Test-only timing margin (production timeouts are much longer), not a correctness bug.

## Fix options (operator decision)

- Test only: give E3 a longer timeout (e.g. 3 s, grace 2 s) so scheduling jitter cannot exceed the grace.
- Leave as is and re-run on recurrence.
