# M1b-1b: fleet runner — `/file`, `/summary`, `/timeout`, `/parallel`

**Status:** APPROVED — written 2026-11-15; intents approved by the operator 2026-11-15; dispatch after phase 0 (`dirused-m1b0-modular-refactor.md`) merges
**Milestone:** M1 (second half), phase 1b. Runs in parallel with phase 1a (`dirused-m1b-remote-targets.md`, Luna); the two
specs share no file.
**Plan:** k3d-manager `docs/plans/dirused-windows-disk-usage-tool.md` (Command line, Scan correctness: multiple targets, slow links)
**Approval:** operator, 2026-11-15 ("be sure to modulus and we can try to distribute tasks between flash and luna")
**Intent approved:** operator, 2026-11-15
**Approval note:** operator "approved" (2026-11-15) covers the intents below, `\\node` = every `<letter>$` admin share, and Luna for phase 0. Scope item 7 added 2026-11-15 on the operator's "yes" to `//server/share` targets; item 8 and E5 (`/help`) added 2026-11-15 on "go ahead to add /help too".
**Implementer:** Flash (agy `gemini-3.8-flash-medium`). **Verifier:** Claude, from the Acceptance block only.
**Repo / base:** wilddog64/dirused, branch `m1b1b-fleet-runner` from `main` after phase 0 merges.

## You will see / It failed if

- **You will see:** `dirused /file targets.txt /summary` prints used, free and percent for every volume in the list, fullest
  first, in seconds. Without `/summary` it scans each target fully, a few at once (`/parallel 4`), and a slow one stops at
  `/timeout` with what it found so far, marked partial.
- **It failed if:** a target that timed out or failed looks complete, a slow target holds up the others, more than `/parallel`
  scans run at once, or `/summary` walks the folders.

## Context

After phase 0, `ArgParser` parses `/file`, `/summary`, `/timeout` and `/parallel` into `Options` and rejects them in one guard,
`RejectUnavailable`; `ScanRunner.Run(targets, scan, RunOptions, ct)` runs sequentially and takes the scan as a delegate, so tests
can pass a fake scan. Phase 1a makes UNC and `\\node` targets resolve; this phase does not depend on it (tests use local paths).
Build and test gate: the `windows-latest` CI job `windows`, plus the `portable` job. ArgParser, ScanRunner and the renderers
live in the portable `Dirused.Common` project after phase 0, so most of this phase builds and tests on macOS
(`dotnet test tests/Dirused.Tests.Portable`) before pushing.

## Proof of external behaviour

None needed beyond phase 0's: this phase uses only .NET (`Task`, `SemaphoreSlim`, `CancellationTokenSource`,
`Console.CancelKeyPress`) and the phase 0 `VolumeProbe`, proven on windows-latest in run 43758987933 (2026-11-15).

## Scope

1. **`/file <path>`:** one target per line; trim; skip blank lines and lines starting with `#`; UTF-8 with or without BOM.
   Targets from the file are added after any typed on the command line, keeping order. A missing or unreadable file: message
   naming it, exit 1. Remove the `/file` case from `RejectUnavailable`.
2. **`/summary`:** for each target, the volume line only, from `VolumeProbe`; no directory walk. Text: one row per volume
   (target, used, free, total, percent), sorted by percent used, highest first; failed targets listed after, with the error.
   `/json`: the M1a document with empty `directories` and `files` and `"summary": true`. `/csv`: header
   `kind,target,used_bytes,free_bytes,total_bytes,percent_used`. Two targets on the same volume serial print once.
3. **`/timeout <n>[s|m|h]`** (no suffix means seconds; must be > 0): per target. On expiry the scan stops through its
   `CancellationToken`, keeps what it has, and the target is marked incomplete with `TIMED OUT after <n>`; exit 3.
   `Scanner.Walk` checks the token between directories.
4. **`/parallel <n>`** (1–64, default 4): at most n targets scanned at once (`SemaphoreSlim`). Output stays in input order,
   whatever order scans finish in.
5. **Ctrl+C:** cancel all running scans, print the partial results, mark unfinished targets incomplete, exit 3.
6. **One failure never stops the rest:** an exception in one target's scan becomes that target's error; the others continue.
7. **`//` targets (operator, 2026-11-15):** in `ArgParser`, an argument starting with `//` goes to the target parser, not
   the switch branch, so `//server/share` is a target (phase 1a makes `TargetParser` accept it). `/all` and every switch are
   unchanged. Test in `tests/Dirused.Tests.Portable/FleetRunnerTests.cs`: `//server/share` no longer gives `Unknown switch`
   (red on pre-fix code), and `/top 5` still parses as a switch (positive control).
8. **`/help` (operator, 2026-11-15: "go ahead to add /help too"):** replace the two-line `UsageText` with full help: every
   switch available after M1b (`/top`, `/json`, `/csv`, `/all`, `/file`, `/summary`, `/timeout`, `/parallel`, `/help`), one
   line each with its argument and default; the target forms (`.`, relative paths, `C:\x` or `c:/x`, `C:`, `\\server\share`
   or `//server/share`, `\\node` or `//node`, `/all`); that switches take `/`, `-` or `--` in any case; and the exit codes
   (0, 1, 3). Plain text, under 80 columns, no switch listed that is still refused (`/purge`, `/monitor`, `/gui`). The
   short usage line printed on a usage error stays one line plus "Run dirused /help for more." Merge this branch after
   phase 1a, so help never names a target form that does not work yet.
