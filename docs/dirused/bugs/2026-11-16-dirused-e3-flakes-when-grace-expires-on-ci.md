# dirused E3 flakes on Windows CI: the 200 ms grace expires before the cooperative scan returns

**Status:** OPEN — recurred 2026-11-16 at 1926d2e, after the #9 test-only change (609d183); the 1 s timeout did not hold
**Priority:** P3 — test-only, but `windows` is a required check on dirused `main`, so each flake blocks a merge until a rerun passes
**Introduced by:** wilddog64/dirused 588f0c2 (PR #8, merged as 25671fb) — added the hard-abandon wait at timeout + `min(timeout, 2s)`
**Should have been caught by:** offline test
**Introducing change reviewed:** yes (Argon)
**Waiting on:** operator decision — since 2026-11-16 (product grace floor, or diagnose why a cancelled cooperative scan misses a 1 s grace)
**Approved:** operator 2026-11-16 ("approved 1")
**Prior art:** none above threshold. Exact slug: no match. `make find-similar-docs` not run (vector store context missing earlier today).
**Filed:** 2026-11-16

## Symptom

`FleetRunnerTests.E3_TimeoutKeepsPartialAndFailureDoesNotStopOthers` failed on `CI / windows (push)` at 2c4134f (main merged into PR #7's branch), run 43791440439, in both attempts: 403 ms and 463 ms, `Assert.Contains` at `FleetRunnerTests.cs:70` (partial entry missing). The `pull_request` run of the same SHA (43791444019) passed, as did main at 25671fb and every PR #8 run. 60/60 local passes on macOS (30 idle, 30 under 20× `yes` CPU load).

## Diagnosis

E3 runs with `Timeout: 200ms`, so `ScanRunner` waits `200 + min(200, 2000) = 400 ms` before abandoning a scan (`ScanRunner.cs:63`). The slow delegate is cooperative: it returns a partial result as soon as its token is cancelled. Line 69 (incomplete) and the TIMED OUT reason passed while line 70 (partial entry kept) failed, and both durations are ≥ 400 ms, so the scan was abandoned: the delegate had not returned within 200 ms of the cancel.

Likely cause (not proven): `CancelAfter` fires on a thread-pool timer. On a 2-vCPU Windows runner, with xUnit running other test classes concurrently, the callback or the delegate's wake-up can be late by more than 200 ms. Before PR #8 the worker always waited for a cooperative scan, so lateness was harmless.

## Product impact

Low. Real `/timeout` values are seconds or more, giving a 2 s grace. A cooperative scan that is late past the grace loses its partial result and reports TIMED OUT with no entries.

## Fix options

1. Test-only: give E3 a timeout whose grace absorbs runner jitter (e.g. `Timeout: 1s`, grace 1 s), keeping the hung-scan tests E1/E2 on short timeouts.
2. Product: a grace floor (e.g. `max(min(timeout, 2s), 500ms)`) so a cooperative scan always gets a reasonable window.

## Review of the fix (PR #9, 2026-11-16)

Argon blind review, verified by Claude:
- E3 at 1 s *narrows* the race (grace 200 ms → 1 s); it doesn't remove it. Accepted: E3 checks behaviour at a wall-clock deadline, so some timing dependence comes with the test.
- E3 still fails if partial-result handling breaks (`FleetRunnerTests.cs:70`), so its guard survives the change.
- Watch item, not fixed: E1 (`quick` must finish within its 600 ms abandon window) and E2's second sub-test (`manyCalls == 4` needs each scan thread to start within 400 ms) carry the same kind of exposure. It's smaller there, since the margin covers thread start-up rather than a timer callback plus a wake-up. Neither has failed in CI. If one does, give it the same treatment.
- Rejected: an `ObjectDisposedException` on `ct.WaitHandle` can only happen after abandonment, which already fails the test, and the scan thread's catch absorbs it. E4's `max8 > 2` predates PR #8.

## Recurrence (2026-11-16, Claude)

`CI / windows (push)` on branch `m1c-summary-all-bugs` at 1926d2e, run 43981702417, failed E3 at `FleetRunnerTests.cs:70` (`Assert.Contains`, partial entry missing) in 2 s.
`main` at the same SHA passed. The test already carries the #9 change (`Timeout: 1s`, so a 1 s grace), and 2 s is the full timeout plus grace,
so the scan was abandoned again: the delegate had not returned within 1 s of the cancel.

A 1 s lateness is hard to explain by timer jitter alone, so the jitter diagnosis above is weaker now. Next step is to check whether the
cancel reaches the delegate's token at all on the abandon path (`ScanRunner.cs`: the linked `timeoutCts`, its disposal, and when the worker
stops waiting), before choosing fix option 2. Seen while verifying M1c-A; not caused by it (the failing run is the unchanged base commit).

