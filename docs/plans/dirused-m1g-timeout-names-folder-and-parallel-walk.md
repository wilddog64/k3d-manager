# dirused M1g — a timeout names the folder it stopped in; parallel walk inside one drive

**Status:** Part A ready for dispatch (Luna). Part B held: the VM proof below does not show a gain; waiting on the operator's office probe (B2)
**Repo / branch:** wilddog64/dirused; `m1g-timeout-folder-parallel-walk` from `main` at 6c66022 (M1e merged, PR #12)
**Tracked:** separately from k3d-manager releases (operator, 2026-11-15); out-of-band repo, no ideas-backlog step (operator, 2026-11-17). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Operator words (2026-11-17):** "go ahead for that, and you can dispatch the tasks on you will" — after the office run below and Claude's two suggestions (name the stuck folder; parallel walk inside one target).
**Supersedes:** `docs/plans/dirused-m1c-summary-top-and-fast-scan.md` Part B, B2 (parallel walk). B3 (bounded heap) stays in M1c.
**Risk:** medium (concurrency inside `Scanner`; output adds error lines)
**Implementer:** Luna (Codex). **Verifier:** independent agent from Acceptance only; live evidence by Claude (dirused-dev VM) and the operator (office host).

## Why

Office run, operator, 2026-11-17, v0.0.3, `dirused /top 3 /deep 2 /parallel 8 /timeout 2m /file servers.list`: all four agent
hosts printed `TIMED OUT after 120s` on `d$` with only 1.6–9.1 GB used. On `us03l12agt02` the volume says 9.1G used but the partial
rows reach 546M, so most of the space sits in folders the walk never reached, and nothing says which folder it was reading.

1. **A:** the only error line is `\\host\d$: TIMED OUT after 120s`. The folder being read when the timeout hit is the one the
   operator needs, and the scanner drops it: `Walk` (`src/Dirused.Core/Scanner.cs:53`) returns quietly once the token is cancelled.
2. **B:** `/parallel` runs hosts side by side (`src/Dirused.Common/ScanRunner.cs:15`, `min(parallel, targets)`), but each drive is
   one sequential walk, one SMB listing round trip after another (`Scanner.cs:62-160`). A drive with many small folders is slow
   however many hosts run at once.

## Proof for B

**B1 (Claude, read-only, dirused-dev VM BENTO, Windows 11 ARM64, 2026-11-17T15:27Z, v0.0.3 build 04:05Z).** `\\localhost\c$\Windows`,
83 top-level folders, one `dirused` process per folder (script and output: session 8842446b scratchpad `par/probe.ps1`,
`par/probe-out.txt`):

| Run | Wall time |
|---|---|
| whole tree, one process (today) | 11.4s |
| 83 folders one after another | 17.6s (about 6s of it process start-up) |
| 4 at a time | 13.8s |
| 8 at a time | 12.4s |

No gain on SMB loopback: loopback has almost no round-trip latency, which is what parallel reads hide, and `WinSxS` dominates the
tree. **Not proven: a real remote server.** B is not dispatched on this evidence.

**B2 (operator, office, required before B is dispatched).** On one agent, time the four largest top-level `d$` folders read one after
another, then all four at once (separate `dirused` processes). B goes ahead if "at once" is clearly faster than "one after another".
If it is not, B is dropped and M1g is Part A only.

## Change

### A. Name the folder a stopped scan was reading (`src/Dirused.Core/Scanner.cs`)
- When `Walk` stops early because `ct` is cancelled (the check at the top of `Walk` after the directory was entered, or the
  `if (ct.IsCancellationRequested) break;` in either entry loop), and no deeper call already reported a stop, add
  `ScanError(<that directory's display path>, "not finished: scan stopped")`. A directory never entered (cancelled before its
  listing started) adds nothing.
- Result: a sequential scan reports exactly one such line, the deepest folder in progress; a parallel scan (B) one per folder in
  progress.
- The existing `TIMED OUT after …` / `CANCELLED` lines from `ScanRunner` stay unchanged. No change to the abandoned path
  (`ScanRunner.cs:63-80`, a scan thread hung inside one listing call); that case is out of scope.
- Text, JSON and CSV carry the line through the existing errors list; no renderer or format change.

### B. Parallel walk inside one target (`Scanner.cs`, `ArgParser.cs`, `Options`, `RemoteScan`, `Program.cs`)
- New switch `/threads <n>`, integer 1–32, default 4. Help text: `  /threads <n>        Folders read at once per drive, 1-32 (default: 4)`.
  Error text: `/threads requires an integer between 1 and 32`.
- `Scanner` takes the thread count (constructor or `Scan` argument; keep the existing `internal Scanner(Func<…> reader)` test seam,
  adding the count beside it). `/threads 1` must run exactly today's code path.
- With n > 1: when `Walk` reaches a subdirectory and fewer than n − 1 extra walkers are running for this scan, it walks that
  subdirectory on a **new dedicated thread** (`new Thread { IsBackground = true }`); otherwise inline. The parent joins every child it
  started before it returns its totals.
  **Never use `Task.Run`, `Parallel.*` or other thread-pool threads for directory reads**: blocking SMB calls on the pool caused the
  `/parallel` hang fixed in `docs/plans/dirused-e3-timeout-cancel-without-thread-pool.md`.
- Shared state made safe: the hard-link `seen` set, the `directories`, `files` and `errors` lists (one lock is fine), and
  `PerFileCalls` / `FallbackDirectories` (`Interlocked`).
- `Scan` returns only after every walker thread of that scan has finished, including on cancellation.
- Output order: rows are already sorted at the end. With n > 1, sort `errors` by path (ordinal, ignore case), then reason; with
  n = 1 leave the order as today.
- Hard links: totals stay exact (the shared `seen` set counts each FileId once). Which folder row gets credit for a link that spans
  two folders may differ from the sequential walk; that is the only allowed difference.

## Files

| File | Part |
|---|---|
| `src/Dirused.Core/Scanner.cs` | A, B |
| `src/Dirused.Common/ArgParser.cs` (and the `Options` record wherever it is defined) | B |
| `src/Dirused.Common/RemoteScan.cs` or wherever `RemoteScan.Scan` lives | B (pass the count through) |
| `src/Dirused.Cli/Program.cs` | B (pass `options.Threads`) |
| `tests/Dirused.Tests/ScannerTests.cs` | A, B |
| `tests/Dirused.Tests.Portable/ArgParserTests.cs` | B |
| `README.md` | A, B (document `/threads` and the new error line) |

## Contract readers

Not a k3d-manager contract. dirused output is a user contract: JSON/CSV readers are `tests/Dirused.Tests/OutputCompatTests.cs` and
`tests/Dirused.Tests.Portable/RendererTests.cs`. JSON keys and CSV header do not change; A adds entries to the existing errors list.
Writer of `Options`: `ArgParser.cs:113,130` (positional record; add `Threads` last with a default so other constructors compile).

## Tests

Use the existing `internal Scanner(Func<string, IReadOnlyList<DirEntry>> reader)` seam with a stub reader (an in-memory tree), as
`Test_FallbackWhenListingRejected` does. Names exactly:

1. `Test_StoppedScanNamesFolderInProgress` — stub tree `root\a\deep`, `root\b`; the reader for `root\a\deep` cancels the token,
   then returns entries. Errors contain `root\a\deep: not finished: scan stopped` exactly once, and nothing for `root\b`.
2. `Test_CancelledBeforeStartNamesNothingExtra` — token cancelled before `Scan`; no `not finished` error.
3. `Test_ThreadsSameTotalsRowsAndErrors` — stub tree of 40 folders × 3 levels with sizes, two unreadable folders and one FileId shared
   by files in two different top-level folders. `/threads 1` and `/threads 8`: equal root logical and on-disk totals, equal
   directory rows when the shared FileId is removed, equal errors after sorting. Run the `/threads 8` scan 20 times.
4. `Test_ThreadsReadsConcurrentlyOffThreadPool` — stub reader blocks on a barrier until 4 calls are inside it at once (fails after
   5 s); `/threads 4` completes; every call saw `Thread.CurrentThread.IsThreadPoolThread == false`.
5. `Test_ThreadsJoinBeforeReturn` — stub reader sleeps 200 ms per folder; cancel after 100 ms; after `Scan` returns, record the
   errors count, wait 1 s, the count is unchanged and no reader call starts after return.
6. `Test_ThreadsOneIsSequential` — `/threads 1`: the stub reader sees calls in depth-first order, one at a time.
7. ArgParser (portable): `/threads 1` and `/threads 32` accepted; `/threads 0`, `33` and `x` rejected with the error text; default 4.

Pre-fix red: 1, 3, 4, 5, 7 fail on 6c66022 (1 by missing error, the others by the missing option or overload). Mutations (each must
turn the named test red): drop the stop error (1); report every in-progress ancestor, not only the deepest (1); use `Task.Run` for
child walks (4); return from `Scan` without joining children (5); unsynchronised `seen.Add` or list `Add` (3, under 20 runs).

## What NOT to Do

- Do NOT change `ScanRunner` timeout logic, `/parallel`, the renderers, JSON keys or CSV header.
- Do NOT use thread-pool threads (`Task.Run`, `Parallel.ForEach`, `ThreadPool`) for directory reads.
- Do NOT change hard-link, placeholder or reparse-point handling beyond making it thread-safe.
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the Files table.

## Rules

- LF line endings; keep existing style; no unsolicited refactors.
- Tests use stub readers or temp directories; no network shares.
- If the spec contradicts the code, stop and say so; do not guess.

## Gates

`dotnet build -warnaserror`, `dotnet test tests/Dirused.Tests.Portable`, and on Windows CI `dotnet test tests/Dirused.Tests`.

## Definition of Done

- [ ] A and B implemented; `git status` shows only files in the Files table.
- [ ] Gates green (Windows suite via CI on the pushed branch, checked by Claude).
- [ ] Pre-fix red recorded for tests 1, 3, 4, 5, 7.
- [ ] Mutation table: mutation → test → red.
- [ ] Report back to Claude: changed files, test output, mutation table. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: when a scan stops on /timeout or Ctrl-C, the errors name each folder that was being read, as "<path>: not finished: scan stopped"
  - id: M2
    text: /threads n (1-32, default 4) reads up to n folders of one drive at once on dedicated threads; /threads 1 is today's sequential walk
  - id: M3
    text: for the same tree, /threads n and /threads 1 give the same totals, the same rows (except credit for a hard link spanning two folders) and the same errors
  - id: M4
    text: on a remote share, the default scan is faster than /threads 1
must_not:
  - id: N1
    text: a scan stopped by /timeout reports no folder path other than the target — red today (office run 2026-11-17)
  - id: N2
    text: a /threads scan counts a hard-linked file twice, loses or duplicates a row or error, or returns while a walker thread is still running — red today (no /threads)
  - id: N3
    text: a directory read runs on a .NET thread-pool thread
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: dotnet test tests/Dirused.Tests --filter "FullyQualifiedName~Stopped|FullyQualifiedName~CancelledBeforeStart"
    intent: When a scan runs out of time, it tells you which folder it was stuck in, so you can scan that folder directly.
  - id: E2
    proves: [M2, M3, N2, N3]
    kind: offline
    command: dotnet test tests/Dirused.Tests --filter "FullyQualifiedName~Threads" and dotnet test tests/Dirused.Tests.Portable --filter "FullyQualifiedName~Threads"
    intent: Reading several folders at once gives exactly the same sizes as reading them one by one, and cannot bring back the old hang.
  - id: E3
    proves: [M1, M3, M4]
    kind: live
    command: on the dirused-dev VM, \\localhost\c$ with /threads 1 and the default, timed twice each, same total and rows; \\localhost\c$ /timeout 2s names a folder (Claude)
    intent: On a real Windows share the new build is faster and its numbers match the old walk.
  - id: E4
    proves: [M1, M4]
    kind: live
    command: operator runs dirused \\<one office agent>\d$ /timeout 5m with /threads 1 and with the default, reports wall times and any "not finished" folder
    intent: On your office servers d$ finishes sooner, and if it still times out you see which folder is slow.
interface: dirused command line (text, JSON, CSV output)
```

**Intent approved:** Part A (M1, N1, E1): operator, 2026-11-17, delegated — "go ahead for that, and you can dispatch the tasks on you will". Part B (M2–M4, N2, N3, E2–E4): pending B2.

## Dispatch now: Part A only

Implement only `### A`, tests 1 and 2, the A mutations, and the A line in `README.md`. Do not add `/threads` or touch `ArgParser.cs`,
`Program.cs` or `RemoteScan`. Gate: E1. Part B is a later dispatch from this file.
