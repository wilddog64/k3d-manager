# dirused `/timeout` cannot bound a volume probe that never returns

**Status:** OPEN — captured from the Copilot review of wilddog64/dirused PR #3 (Program.cs:28); approved, not yet dispatched; spec with Acceptance written and intents approved 2026-11-16; dispatched 2026-11-16
**Priority:** P3 — a dead SMB server can stall one worker past `/timeout`; other targets still finish (workaround: Ctrl+C after the rest report, or a smaller `/file`)
**Introduced by:** wilddog64/dirused 97a47fc (M1b phase 1b, merged in febe79d)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (Claude verification)
**Waiting on:** fix running — since 2026-11-16
**Approved:** operator 2026-11-16 ("approve two P3 bugs and can dispatch to Flash and Luna after /clear"); operator clarified one bug per agent: Luna (`gpt-6-luna`, Codex) implements; spec with Acceptance next
**Prior art:** none above threshold. Exact slug: no match. `make find-similar-docs` was unavailable (vector store context `k3d-k3d-cluster` missing).
**Filed:** 2026-11-16
**Intent approved:** operator, 2026-11-16
**Repo / branch:** wilddog64/dirused, `p3-timeout-hung-probe` from `main` at b475154 (1b merged in febe79d)
**Implementer:** Luna (Codex `gpt-6-luna`). **Verifier:** Claude, from the Acceptance block only; live evidence by Claude (`make vm-live`).

## You will see / It failed if

- **You will see:** with `/timeout 30`, a target whose server stops answering mid-probe reports `TIMED OUT after 30s` at about 30 s.
- **It failed if:** that target, and the run, wait as long as Windows' own SMB timeout before reporting.

## Cause

`ScanRunner.Run` (`src/Dirused.Common/ScanRunner.cs`) calls the scan delegate synchronously on its worker and only
checks the timeout after the delegate returns. Full scans check the token between folders, so they stop. The `/summary`
probe is a single blocking Win32 call (`GetDiskFreeSpaceEx` / `GetVolumeInformation`), and no token can interrupt it.
Passing the token through, as the Copilot review suggested, would change nothing observable.

## Fix

In `ScanRunner.Run`, when `/timeout` is set, run each target's scan delegate on its own background thread and have the
worker wait for it up to the timeout plus a grace of `min(timeout, 2s)`:

- returns within that window: today's behaviour, unchanged (a cooperative scan that stops on the token keeps its
  partial results and gets the `TIMED OUT after <d>` error; the existing `FleetRunnerTests.E3` must stay green unedited);
- still running: record `Incomplete(target, "TIMED OUT after <d>")` for that target, discard whatever the delegate later
  returns, and move the worker on to the next target. The abandoned thread must be a background thread so the process
  can exit while it is still blocked.
- Bound: at most `Parallel` abandoned scans may be outstanding. A target that would start while that many are still
  hung is not started and is reported incomplete with reason `SKIPPED: <n> earlier targets still hung past /timeout`.
  An abandoned scan that later returns frees its slot.

Without `/timeout`, behaviour is unchanged (no extra thread). Ctrl+C during a hung call is out of scope.

Make two commits: first the new tests only (they must fail on b475154), then the fix. Push both; do not open a PR.

## Files

- `src/Dirused.Common/ScanRunner.cs`
- `tests/Dirused.Tests.Portable/FleetRunnerTests.cs` (add tests; do not edit the existing E3/E4)

## Acceptance

```yaml
interface:
  - "ScanRunner.Run(targets, scan, RunOptions{Parallel, Timeout}, ct) -> results in input order"
  - "a scan still running at Timeout + min(Timeout, 2s) is reported TIMED OUT after <d>, and its later result is discarded"
  - "SKIPPED: <n> earlier targets still hung past /timeout, when Parallel abandoned scans are outstanding"
must:
  - "with /timeout, a scan that ignores its token and never returns is reported TIMED OUT, and Run returns within Timeout + min(Timeout, 2s) plus scheduling slack"
  - "other targets in the same run still complete normally"
  - "a scan that stops on its token keeps its partial results (existing E3 stays green unedited)"
  - "no more than Parallel abandoned scans are outstanding; further targets are reported SKIPPED and incomplete"
  - "without /timeout, results are identical to today"
must_not:
  - "Run waits for a hung scan longer than Timeout + min(Timeout, 2s) plus slack"
  - "a hung target is reported complete"
  - "abandoned scans grow past Parallel"
evidence:
  - id: E1
    proves: [ "with /timeout, a scan that ignores its token and never returns is reported TIMED OUT, and Run returns within Timeout + min(Timeout, 2s) plus scheduling slack", "other targets in the same run still complete normally", "Run waits for a hung scan longer than Timeout + min(Timeout, 2s) plus slack", "a hung target is reported complete" ]
    kind: offline
    how: "Portable xUnit: targets [hung, quick], Parallel 2, Timeout 300ms; the hung delegate ignores ct and blocks on a ManualResetEventSlim for up to 30s (set in finally); Run returns in under 3s by Stopwatch; hung is Complete=false with a TIMED OUT error; quick is complete; red on b475154 (Run takes ~30s)"
    intent: "A machine whose file server stops answering is marked TIMED OUT at your /timeout instead of holding up the whole run."
  - id: E2
    proves: [ "no more than Parallel abandoned scans are outstanding; further targets are reported SKIPPED and incomplete", "abandoned scans grow past Parallel" ]
    kind: offline
    how: "Portable xUnit: 4 hung targets, Parallel 1, Timeout 200ms; the delegate counts invocations; Run returns in under 3s, invocations == 1, result 0 TIMED OUT, results 1-3 SKIPPED and incomplete; positive control: Parallel 4 over the same 4 hung targets gives 4 invocations, all TIMED OUT; red on b475154"
    intent: "Even a list full of dead machines can't pile up stuck work; dirused skips the rest and says why."
  - id: E3
    proves: [ "a scan that stops on its token keeps its partial results (existing E3 stays green unedited)", "without /timeout, results are identical to today" ]
    kind: offline
    how: "Claude: git diff shows FleetRunnerTests E3/E4 and every other existing test unchanged; dotnet test tests/Dirused.Tests.Portable all green; CI windows + portable jobs green"
    intent: "Slow machines that do stop on time still show what was found before the timeout, and runs without /timeout behave as before."
  - id: E4
    proves: [ "without /timeout, results are identical to today", "other targets in the same run still complete normally" ]
    kind: live
    how: "Claude runs make vm-live on the dirused-dev VM with the fix-commit build: every check that passed at b475154 still passes (a hung SMB server cannot be staged on the VM; E1/E2 carry the hang)"
    intent: "Real scans on Windows, including /timeout and /summary, still work after the change."
```
