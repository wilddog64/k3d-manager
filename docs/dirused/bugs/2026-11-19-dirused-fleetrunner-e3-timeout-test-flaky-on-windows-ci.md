# dirused `FleetRunnerTests.E3` fails on a loaded Windows CI runner: a 1 s grace is too short for the cancelled scan to return its partial result

**Status:** OPEN
**Priority:** P3 — test-only flake; the job passes on rerun and the product behaviour is unchanged
**Introduced by:** unknown (the M2 fleet runner's timeout test)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-19
**Tracked:** dirused (OOB repo), not a k3d-manager release.
**Prior art:** none above threshold (find-similar-docs unavailable; the exact-slug glob found nothing; the 8 sampled earlier failed CI runs all failed on other tests)
**Filed:** 2026-11-19

## Symptom

PR wilddog64/dirused#33, head 529ec87: the `pull_request` Windows job (run 44583852638, job 135771369722) failed in
`Dirused.Tests.Portable.FleetRunnerTests.E3_TimeoutKeepsPartialAndFailureDoesNotStopOthers` at `FleetRunnerTests.cs:70`:
`Assert.Contains(partialEntry, results[0].Result.Directories)` — Item not found. The `push` run on the same SHA
(44583837675) passed. PR #33 does not touch `ScanRunner` or this test.

## Cause

The test gives the slow target `Timeout: 1 s`. `ScanRunner.cs:63` waits `duration + min(duration, 2 s)` = 2 s in total for the scan
thread. The thread must notice cancellation and return its partial result in the extra 1 s. With 4 parallel scans on a busy
Windows runner it did not. The target was then marked abandoned and given an empty `Incomplete` result with no partial
entries (`ScanRunner.cs:80`).

## Proposed fix (for operator decision)

Test only: make the grace deterministic. Either give the test a longer timeout, so the grace is longer too (e.g. `Timeout: 3 s`, with
the slow target waiting at most 10 s), or have the slow scan signal when it has seen cancellation and assert after that signal.
The product's grace rule stays as it is.