9. **README:** usage lines for the four switches, with a sample `targets.txt`.

## Files

- `src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs`, `src/Dirused.Cli/Program.cs` (Ctrl+C wiring only)
- `src/Dirused.Common/ScanRunner.cs`, `src/Dirused.Core/Scanner.cs` (cancellation checks only)
- `src/Dirused.Common/Renderers/SummaryRenderer.cs` (new), plus the summary branch in the JSON and CSV renderers
- `tests/Dirused.Tests.Portable/FleetRunnerTests.cs` (E1 file parsing, E3, E4: fake scans), `tests/Dirused.Tests/SummaryTests.cs` (E2: real volumes and ACLs)
- `README.md` (usage section; phase 1a edits a different paragraph — rebase if both touch it)

Not touched (phase 1a owns them): `Targets/TargetParser.cs`, `Targets/TargetResolver.cs`, `Targets/NodeShares.cs`, `Native/`.

## Out of scope

UNC and `\\node` resolution (phase 1a); `/monitor`, `/threshold` (M3); deletes (M2); progress display; GUI.

## Acceptance

```yaml
interface:
  - "dirused [target...] /file targets.txt [/summary] [/timeout <n>[s|m|h]] [/parallel <n>] [/top N] [/json|/csv]"
  - "ScanRunner.Run(targets, scan, RunOptions{Parallel, Timeout}, ct) -> results in input order"
  - "exit codes: 0 ok, 1 usage or unreadable target file, 3 any target incomplete, failed or timed out"
must:
  - "/file reads one target per line, skipping blank and # lines, after the typed targets"
  - "/summary prints one volume row per volume, sorted by percent used, without walking any directory"
  - "a target that exceeds /timeout keeps its partial results, is marked TIMED OUT, and the run exits 3"
  - "/parallel n never runs more than n scans at once, and output order equals input order"
  - "one target's exception does not stop the other targets"
  - "/help lists every available switch, the target forms and the exit codes"
must_not:
  - "/file, /summary, /timeout or /parallel exits 1 with 'not available yet (M1b)'"
  - "a timed-out or failed target is reported complete or the run exits 0"
  - "/summary enumerates any directory"
  - "more than /parallel scans run at the same time"
  - "/help omits an available switch or lists a refused one"
evidence:
  - id: E1
    proves: [ "/file reads one target per line, skipping blank and # lines, after the typed targets", "/file, /summary, /timeout or /parallel exits 1 with 'not available yet (M1b)'" ]
    kind: offline
    how: "xUnit: a targets file with a BOM, blank lines, # comments and two temp dirs, plus one typed dir; text output lists the three in typed-then-file order, exit 0; a missing file exits 1 naming it"
    intent: "Point dirused at a list of machines in a text file and it measures every one, in the order you wrote them."
  - id: E2
    proves: [ "/summary prints one volume row per volume, sorted by percent used, without walking any directory", "/summary enumerates any directory" ]
    kind: offline
    how: "xUnit: /summary on a temp tree containing a deny-ACL subdirectory exits 0 with no INCOMPLETE line (a walk would hit the ACL and exit 3); positive control: the same tree without /summary exits 3; C:\\ and D:\\ rows sorted by percent; /csv header as documented"
    intent: "The quick fleet check reads only each drive's used and free space, so it takes seconds, fullest drive first."
  - id: E3
    proves: [ "a target that exceeds /timeout keeps its partial results, is marked TIMED OUT, and the run exits 3", "a timed-out or failed target is reported complete or the run exits 0", "one target's exception does not stop the other targets" ]
    kind: offline
    how: "xUnit with a fake scan delegate: one target blocks until cancelled and returns partial entries, one throws, one returns at once; with Timeout 1s the run exits 3, the slow target is TIMED OUT with its partial entries, the throwing one shows its error, the quick one is complete; positive control: all quick targets exit 0"
    intent: "A slow or broken machine is reported as partial or failed and never holds up or hides the others."
  - id: E4
    proves: [ "/parallel n never runs more than n scans at once, and output order equals input order", "more than /parallel scans run at the same time" ]
    kind: offline
    how: "xUnit with a fake scan that records max concurrent calls and finishes in reverse order: Parallel 2 over 8 targets gives max 2 and results in input order; positive control: Parallel 8 reaches more than 2"
    intent: "dirused scans only as many machines at once as you allow, and the report always comes out in your order."
  - id: E5
    proves: [ "/help lists every available switch, the target forms and the exit codes", "/help omits an available switch or lists a refused one" ]
    kind: offline
    how: "Portable xUnit: ArgParser /help -> Usage; the help text contains /top, /json, /csv, /all, /file, /summary, /timeout, /parallel, //server/share, c:/ and 'exit' (fails on the pre-fix two-line text), contains none of /purge, /monitor, /gui, and every line is under 80 columns; positive control: an invalid target still prints the short usage line"
    intent: "dirused /help shows every switch and path form you can use, and nothing that isn't ready yet."
```
