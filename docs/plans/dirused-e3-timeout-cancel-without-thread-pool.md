# dirused — `/timeout` cancel must not wait for a thread-pool thread (E3 flake diagnosis, then fix)

**Status:** DRAFT — intent pending
**Bug:** `docs/dirused/bugs/2026-11-16-dirused-e3-flakes-when-grace-expires-on-ci.md`
**Tracked:** separately from k3d-manager releases; this file sits in k3d-manager only so `codex-dispatch start` can read it
**Intent approved:** —
**Approval words:** operator 2026-11-17, "yes" to "should I write the E3 diagnosis spec?" (diagnose first, no grace floor)
**Repo / branch:** wilddog64/dirused, `fix/e3-timeout-cancel` from `main`
**Implementer:** Flash (agy `gemini-3.8-flash-medium`). **Verifier:** Claude, from the Acceptance block only.

## You will see / It failed if

- **You will see:** a scan that stops cleanly when `/timeout` expires keeps its partial result, even when the machine is busy.
  The E3 test stops failing on Windows CI.
- **It failed if:** a cooperative scan loses its partial result because the cancel arrived after the grace window, or a hung scan is no longer abandoned at timeout + grace.

## Diagnosis so far (Claude, 2026-11-17, from `src/Dirused.Common/ScanRunner.cs` on `main`)

- Workers run on dedicated threads (`TaskCreationOptions.LongRunning`, line 139), and each scan runs on its own `Thread` (line 49). Neither uses the thread pool.
- The timeout is delivered by `timeoutCts.CancelAfter(duration)` (line 43). In .NET, the `CancelAfter` timer fires by queueing its callback to the **thread pool**.
  If pool threads are blocked (other test classes running concurrently on a 2-vCPU runner), the callback waits for the pool to add a thread, about one every 0.5 s.
- The recurrence at 1926d2e showed the cancel more than 1 s late, which timer jitter alone does not explain; queueing behind a starved pool would.
- **Not proven.** Step 1 below proves or refutes it before any product change.

## Steps

1. **Test-only commit (diagnosis).** Add `TimeoutCancelUnderPoolStarvation` (in `tests/Dirused.Tests.Portable`) in its own xUnit collection with
   `DisableParallelization = true`. It saturates the thread pool, then runs `ScanRunner.Run` with one cooperative target and `Timeout: 1s`:
   - Pin `ThreadPool.SetMinThreads` to a low value for the test and restore the original in `finally`.
   - Occupy every pool thread with work items that block on a `ManualResetEventSlim`, and queue at least 20 more blocking items behind them,
     so newly injected threads pick those up first (the global queue is FIFO) and the timer callback stays queued.
   - Release the blockers in `finally`.
   - Assert the cooperative scan's partial entry is kept and its result says TIMED OUT.
   This commit must be **red on `main`**, in at least 9 of 10 local runs. **If it cannot be made red, stop:** report the runs and do not change product code.
   The thread-pool hypothesis is then wrong and the bug goes back to investigation.
2. **Fix commit.** Deliver the timeout from the worker's own dedicated thread instead of a timer:
   the worker waits `done.Wait(duration)`; if the scan has not finished, it calls `timeoutCts.Cancel()` itself (registered callbacks and `WaitHandle` run synchronously on the caller),
   then waits the grace `min(duration, 2 s)`. Remove `CancelAfter`. The abandon path, the `abandoned` count, the TIMED OUT / CANCELLED reasons and `ct` handling are unchanged.
3. Leave E1, E2 and E3 in `FleetRunnerTests.cs` as they are. They are the positive controls that hung scans are still abandoned and partial results kept.

## Files

- `src/Dirused.Common/ScanRunner.cs`
- `tests/Dirused.Tests.Portable/` — one new test file (the portable project; the implementer picks the file name and states it in the report)

## Contract readers

`ScanRunner.Run` signature and `RunOptions` do not change. Readers: `src/Dirused.Cli` (the `/timeout` and `/parallel` options), `FleetRunnerTests.cs`.
No output format, exit code or option changes.

## Acceptance

```yaml
interface:
  - "ScanRunner.Run(targets, scan, RunOptions(Parallel, Timeout), ct) -> IReadOnlyList<TargetResult>"
must:
  - "with the thread pool saturated, a cooperative scan under Timeout 1s keeps its partial entry and reports TIMED OUT"
  - "a hung scan that ignores its token is still abandoned at timeout + grace and reported TIMED OUT"
  - "a scan that finishes before the timeout is complete with no TIMED OUT error"
must_not:
  - "a cooperative scan loses its partial result because the timeout cancel waited for a thread-pool thread"
  - "ScanRunner uses CancelAfter or any timer callback to deliver /timeout"
evidence:
  - id: E1
    proves: [ "with the thread pool saturated, a cooperative scan under Timeout 1s keeps its partial entry and reports TIMED OUT", "a cooperative scan loses its partial result because the timeout cancel waited for a thread-pool thread" ]
    kind: offline
    how: "TimeoutCancelUnderPoolStarvation in its own non-parallel collection: red on the test-only commit (main code) in at least 9 of 10 local runs, green on the fix in 10 of 10; Claude reruns both"
    intent: "A busy machine no longer makes a timed-out scan throw away what it already found."
  - id: E2
    proves: [ "a hung scan that ignores its token is still abandoned at timeout + grace and reported TIMED OUT", "a scan that finishes before the timeout is complete with no TIMED OUT error" ]
    kind: offline
    how: "positive controls: FleetRunnerTests E1, E2 and E3 unchanged and green on the fix; full portable and Windows suites green on CI for the fix commit"
    intent: "Scans that hang are still cut off on time, and normal scans are unaffected."
  - id: E3
    proves: [ "ScanRunner uses CancelAfter or any timer callback to deliver /timeout" ]
    kind: offline
    how: "git grep -n 'CancelAfter\\|new Timer\\|System.Threading.Timer' src/Dirused.Common/ScanRunner.cs is empty on the fix commit and non-empty on main"
    intent: "The timeout no longer depends on a background timer that can be delayed."
  - id: E4
    proves: [ "a cooperative scan loses its partial result because the timeout cancel waited for a thread-pool thread" ]
    kind: offline
    how: "CI / windows (push) and (pull_request) green on the fix PR, then 5 reruns of the windows job with no E3 failure; Claude records the run IDs"
    intent: "The Windows CI check stops failing on E3, so dirused merges are not blocked by reruns."
```
