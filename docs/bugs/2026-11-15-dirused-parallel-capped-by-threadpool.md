# dirused `/parallel N` is capped by the .NET thread pool, not by N

**Status:** OPEN — red on wilddog64/dirused#3 CI (`portable`, run 43771802268); reproduced on the macOS host
**Priority:** P1 — blocks the open dirused PR #3 (M1b phase 1b); no workaround inside dirused
**Introduced by:** wilddog64/dirused 97a47fc (M1b phase 1b, not yet merged)
**Should have been caught by:** offline test (E4 caught it on a 2-vCPU runner; the 12-core Mac hid it)
**Introducing change reviewed:** yes (Claude verification; passed on the Mac only)
**Waiting on:** operator decision — since 2026-11-15 (intent approval, then dispatch)
**Prior art:** none. Exact slug: no match. `make find-similar-docs` was unavailable (vector store context `k3d-k3d-cluster` missing).
**Filed:** 2026-11-15
**Parent spec:** `docs/plans/dirused-m1b-fleet-runner.md` (E4: `/parallel` caps concurrency)
**Intent approved:** pending
**Repo / branch:** wilddog64/dirused, `m1b1b-fleet-runner` (worktree `~/.local/share/k3d-manager/worktrees/v1.44.0/dirused-m1b1b-fleet-runner`)
**Implementer:** Luna (Codex). **Verifier:** Claude, from the Acceptance block only.

## You will see / It failed if

- **You will see:** `dirused /file fleet.txt /parallel 8` scans 8 machines at once, even from a 2-core VM.
- **It failed if:** a small machine scans only as many targets at once as it has cores, whatever `/parallel` says.

## Evidence

- CI `portable` on ubuntu-latest (2 vCPU): `E4_ParallelCapsConcurrencyAndPreservesInputOrder [FAIL] Expected max concurrency > 2 with Parallel 8, got 2`.
- macOS host, 2026-11-15, .NET 10, at 97a47fc: `DOTNET_PROCESSOR_COUNT=2 dotnet test tests/Dirused.Tests.Portable --filter E4_` peaks at 1 (red);
  `DOTNET_PROCESSOR_COUNT=8` passes.

## Cause

`ScanRunner.Run` (`src/Dirused.Common/ScanRunner.cs:22`) starts one `Task.Run` per target and gates it with a
`SemaphoreSlim(n)`. The scan delegate is synchronous and blocks on disk and SMB I/O. Blocking delegates occupy thread-pool
workers. The pool starts with about one worker per core and adds more slowly, so the semaphore's `n` is never reached on
small machines.

## Fix

In `src/Dirused.Common/ScanRunner.cs` only:

- start `min(n, targets.Count)` dedicated workers with
  `Task.Factory.StartNew(..., CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default)`;
- each worker takes the next index with `Interlocked.Increment` on a shared counter and writes `results[idx]`;
  `Task.WaitAll(workers)`. The worker count replaces the semaphore;
- keep per-target behaviour: timeout via linked CTS (TIMED OUT, with partial results kept), CANCELLED when `ct` is
  cancelled (including targets never started), and an exception becomes that target's error;
- never one thread per target (a `/file` can list hundreds).

## Acceptance

```yaml
interface:
  - "ScanRunner.Run(targets, scan, RunOptions(Parallel, Timeout), ct) — signature unchanged"
must:
  - "with Parallel 8 and blocking scans, more than 2 targets scan at once even when the runtime sees 2 processors"
  - "no more than N targets scan at once, and results stay in input order"
  - "timeout, Ctrl+C and per-target exception behaviour is unchanged"
must_not:
  - "concurrency is limited by the processor count instead of /parallel"
  - "a thread is created per target when the target list is longer than N"
evidence:
  - id: E1
    proves: [ "with Parallel 8 and blocking scans, more than 2 targets scan at once even when the runtime sees 2 processors", "concurrency is limited by the processor count instead of /parallel", "no more than N targets scan at once, and results stay in input order" ]
    kind: offline
    how: "DOTNET_PROCESSOR_COUNT=2 dotnet test tests/Dirused.Tests.Portable --filter E4_ : red at 97a47fc (peak 1), green after the fix; CI portable job (ubuntu 2 vCPU) green on PR #3"
    intent: "Asking for 8 machines at once gets 8 at once, even on a small VM."
  - id: E2
    proves: [ "timeout, Ctrl+C and per-target exception behaviour is unchanged" ]
    kind: offline
    how: "full portable suite green with and without DOTNET_PROCESSOR_COUNT=2; Windows CI job green on PR #3"
    intent: "Timeouts, Ctrl+C and failed machines still report the same way."
  - id: E3
    proves: [ "a thread is created per target when the target list is longer than N" ]
    kind: offline
    how: "Claude review of the diff: worker count is min(N, targets.Count); no per-target StartNew or Thread"
    intent: "A fleet list of hundreds of machines does not start hundreds of threads."
```
